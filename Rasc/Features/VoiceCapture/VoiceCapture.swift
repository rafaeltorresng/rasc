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
    static let outputPreferenceKey = "voiceCaptureOutput"
    static let standaloneHistoryPreferenceKey = "voiceCaptureStandaloneKeepsHistory"
    nonisolated static let isSupported: Bool = {
        #if arch(arm64)
        if #available(macOS 26.0, *) { return true }
        #endif
        return false
    }()

    enum Phase: Equatable {
        case idle, checking, starting, listening, finishing, waitingForModel, transcribing, stopping
        case saving, opening, ready
        case copied, inserted, copiedFallback
        case issue(Issue)
    }

    enum Issue: Equatable {
        case permission, microphone, noSpeech, modelUnavailable, modelTimeout, lowDiskSpace, transcription, persistence, blocked

        var message: String {
            switch self {
            case .permission: "Allow Rasc to use the microphone in System Settings."
            case .microphone: "Rasc couldn’t receive audio from your microphone."
            case .noSpeech: "Rasc didn’t recognize any speech."
            case .modelUnavailable: "Rasc couldn’t load the local speech model."
            case .modelTimeout: "The speech model is taking too long to load."
            case .lowDiskSpace: "Free up disk space, then retry transcription."
            case .transcription: "Rasc couldn’t transcribe this recording."
            case .persistence: "Rasc couldn’t save the recorded thought. Try again to save it."
            case .blocked: "Finish the open dialog before recording."
            }
        }
    }

    enum Setup: Equatable {
        case unchecked
        case missing
        case downloading(downloaded: Int64, total: Int64)
        case importing
        case preparing
        case installed
        case downloadFailed
        case failed
        case lowDiskSpace
    }

    struct Speech: Sendable {
        typealias Ready = @Sendable () async -> Void
        typealias DownloadProgress = @Sendable (Int64, Int64) -> Void
        var assetsAvailable: @Sendable () -> Bool
        var hasInstalledAssets: @Sendable () -> Bool = { false }
        var downloadSizeBytes: @Sendable () -> Int64 = { 652_304_885 }
        var download: @Sendable (@escaping DownloadProgress) async throws -> Void = { _ in }
        var removeInstalled: @Sendable () throws -> Void = {}
        var prepare: @Sendable () async throws -> Void
        var transcribe: @Sendable (VoiceAudio, @escaping Ready) async throws -> String
        var release: @Sendable () async -> Void

        static func local() -> Self {
            let model = VoiceModel()
            return Self(assetsAvailable: { (try? VoiceModelAssets.availableFolder()) != nil },
                        hasInstalledAssets: { VoiceModelAssets.hasInstalledFolder() },
                        downloadSizeBytes: { VoiceModelAssets.totalManifestBytes() },
                        download: { try await VoiceModelAssets.installFromDownloader(progress: $0) },
                        removeInstalled: { try VoiceModelAssets.removeInstalled() },
                        prepare: { try await model.prepare() },
                        transcribe: { try await model.transcribe($0, modelReady: $1) },
                        release: { await model.releaseForMemoryPressure() })
        }
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
    @Published private(set) var modifierShortcutIsActive = false
    @Published private(set) var modifierShortcutHasAccess = true
    @Published private(set) var output: VoiceCaptureOutput
    @Published private(set) var standaloneKeepsHistory: Bool
    let inputLevel = VoiceInputLevel()
    @Published private(set) var canRetryAudio = false
    @Published private(set) var awaitingMicrophonePermission = false
    @Published private(set) var canRemoveInstalledModel = false

    private let preferences: UserDefaults
    private let support: Bool
    private let input: Input
    private let speech: Speech
    private let modelTimeout: Duration
    private let presentWindows: Bool
    private let modifierStore: ModifierShortcutStore
    private let pasteboard: NSPasteboard
    private lazy var modifierMonitor = ModifierShortcutMonitor()
    private var repository: NoteRepository?
    private lazy var windows = VoiceCaptureWindows(capture: self)
    private var handlesShortcut = false
    private var setupTask: Task<Void, Never>?
    private var reprepareTask: Task<Void, Never>?
    private var pressure: DispatchSourceMemoryPressure?
    private var sleepObserver: (any NSObjectProtocol)?
    private var wakeObserver: (any NSObjectProtocol)?
    private var releasedForResourceConstraint = false
    private var operation: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    private var slowPreparation: Task<Void, Never>?
    private var releaseAfterCapture = false
    private var meter: Task<Void, Never>?
    private var audioExpiry: Task<Void, Never>?
    private var id: UUID?
    private var decodeID: UUID?
    private var buffer: MicBuffer?
    private var retryAudio: VoiceAudio?
    private var pendingTranscript: String?
    private var capturedScratchID: UUID?
    private var captureWasInterrupted = false
    private var targetApplication: NSRunningApplication?
    private var deliveryDismissTask: Task<Void, Never>?
    private var lastActivation: ContinuousClock.Instant?
    private var activatedAt: ContinuousClock.Instant?

    var modelDownloadSizeBytes: Int64 {
        speech.downloadSizeBytes()
    }

    var canChangeEnabled: Bool {
        setup != .importing && phase != .saving && phase != .opening && pendingTranscript == nil
    }

    /// The configured modifier-only trigger, if any. Independent of the
    /// `KeyboardShortcuts` chord binding for `.voiceCapture`.
    var modifierShortcut: ModifierShortcut? { modifierStore.shortcut }

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
        speech: Speech = .local(),
        modelTimeout: Duration = .seconds(35),
        modifierStore: ModifierShortcutStore = .shared,
        pasteboard: NSPasteboard = .general
    ) {
        self.preferences = preferences
        support = supported
        enabled = supported && preferences.bool(forKey: Self.preferenceKey)
        self.input = input
        self.presentWindows = presentWindows
        self.speech = speech
        self.modelTimeout = modelTimeout
        self.modifierStore = modifierStore
        self.pasteboard = pasteboard
        output = VoiceCaptureOutput(rawValue: preferences.string(forKey: Self.outputPreferenceKey) ?? "") ?? .scratchpad
        standaloneKeepsHistory = preferences.bool(forKey: Self.standaloneHistoryPreferenceKey)
    }

    func connect(repository: NoteRepository) {
        self.repository = repository
        if enabled { checkSetup(prepare: true) }
        guard support, presentWindows, !handlesShortcut else { return }
        handlesShortcut = true
        if !enabled { KeyboardShortcuts.disable(.voiceCapture) }
        KeyboardShortcuts.onKeyDown(for: .voiceCapture) { [weak self] in
            Self.logger.debug("Global Voice Capture shortcut received")
            self?.activate(fromShortcut: true)
        }
        refreshShortcut()
        refreshModifierShortcut()
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
            reprepareTask?.cancel()
            reprepareTask = nil
            releasedForResourceConstraint = false
            setup = .unchecked
            canRemoveInstalledModel = false
            if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
            sleepObserver = nil
            if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
            wakeObserver = nil
            pressure?.cancel()
            pressure = nil
            modifierMonitor.stop()
            modifierShortcutIsActive = false
            Task { if !enabled { await speech.release() } }
            cancel()
        }
    }

    /// Assign (or clear) the modifier-only global trigger. Kept independent of
    /// the `KeyboardShortcuts` chord binding; a user can use either or both.
    func setModifierShortcut(_ shortcut: ModifierShortcut?) {
        modifierStore.set(shortcut)
        refreshModifierShortcut()
    }

    func refreshModifierShortcut() {
        guard support, presentWindows else { return }
        let hadAccess = modifierShortcutHasAccess
        let hasAccess = ModifierShortcutAccess.isTrusted
        modifierShortcutHasAccess = hasAccess
        guard enabled, let shortcut = modifierStore.shortcut else {
            modifierMonitor.stop()
            modifierShortcutIsActive = false
            return
        }
        if hasAccess, !hadAccess { modifierMonitor.stop() }
        modifierMonitor.start(shortcut: shortcut) { [weak self] in
            self?.activate(fromShortcut: true)
        }
        modifierShortcutIsActive = modifierMonitor.isRunning
    }

    /// Suppress modifier triggering while a settings recorder is capturing a key.
    func setModifierShortcutRecording(_ recording: Bool) {
        modifierMonitor.isSuspended = recording
    }

    /// Choose where a finished transcript is delivered. `.scratchpad` is the default.
    func setOutput(_ output: VoiceCaptureOutput) {
        guard output != self.output else { return }
        self.output = output
        preferences.set(output.rawValue, forKey: Self.outputPreferenceKey)
    }

    /// Independent preference for `.clipboard` / `.insertAtCursor` modes. Standalone
    /// transcripts are never forced into Home when this is off.
    func setStandaloneKeepsHistory(_ value: Bool) {
        guard value != standaloneKeepsHistory else { return }
        standaloneKeepsHistory = value
        preferences.set(value, forKey: Self.standaloneHistoryPreferenceKey)
    }

    /// True when Accessibility is required for the current output mode.
    var outputNeedsAccessibility: Bool {
        output == .insertAtCursor && !ModifierShortcutAccess.isTrusted
    }

    func requestAccessibilityForInsertion() {
        ModifierShortcutAccess.request()
    }

    func openAccessibilitySettings() {
        ModifierShortcutAccess.openSettings()
    }

    func refreshShortcut() {
        refreshModifierShortcut()
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
        let speech = self.speech
        setupTask = Task(priority: .utility) {
            let (available, installed) = await Task.detached(priority: .utility) {
                (speech.assetsAvailable(), speech.hasInstalledAssets())
            }.value
            guard !Task.isCancelled else { return }
            setupTask = nil
            canRemoveInstalledModel = installed
            setup = available ? .installed : .missing
            if available, prepare { prepareModel() }
        }
    }

    func downloadModel() {
        guard enabled, setupTask == nil, phase == .idle else { return }
        let total = speech.downloadSizeBytes()
        setup = .downloading(downloaded: 0, total: total)
        setupTask = Task {
            do {
                try await speech.download { [weak self] downloaded, totalBytes in
                    Task { @MainActor [weak self] in
                        guard let self, case .downloading = self.setup else { return }
                        self.setup = .downloading(downloaded: downloaded, total: totalBytes)
                    }
                }
                try Task.checkCancellation()
                setupTask = nil
                canRemoveInstalledModel = speech.hasInstalledAssets()
                setup = .installed
                prepareModel()
            } catch is CancellationError {
                guard !Task.isCancelled else { return }
                setupTask = nil
                setup = .missing
            } catch let error as URLError where error.code == .cancelled {
                guard !Task.isCancelled else { return }
                setupTask = nil
                setup = .missing
            } catch {
                guard !Task.isCancelled else { return }
                setupTask = nil
                if (error as? VoiceModel.PreparationError) == .lowDiskSpace ||
                    (error as NSError).domain == NSCocoaErrorDomain && (error as NSError).code == NSFileWriteOutOfSpaceError {
                    setup = .lowDiskSpace
                } else {
                    setup = .downloadFailed
                }
            }
        }
    }

    func cancelModelDownload() {
        guard case .downloading = setup else { return }
        setupTask?.cancel()
        setupTask = nil
        setup = .missing
    }

    func removeInstalledModel() {
        guard enabled, phase == .idle, setupTask == nil, speech.hasInstalledAssets() else { return }
        let speech = self.speech
        setupTask = Task {
            await speech.release()
            do {
                try await Task.detached(priority: .utility) {
                    try speech.removeInstalled()
                }.value
                guard !Task.isCancelled else { return }
                setupTask = nil
                canRemoveInstalledModel = false
                setup = .missing
            } catch {
                guard !Task.isCancelled else { return }
                setupTask = nil
                canRemoveInstalledModel = speech.hasInstalledAssets()
                setup = canRemoveInstalledModel ? .installed : .missing
            }
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
                canRemoveInstalledModel = speech.hasInstalledAssets()
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
        guard enabled, setupTask == nil, phase == .idle || phase == .listening else { return }
        reprepareTask?.cancel()
        reprepareTask = nil
        releasedForResourceConstraint = false
        observeResources()
        setup = .preparing
        setupTask = Task(priority: .utility) {
            do {
                try await speech.prepare()
                try Task.checkCancellation()
                setup = .installed
            } catch is CancellationError {
                guard !Task.isCancelled else { return }
                setup = .installed
            } catch {
                guard !Task.isCancelled else { return }
                setup = (error as? VoiceModel.PreparationError) == .lowDiskSpace ? .lowDiskSpace : .failed
            }
            setupTask = nil
        }
    }

    private func observeResources() {
        guard presentWindows, pressure == nil else { return }
        let pressure = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        pressure.setEventHandler { [weak self, weak pressure] in
            guard let pressure else { return }
            let data = pressure.data
            Task { @MainActor in
                guard let self else { return }
                if data.contains(.warning) || data.contains(.critical) {
                    self.handleResourceConstraint()
                } else if data.contains(.normal) {
                    self.scheduleReprepareAfterConstraint(delay: .seconds(2))
                }
            }
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
                self.handleResourceConstraint()
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleReprepareAfterConstraint(delay: .milliseconds(1500))
            }
        }
    }

    func handleResourceConstraint() {
        reprepareTask?.cancel()
        reprepareTask = nil
        releasedForResourceConstraint = true
        releaseModelWhenSafe()
    }

    func scheduleReprepareAfterConstraint(delay: Duration = .seconds(2)) {
        guard enabled, releasedForResourceConstraint, reprepareTask == nil else { return }
        reprepareTask = Task {
            do { try await Task.sleep(for: delay) } catch { return }
            reprepareTask = nil
            guard enabled, releasedForResourceConstraint, phase == .idle, setup == .installed else { return }
            prepareModel()
        }
    }

    func releaseModelWhenSafe() {
        switch phase {
        case .checking, .starting, .listening, .finishing, .waitingForModel, .transcribing:
            releaseAfterCapture = true
        default:
            releaseAfterCapture = false
            Task { await speech.release() }
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
            let available = await Task.detached(operation: speech.assetsAvailable).value
            guard owns(token) else { return }
            guard available else {
                if case .downloading = setup { } else { setup = .missing }
                transition(.idle)
                if presentWindows {
                    windows.hideStatus()
                    SettingsNavigation.revealVoiceCapture()
                }
                return
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
            // Remember where dictation started. Focus is never stolen; insertion
            // follows the app that is frontmost at finish, falling back to this.
            targetApplication = NSWorkspace.shared.frontmostApplication.flatMap { $0 == .current ? nil : $0 }
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
                    prepareModel()
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
        transition(.finishing)
        let start = ContinuousClock.now
        slowPreparation = Task {
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            guard owns(token), decodeID == attempt else { return }
            transition(.waitingForModel)
        }
        armDeadline(modelTimeout, owner: token, attempt: attempt, issue: .modelTimeout)
        operation = Task {
            do {
                let text = try await speech.transcribe(audio) { [weak self] in
                    await self?.didPrepareModel(owner: token, attempt: attempt)
                }
                guard owns(token), decodeID == attempt else { return }
                clearDecodeTimers()
                releaseAudio()
                guard text.contains(where: { $0.isLetter || $0.isNumber }) else {
                    transition(.issue(.noSpeech))
                    return
                }
                pendingTranscript = text
                Self.logger.debug("Finish to transcript: \(Self.ms(start), privacy: .public) ms")
                await deliverTranscript(text, owner: token)
            } catch {
                guard owns(token), decodeID == attempt else { return }
                let issue: Issue = switch error as? VoiceModel.PreparationError {
                case .lowDiskSpace: .lowDiskSpace
                case .unavailable: .modelUnavailable
                case nil: .transcription
                }
                transcriptionFailed(token, issue: issue)
            }
        }
    }

    private func didPrepareModel(owner token: UUID, attempt: UUID) {
        guard owns(token), decodeID == attempt else { return }
        slowPreparation?.cancel()
        slowPreparation = nil
        if setup == .failed || setup == .lowDiskSpace { setup = .installed }
        transition(.transcribing)
        armDeadline(.seconds(30), owner: token, attempt: attempt, issue: .transcription)
    }

    private func armDeadline(_ duration: Duration, owner token: UUID, attempt: UUID, issue: Issue) {
        watchdog?.cancel()
        watchdog = Task {
            do { try await Task.sleep(for: duration) } catch { return }
            guard owns(token), decodeID == attempt else { return }
            operation?.cancel()
            transcriptionFailed(token, issue: issue)
        }
    }

    private func transcriptionFailed(_ token: UUID, issue: Issue) {
        clearDecodeTimers()
        canRetryAudio = retryAudio != nil
        transition(.issue(issue))
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
        } else if let retryAudio {
            transcribe(retryAudio, owner: token)
        } else {
            begin()
        }
    }

    /// Deliver a finished transcript according to `output`. Focus is never stolen;
    /// no window opens in `.clipboard` or `.insertAtCursor` modes.
    private func deliverTranscript(_ text: String, owner token: UUID) async {
        guard owns(token) else { return }
        switch output {
        case .scratchpad:
            await saveAndOpenScratch()
        case .clipboard:
            pendingTranscript = nil
            await saveStandaloneIfNeeded(text)
            VoiceTextInsertion.copy(text, to: pasteboard)
            transition(.copied)
            scheduleDeliveryDismiss(.copied, after: .milliseconds(1400))
        case .insertAtCursor:
            pendingTranscript = nil
            await saveStandaloneIfNeeded(text)
            let app = currentTargetApplication()
            let result = VoiceTextInsertion.insert(text, target: app, pasteboard: pasteboard)
            switch result {
            case .inserted:
                transition(.inserted)
                scheduleDeliveryDismiss(.inserted, after: .milliseconds(1400))
            case .copiedToClipboard:
                // Honest fallback: text is on the clipboard, keep the capsule up.
                transition(.copiedFallback)
            }
        }
    }

    /// Saves a copy in Rasc's local store only when the user asked for standalone history.
    private func saveStandaloneIfNeeded(_ text: String) async {
        guard standaloneKeepsHistory, let repository else { return }
        do {
            _ = try await repository.createScratch(content: text)
            onNotesChanged?()
        } catch {
            // Standalone history must never block delivery of the transcript.
            Self.logger.error("Standalone history save failed")
        }
    }

    private func currentTargetApplication() -> NSRunningApplication? {
        if let frontmost = NSWorkspace.shared.frontmostApplication, frontmost != .current { return frontmost }
        return targetApplication
    }

    private func scheduleDeliveryDismiss(_ phase: Phase, after delay: Duration) {
        deliveryDismissTask?.cancel()
        deliveryDismissTask = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard let self, self.phase == phase else { return }
            self.dismiss()
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
        if phase == .copied || phase == .inserted || phase == .copiedFallback { return true }
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
        case .issue, .ready, .copied, .inserted, .copiedFallback:
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
        deliveryDismissTask?.cancel()
        deliveryDismissTask = nil
        targetApplication = nil
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
        clearDecodeTimers()
        releaseAudio()
    }

    private func clearDecodeTimers() {
        watchdog?.cancel()
        watchdog = nil
        slowPreparation?.cancel()
        slowPreparation = nil
        decodeID = nil
    }

    private func releaseAudio() {
        audioExpiry?.cancel()
        audioExpiry = nil
        retryAudio = nil
        canRetryAudio = false
    }

    private func transition(_ next: Phase) {
        phase = next
        switch next {
        case .idle, .issue, .saving, .copied, .inserted, .copiedFallback:
            if releaseAfterCapture { releaseModelWhenSafe() }
        default:
            break
        }
        if presentWindows { windows.announce(next) }
    }

    private static func ms(_ start: ContinuousClock.Instant) -> Int {
        Int((start.duration(to: .now) / .milliseconds(1)).rounded())
    }
}
