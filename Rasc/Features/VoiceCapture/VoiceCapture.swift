import AppKit
import AVFoundation
import Combine
import Foundation
import KeyboardShortcuts
import OSLog

extension KeyboardShortcuts.Name {
    static let voiceCapture = Self("voiceCapture")
}

@MainActor
final class VoiceCapture: ObservableObject {
    static let shared = VoiceCapture()
    static let preferenceKey = "voiceCaptureEnabled"
    nonisolated static let isSupported: Bool = {
        #if arch(arm64)
        if #available(macOS 26.0, *) { return true }
        #endif
        return false
    }()

    enum Phase: Equatable {
        case idle, checking, starting, listening, finishing, waitingForModel, transcribing, stopping
        case reviewing, saving, kept, undoing
        case issue(Issue)
    }

    enum Issue: Equatable {
        case permission, microphone, noSpeech, transcription, persistence, blocked

        var message: String {
            switch self {
            case .permission: "Allow Rasc to use the microphone in System Settings."
            case .microphone: "Rasc couldn’t receive audio from your microphone."
            case .noSpeech: "Rasc didn’t recognize any speech."
            case .transcription: "Rasc couldn’t transcribe this recording."
            case .persistence: "Rasc couldn’t recover the previous voice capture."
            case .blocked: "Finish the open dialog before recording."
            }
        }
    }

    enum Setup: Equatable {
        case unchecked, missing, installed, importing, preparing, failed
    }

    struct Input: Sendable {
        var authorization: @Sendable () -> AVAuthorizationStatus
        var requestAccess: @Sendable () async -> Bool
        var start: @Sendable (UUID, @escaping @Sendable () -> Void) async throws -> MicBuffer
        var stop: @Sendable (UUID) async -> Void

        static func microphone() -> Self {
            let device = VoiceMicrophone()
            return Self(
                authorization: { AVCaptureDevice.authorizationStatus(for: .audio) },
                requestAccess: { await AVCaptureDevice.requestAccess(for: .audio) },
                start: { id, changed in try await device.start(id: id, onRouteChange: changed) },
                stop: { id in await device.stop(id: id) }
            )
        }
    }

    private static let logger = Logger(subsystem: "app.rasc", category: "VoiceCapture")
    @Published private(set) var enabled: Bool
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var setup: Setup = .unchecked
    @Published private(set) var shortcutIsActive = false
    let inputLevel = VoiceInputLevel()
    @Published private(set) var content = ""
    @Published private(set) var reviewMessage: String?
    @Published private(set) var canRetryAudio = false
    @Published private(set) var awaitingMicrophonePermission = false

    private let preferences: UserDefaults
    private let support: Bool
    private let input: Input
    private let model = VoiceModel()
    private let presentWindows: Bool
    private let injectedDecode: (@Sendable (VoiceAudio) async throws -> String)?
    private var repository: NoteRepository?
    private lazy var windows = VoiceCaptureWindows(capture: self)
    private var handlesShortcut = false
    private var setupTask: Task<Void, Never>?
    private var pressure: DispatchSourceMemoryPressure?
    private var sleepObserver: (any NSObjectProtocol)?
    private var operation: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    private var meter: Task<Void, Never>?
    private var receiptTimer: Task<Void, Never>?
    private var audioExpiry: Task<Void, Never>?
    private var id: UUID?
    private var decodeID: UUID?
    private var buffer: MicBuffer?
    private var retryAudio: VoiceAudio?
    private var receipt: Note?
    private var stagedContent: String?
    private(set) var reviewWrite: Task<Bool, Never>?
    private var recoveryRequired = false
    private var lastActivation: ContinuousClock.Instant?
    private var activatedAt: ContinuousClock.Instant?

    var canChangeEnabled: Bool {
        setup != .importing && phase != .saving && phase != .undoing && !recoveryRequired
    }

    var hasUnsavedAudio: Bool {
        phase == .listening || phase == .finishing || retryAudio != nil
    }

    var needsMicrophoneAccess: Bool {
        phase == .issue(.permission) && input.authorization() != .authorized
    }

    var onNotesChanged: (() -> Void)?
    var onOpenThought: ((UUID) -> Void)?

    init(
        preferences: UserDefaults = .standard,
        supported: Bool = VoiceCapture.isSupported,
        input: Input = .microphone(),
        presentWindows: Bool = true,
        decode: (@Sendable (VoiceAudio) async throws -> String)? = nil
    ) {
        self.preferences = preferences
        support = supported
        enabled = supported && preferences.bool(forKey: Self.preferenceKey)
        self.input = input
        self.presentWindows = presentWindows
        injectedDecode = decode
    }

    func connect(repository: NoteRepository) {
        self.repository = repository
        guard support, presentWindows, !handlesShortcut else { return }
        handlesShortcut = true
        if !enabled { KeyboardShortcuts.disable(.voiceCapture) }
        KeyboardShortcuts.onKeyDown(for: .voiceCapture) { [weak self] in
            Self.logger.debug("Global Voice Capture shortcut received")
            self?.activate(fromShortcut: true)
        }
        refreshShortcut()
    }

    func setEnabled(_ value: Bool) {
        guard support, value != enabled, canChangeEnabled else { return }
        enabled = value
        preferences.set(value, forKey: Self.preferenceKey)
        refreshShortcut()
        if value {
            checkSetup(prepare: true)
        } else {
            setupTask?.cancel()
            setupTask = nil
            setup = .unchecked
            if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
            sleepObserver = nil
            pressure?.cancel()
            pressure = nil
            Task { await model.releaseForMemoryPressure() }
            if phase == .reviewing {
                closeReview()
            } else {
                cancel()
            }
        }
    }

    func refreshShortcut() {
        guard handlesShortcut else { return }
        if enabled {
            KeyboardShortcuts.enable(.voiceCapture)
        } else {
            KeyboardShortcuts.disable(.voiceCapture)
        }
        let active = KeyboardShortcuts.isEnabled(for: .voiceCapture)
        if shortcutIsActive != active { shortcutIsActive = active }
    }

    func checkSetup(prepare: Bool = false) {
        guard enabled, setupTask == nil else { return }
        setupTask = Task {
            let folder = await Task.detached { try? VoiceModelAssets.availableFolder() }.value
            guard !Task.isCancelled else { return }
            setupTask = nil
            setup = folder == nil ? .missing : .installed
            if folder != nil, prepare { prepareModel() }
        }
    }

    func importModel(from folder: URL) {
        guard enabled, setupTask == nil, phase == .idle else { return }
        let install = Task.detached(priority: .userInitiated) { try VoiceModelAssets.install(from: folder) }
        setup = .importing
        setupTask = Task {
            do {
                try await withTaskCancellationHandler {
                    try await install.value
                } onCancel: { install.cancel() }
                try Task.checkCancellation()
                setupTask = nil
                setup = .installed
                prepareModel()
            } catch {
                guard !Task.isCancelled else { return }
                setupTask = nil
                setup = .failed
            }
        }
    }

    func prepareModel() {
        guard enabled, setupTask == nil, phase == .idle else { return }
        observeResources()
        setup = .preparing
        setupTask = Task {
            do {
                try await model.prepare()
                try Task.checkCancellation()
                setup = .installed
            } catch {
                guard !Task.isCancelled else { return }
                setup = .failed
            }
            setupTask = nil
        }
    }

    private func observeResources() {
        guard presentWindows, pressure == nil else { return }
        let pressure = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        pressure.setEventHandler { [weak self] in
            Task { @MainActor in await self?.model.releaseForMemoryPressure() }
        }
        self.pressure = pressure
        pressure.activate()
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.phase == .checking { self.cancel() }
                else { self.interruptInput() }
                await self.model.releaseForMemoryPressure()
            }
        }
    }

    func activate(fromShortcut: Bool = false) {
        guard support else { return }
        guard enabled else {
            if !fromShortcut { SettingsNavigation.revealVoiceCapture() }
            return
        }
        if fromShortcut {
            let now = ContinuousClock.now
            if let lastActivation, lastActivation.duration(to: now) < .milliseconds(180) { return }
            lastActivation = now
        }
        switch phase {
        case .idle, .kept:
            begin()
        case .issue(.permission) where fromShortcut && needsMicrophoneAccess:
            if presentWindows { windows.showStatus() }
        case .issue:
            recover()
        case .listening:
            finish()
        case .reviewing:
            showReview()
        default:
            break
        }
    }

    private func begin() {
        guard let repository, setup != .importing else { return }
        receiptTimer?.cancel()
        receipt = nil
        resetInput()
        let token = UUID()
        id = token
        if presentWindows, windows.hasBlockingSheet {
            transition(.issue(.blocked))
            windows.showStatus()
            return
        }
        activatedAt = .now
        transition(.checking)
        if presentWindows { windows.showStatus() }
        observeResources()

        operation = Task {
            do {
                let pending = try await repository.pendingVoiceDraft()
                guard owns(token) else { return }
                if let pending {
                    id = pending.id
                    content = pending.content
                    stagedContent = pending.content
                    reviewMessage = nil
                    transition(.reviewing)
                    showReview()
                    return
                }
            } catch {
                if owns(token) { transition(.issue(.persistence)) }
                return
            }
            if injectedDecode == nil {
                let available = await Task.detached { (try? VoiceModelAssets.availableFolder()) != nil }.value
                guard owns(token) else { return }
                guard available else {
                    setup = .missing
                    transition(.idle)
                    if presentWindows {
                        windows.hideStatus()
                        SettingsNavigation.revealVoiceCapture()
                    }
                    return
                }
            }

            switch input.authorization() {
            case .authorized: break
            case .notDetermined:
                awaitingMicrophonePermission = true
                let granted = await input.requestAccess()
                guard owns(token) else { return }
                if presentWindows { windows.restorePreviousApplicationAfterPermission() }
                awaitingMicrophonePermission = false
                guard granted else {
                    transition(.issue(.permission))
                    return
                }
            default:
                transition(.issue(.permission))
                return
            }
            transition(.starting)
            let input = self.input
            do {
                let audio = try await input.start(token) { [weak self] in
                    Task { @MainActor in
                        guard self?.id == token else { return }
                        self?.interruptInput()
                    }
                }
                guard owns(token) else { await input.stop(token); return }
                buffer = audio
                monitor(audio, owner: token)
                // Mic readiness takes priority over a cold encoder specialization.
            } catch {
                if owns(token) {
                    await input.stop(token)
                    if owns(token) { transition(.issue(.microphone)) }
                }
            }
        }
    }

    private func monitor(_ audio: MicBuffer, owner token: UUID) {
        let started = ContinuousClock.now
        meter = Task {
            while owns(token) {
                let state = audio.status()
                if phase == .starting, state.first != nil {
                    if let activatedAt {
                        Self.logger.debug("Shortcut to microphone: \(Self.ms(activatedAt), privacy: .public) ms")
                    }
                    transition(.listening)
                    if injectedDecode == nil, setupTask == nil {
                        setupTask = Task {
                            do {
                                try await model.prepare()
                                guard !Task.isCancelled else { return }
                            } catch { /* Finalization exposes the failure and provides Retry. */ }
                            guard !Task.isCancelled else { return }
                            setupTask = nil
                        }
                    }
                }
                if phase == .starting, started.duration(to: .now) > .seconds(2) {
                    interruptInput()
                    return
                }
                if phase == .listening {
                    inputLevel.update(state.rms)
                    if state.full {
                        finish(interrupted: true)
                        return
                    }
                    if let last = state.last, last.duration(to: .now) > .milliseconds(850) {
                        finish(interrupted: true)
                        return
                    }
                }
                do { try await Task.sleep(for: .milliseconds(32)) } catch { return }
            }
        }
    }

    private func interruptInput() {
        if phase == .listening || phase == .finishing {
            finish(interrupted: true)
        } else if phase == .starting, let token = id {
            operation?.cancel()
            meter?.cancel()
            transition(.stopping)
            operation = Task {
                await input.stop(token)
                guard owns(token) else { return }
                transition(.issue(.microphone))
            }
        }
    }

    func finish(interrupted: Bool = false) {
        guard phase == .listening || (interrupted && phase == .finishing),
              let token = id, let buffer else { return }
        if presentWindows {
            if interrupted {
                windows.rememberFinishContext(nil)
            } else if phase == .listening {
                windows.rememberFinishContext()
            }
        }
        operation?.cancel()
        transition(.finishing)
        meter?.cancel()
        inputLevel.update(0)
        operation = Task {
            if !interrupted {
                do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
            }
            await input.stop(token)
            guard owns(token) else { return }
            let audio = buffer.audio()
            self.buffer = nil
            guard audio.activitySeconds >= 0.07 else {
                transition(.issue(interrupted ? .microphone : .noSpeech))
                return
            }
            reviewMessage = interrupted ? "Recording ended early. Check the captured text before keeping it." : nil
            transcribe(audio, owner: token)
        }
    }

    private func transcribe(_ audio: VoiceAudio, owner token: UUID) {
        let attempt = UUID()
        decodeID = attempt
        audioExpiry?.cancel()
        retryAudio = audio
        canRetryAudio = false
        transition(.waitingForModel)
        let start = ContinuousClock.now
        watchdog?.cancel()
        watchdog = Task {
            do { try await Task.sleep(for: .seconds(60)) } catch { return }
            guard owns(token), decodeID == attempt else { return }
            decodeID = nil
            operation?.cancel()
            transcriptionFailed(token)
        }
        operation = Task {
            do {
                let text: String
                if let injectedDecode {
                    transition(.transcribing)
                    text = try await injectedDecode(audio)
                } else {
                    text = try await model.transcribe(audio) { [weak self] in
                        Task { @MainActor in
                            guard let self, self.id == token, self.decodeID == attempt else { return }
                            self.transition(.transcribing)
                        }
                    }
                }
                guard owns(token), decodeID == attempt else { return }
                watchdog?.cancel()
                decodeID = nil
                releaseAudio()
                guard text.contains(where: { $0.isLetter || $0.isNumber }) else {
                    transition(.issue(.noSpeech))
                    return
                }
                content = text
                Self.logger.debug("Finish to transcript: \(Self.ms(start), privacy: .public) ms")
                recoveryRequired = true
                let saved = await stageCurrentReview(token)
                recoveryRequired = false
                guard owns(token) else { return }
                if !saved { reviewMessage = "Rasc couldn’t save a recovery copy. Your transcript is still available here." }
                if enabled {
                    transition(.reviewing)
                    if presentWindows { windows.showReviewAfterFinish() }
                } else {
                    transition(.idle)
                }
            } catch {
                guard owns(token), decodeID == attempt else { return }
                watchdog?.cancel()
                decodeID = nil
                transcriptionFailed(token)
            }
        }
    }

    private func transcriptionFailed(_ token: UUID) {
        transition(.issue(.transcription))
        canRetryAudio = retryAudio != nil
        audioExpiry = Task {
            do { try await Task.sleep(for: .seconds(120)) } catch { return }
            if id == token { releaseAudio() }
        }
    }

    func recover() {
        guard case .issue = phase, let token = id else { return }
        if needsMicrophoneAccess {
            openMicrophoneSettings()
            return
        }
        if phase == .issue(.transcription), let retryAudio {
            if presentWindows { windows.rememberFinishContext() }
            transcribe(retryAudio, owner: token)
        } else {
            begin()
        }
    }

    func showReview() {
        if presentWindows { windows.showReview() }
    }

    func edit(_ text: String) {
        guard phase == .reviewing else { return }
        content = text
    }

    func closeReview() {
        guard phase == .reviewing, let token = id else { return }
        if presentWindows { windows.hideReview() }
        writeReview(token)
    }

    private func writeReview(_ token: UUID) {
        let previous = reviewWrite
        reviewWrite = Task {
            _ = await previous?.value
            guard id == token, content != stagedContent else { return true }
            let saved = await stageCurrentReview(token)
            if !saved, id == token {
                reviewMessage = "Rasc couldn’t save the review. Try Keep again or copy the transcript."
                if presentWindows { windows.showReview() }
            }
            return saved
        }
    }

    private func stageCurrentReview(_ token: UUID) async -> Bool {
        guard let repository else { return false }
        let text = content
        do {
            try await repository.stageVoiceDraft(VoiceDraft(id: token, content: text))
            if id == token { stagedContent = text }
            return true
        } catch {
            return false
        }
    }

    func flushReviewForTermination() async -> Bool {
        if recoveryRequired || phase == .saving || phase == .undoing {
            await operation?.value
        }
        _ = await reviewWrite?.value
        guard phase == .reviewing, let token = id, content != stagedContent else { return true }
        writeReview(token)
        return await reviewWrite?.value ?? true
    }

    func keep() {
        guard phase == .reviewing, let token = id, let repository,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        transition(.saving)
        let captured = VoiceDraft(id: token, content: content)
        operation = Task {
            _ = await reviewWrite?.value
            do {
                if stagedContent == nil {
                    try await repository.stageVoiceDraft(captured)
                }
                let started = ContinuousClock.now
                receipt = try await repository.keepVoiceDraft(captured)
                Self.logger.debug("Keep commit: \(Self.ms(started), privacy: .public) ms")
                content = ""
                stagedContent = nil
                reviewMessage = nil
                id = nil
                onNotesChanged?()
                if presentWindows {
                    windows.hideReview()
                    windows.showStatus(reposition: false)
                }
                transition(.kept)
                receiptTimer = Task {
                    do { try await Task.sleep(for: .seconds(12)) } catch { return }
                    if phase == .kept { dismiss() }
                }
            } catch {
                reviewMessage = "Rasc couldn’t keep this thought. Your transcript is still here."
                transition(.reviewing)
            }
        }
    }

    func cancel() {
        guard !recoveryRequired else { return }
        switch phase {
        case .reviewing:
            discardReview()
        case .checking, .starting, .listening, .finishing, .waitingForModel, .transcribing:
            let owner = id
            id = nil
            if awaitingMicrophonePermission, presentWindows { windows.restorePreviousApplicationAfterPermission() }
            awaitingMicrophonePermission = false
            operation?.cancel()
            resetInput()
            transition(.stopping)
            operation = Task {
                if let owner { await input.stop(owner) }
                dismiss()
            }
        case .issue, .kept:
            dismiss()
        default:
            break
        }
    }

    private func discardReview() {
        guard let token = id, let repository else { return }
        transition(.saving)
        operation = Task {
            _ = await reviewWrite?.value
            do {
                try await repository.discardVoiceDraft(id: token)
                dismiss()
            } catch {
                reviewMessage = "Rasc couldn’t discard this transcript. Try again."
                transition(.reviewing)
            }
        }
    }

    func openThought() {
        guard phase == .kept, let receipt else { return }
        dismiss()
        onOpenThought?(receipt.id)
    }

    func undo() {
        guard phase == .kept, let receipt, let repository else { return }
        transition(.undoing)
        operation = Task {
            do {
                try await repository.undoVoiceKeep(receipt)
                onNotesChanged?()
                dismiss()
            } catch {
                dismiss()
                if presentWindows { windows.showUndoFailure() }
            }
        }
    }

    func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    private func owns(_ token: UUID) -> Bool {
        id == token && !Task.isCancelled
    }

    private func dismiss() {
        resetInput()
        receiptTimer?.cancel()
        receipt = nil
        id = nil
        activatedAt = nil
        content = ""
        stagedContent = nil
        reviewMessage = nil
        reviewWrite = nil
        transition(.idle)
        if presentWindows { windows.hide() }
    }

    private func resetInput() {
        meter?.cancel()
        meter = nil
        buffer = nil
        inputLevel.update(0)
        watchdog?.cancel()
        watchdog = nil
        decodeID = nil
        releaseAudio()
    }

    private func releaseAudio() {
        audioExpiry?.cancel()
        audioExpiry = nil
        retryAudio = nil
        canRetryAudio = false
    }

    private func transition(_ next: Phase) {
        phase = next
        if presentWindows { windows.announce(next) }
    }

    private static func ms(_ start: ContinuousClock.Instant) -> Int {
        Int((start.duration(to: .now) / .milliseconds(1)).rounded())
    }
}
