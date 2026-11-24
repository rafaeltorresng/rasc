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
        case saving, opening, ready
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
            case .persistence: "Rasc couldn’t save the recorded thought. Try again to save it."
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
    private var audioExpiry: Task<Void, Never>?
    private var id: UUID?
    private var decodeID: UUID?
    private var buffer: MicBuffer?
    private var retryAudio: VoiceAudio?
    private var pendingTranscript: String?
    private var capturedScratchID: UUID?
    private var captureWasInterrupted = false
    private var lastActivation: ContinuousClock.Instant?
    private var activatedAt: ContinuousClock.Instant?

    var canChangeEnabled: Bool {
        setup != .importing && phase != .saving && phase != .opening && pendingTranscript == nil
    }

    var hasUnsavedAudio: Bool {
        phase == .listening || phase == .finishing || retryAudio != nil
    }

    var needsMicrophoneAccess: Bool {
        phase == .issue(.permission) && input.authorization() != .authorized
    }

    var onNotesChanged: (() -> Void)?
    var onOpenScratch: ((UUID, Bool) async -> Bool)?

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
            cancel()
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

    func handleScratchpadShortcut(_ event: NSEvent) -> Bool {
        guard enabled, shortcutIsActive,
              let shortcut = KeyboardShortcuts.getShortcut(for: .voiceCapture),
              KeyboardShortcuts.Shortcut(event: event) == shortcut else { return false }
        if !event.isARepeat { activate(fromShortcut: true) }
        return true
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
        case .idle:
            begin()
        case .issue(.permission) where fromShortcut && needsMicrophoneAccess:
            if presentWindows { windows.showStatus() }
        case .issue:
            recover()
        case .listening:
            finish()
        case .ready:
            transition(.opening)
            operation = Task { await openSavedScratch() }
        default:
            break
        }
    }

    private func begin() {
        guard repository != nil, setup != .importing else { return }
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
            captureWasInterrupted = interrupted
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
                pendingTranscript = text
                Self.logger.debug("Finish to transcript: \(Self.ms(start), privacy: .public) ms")
                await saveAndOpenScratch()
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
        if phase == .issue(.persistence), pendingTranscript != nil {
            transition(.saving)
            operation = Task { await saveAndOpenScratch() }
        } else if phase == .issue(.transcription), let retryAudio {
            transcribe(retryAudio, owner: token)
        } else {
            begin()
        }
    }

    private func saveAndOpenScratch() async {
        guard let repository, let transcript = pendingTranscript else { return }
        if phase != .saving { transition(.saving) }
        do {
            capturedScratchID = try await repository.createScratch(content: transcript).id
        } catch {
            transition(.issue(.persistence))
            return
        }
        pendingTranscript = nil
        await openSavedScratch()
        onNotesChanged?()
    }

    private func openSavedScratch() async {
        guard let id = capturedScratchID else { return }
        if phase != .opening { transition(.opening) }
        if await onOpenScratch?(id, captureWasInterrupted) == true || onOpenScratch == nil {
            dismiss()
        } else {
            transition(.ready)
        }
    }

    func flushForTermination() async -> Bool {
        if phase == .saving || phase == .opening {
            await operation?.value
        }
        guard let pendingTranscript else { return true }
        guard let repository else { return false }
        do {
            _ = try await repository.createScratch(content: pendingTranscript)
            self.pendingTranscript = nil
            return true
        } catch {
            return false
        }
    }

    func cancel() {
        switch phase {
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
        case .issue, .ready:
            dismiss()
        default:
            break
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
        id = nil
        activatedAt = nil
        pendingTranscript = nil
        capturedScratchID = nil
        captureWasInterrupted = false
        transition(.idle)
        if presentWindows { windows.hideStatus() }
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
