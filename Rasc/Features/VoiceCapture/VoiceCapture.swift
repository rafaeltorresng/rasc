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
    static let dictationDeliveryPreferenceKey = "voiceDictationDelivery"
    static let dictationAlsoClipboardPreferenceKey = "voiceDictationAlsoCopiesToClipboard"
    static let dictationSaveCopyPreferenceKey = "voiceDictationSaveCopy"
    nonisolated static let isSupported: Bool = {
        #if arch(arm64)
        if #available(macOS 26.0, *) { return true }
        #endif
        return false
    }()

    enum Phase: Equatable {
        case idle, checking, starting, listening, finishing, waitingForModel, transcribing, stopping
        case saving, opening, ready
        case copied, inserted, insertedAndCopied, copiedFallback
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
    @Published private(set) var activeIntent: VoiceCaptureIntent = .scratchpad
    @Published private(set) var setup: Setup = .unchecked
    @Published private(set) var shortcutIsActive = false
    @Published private(set) var dictateShortcutIsActive = false
    @Published private(set) var modifierShortcut: ModifierShortcut?
    @Published private(set) var modifierShortcutIsActive = false
    @Published private(set) var modifierShortcutHasAccess = true
    @Published private(set) var hasAccessibilityAccess = true
    @Published private(set) var output: VoiceCaptureOutput
    @Published private(set) var dictationDelivery: VoiceDictationDelivery
    @Published private(set) var dictationAlsoCopiesToClipboard: Bool
    @Published private(set) var standaloneKeepsHistory: Bool
    let inputLevel = VoiceInputLevel()
    @Published private(set) var canRetryAudio = false
    @Published private(set) var awaitingMicrophonePermission = false
    @Published private(set) var canRemoveInstalledModel = false
    @Published private(set) var isConfirmingCancel = false
    @Published private(set) var recordingElapsedSeconds = 0
    @Published private(set) var confirmCancelDurationSeconds = 0
    @Published private(set) var isEscapeCancelArmed = false

    private let preferences: UserDefaults
    private let support: Bool
    private let input: Input
    private let speech: Speech
    private let modelTimeout: Duration
    private let cancelConfirmationThreshold: Duration
    private let escapeConfirmGuard: Duration
    private let cancelConfirmationTimeout: Duration
    private let presentWindows: Bool
    private let modifierStore: ModifierShortcutStore
    private let accessibilityTrusted: @Sendable () -> Bool
    private let pasteboard: NSPasteboard
    private let insertText: @MainActor @Sendable (String, NSRunningApplication?, NSPasteboard) -> VoiceTextInsertion.Result
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
    private var cancelConfirmationTimeoutTask: Task<Void, Never>?
    private var id: UUID?
    private var decodeID: UUID?
    private var buffer: MicBuffer?
    private var retryAudio: VoiceAudio?
    private var pendingTranscript: String?
    private var pendingConfirmedDelivery: (text: String, token: UUID)?
    private var capturedScratchID: UUID?
    private var captureWasInterrupted = false
    private var targetApplication: NSRunningApplication?
    private var deliveryDismissTask: Task<Void, Never>?
    private var standaloneHistoryTask: Task<Void, Never>?
    private var lastActivation: ContinuousClock.Instant?
    private var activatedAt: ContinuousClock.Instant?
    private var recordingStartedAt: ContinuousClock.Instant?
    private var confirmingCancelStartedAt: ContinuousClock.Instant?
    private var recordedAudioDuration: Duration = .zero
    private var legacyDefaultIntent: VoiceCaptureIntent?

    var modelDownloadSizeBytes: Int64 {
        speech.downloadSizeBytes()
    }

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
    var onRefreshGlobalModifiers: (() -> Void)?

    init(
        preferences: UserDefaults = .standard,
        supported: Bool = VoiceCapture.isSupported,
        input: Input = .microphone(),
        presentWindows: Bool = true,
        speech: Speech = .local(),
        modelTimeout: Duration = .seconds(35),
        cancelConfirmationThreshold: Duration = .seconds(30),
        escapeConfirmGuard: Duration = .milliseconds(400),
        cancelConfirmationTimeout: Duration = .seconds(6),
        modifierStore: ModifierShortcutStore = .shared,
        accessibilityTrusted: @escaping @Sendable () -> Bool = { ModifierShortcutAccess.isTrusted },
        pasteboard: NSPasteboard = .general,
        insertText: @escaping @MainActor @Sendable (String, NSRunningApplication?, NSPasteboard) -> VoiceTextInsertion.Result = {
            VoiceTextInsertion.insert($0, target: $1, pasteboard: $2)
        }
    ) {
        self.preferences = preferences
        support = supported
        enabled = supported && preferences.bool(forKey: Self.preferenceKey)
        self.input = input
        self.presentWindows = presentWindows
        self.speech = speech
        self.modelTimeout = modelTimeout
        self.cancelConfirmationThreshold = cancelConfirmationThreshold
        self.escapeConfirmGuard = escapeConfirmGuard
        self.cancelConfirmationTimeout = cancelConfirmationTimeout
        self.modifierStore = modifierStore
        self.accessibilityTrusted = accessibilityTrusted
        self.pasteboard = pasteboard
        self.insertText = insertText
        modifierShortcut = modifierStore.shortcut
        let trusted = accessibilityTrusted()
        modifierShortcutHasAccess = trusted
        hasAccessibilityAccess = trusted
        let initialOutput = VoiceCaptureOutput(rawValue: preferences.string(forKey: Self.outputPreferenceKey) ?? "") ?? .scratchpad
        output = initialOutput
        if let storedDelivery = preferences.string(forKey: Self.dictationDeliveryPreferenceKey).flatMap(VoiceDictationDelivery.init(rawValue:)) {
            dictationDelivery = storedDelivery
        } else {
            dictationDelivery = (initialOutput == .clipboard) ? .clipboard : .insertAtCursor
        }
        if preferences.object(forKey: Self.dictationAlsoClipboardPreferenceKey) != nil {
            dictationAlsoCopiesToClipboard = preferences.bool(forKey: Self.dictationAlsoClipboardPreferenceKey)
        } else {
            dictationAlsoCopiesToClipboard = true
        }
        if preferences.object(forKey: Self.dictationSaveCopyPreferenceKey) != nil {
            standaloneKeepsHistory = preferences.bool(forKey: Self.dictationSaveCopyPreferenceKey)
        } else if preferences.object(forKey: Self.standaloneHistoryPreferenceKey) != nil {
            standaloneKeepsHistory = preferences.bool(forKey: Self.standaloneHistoryPreferenceKey)
        } else {
            standaloneKeepsHistory = true
        }
        if initialOutput != .scratchpad && preferences.string(forKey: Self.dictationDeliveryPreferenceKey) == nil {
            legacyDefaultIntent = .dictate
        }
    }

    func connect(repository: NoteRepository) {
        self.repository = repository
        if presentWindows && preferences === UserDefaults.standard {
            GlobalShortcutStore.shared.migrateLegacyPreferencesIfNeeded()
            reloadDictationPreferences()
        }
        if enabled { checkSetup(prepare: true) }
        guard support, presentWindows, !handlesShortcut else { return }
        handlesShortcut = true
        if !enabled {
            KeyboardShortcuts.disable(.voiceCapture)
            KeyboardShortcuts.disable(.voiceDictate)
        }
        KeyboardShortcuts.onKeyDown(for: .voiceCapture) { [weak self] in
            Self.logger.debug("Global Voice to Scratchpad shortcut received")
            self?.noteExternalChordInput()
            self?.activate(intent: .scratchpad, fromShortcut: true)
        }
        KeyboardShortcuts.onKeyDown(for: .voiceDictate) { [weak self] in
            Self.logger.debug("Global Dictate shortcut received")
            self?.noteExternalChordInput()
            self?.activate(intent: .dictate, fromShortcut: true)
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
            onRefreshGlobalModifiers?()
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
            onRefreshGlobalModifiers?()
            Task { if !enabled { await speech.release() } }
            cancel()
        }
    }

    /// Assign (or clear) the modifier-only global trigger for Voice to Scratchpad.
    func setModifierShortcut(_ shortcut: ModifierShortcut?) {
        modifierStore.set(shortcut)
        if modifierStore === ModifierShortcutStore.shared {
            if let shortcut {
                _ = GlobalShortcutStore.shared.set(.modifier(shortcut), for: .voiceScratchpad)
            } else if GlobalShortcutStore.shared.trigger(for: .voiceScratchpad)?.asModifier != nil {
                _ = GlobalShortcutStore.shared.set(nil, for: .voiceScratchpad)
            }
        }
        modifierShortcut = modifierStore.shortcut
        refreshModifierShortcut()
    }

    func refreshModifierShortcut() {
        let usesSharedStore = (modifierStore === ModifierShortcutStore.shared)
        if usesSharedStore {
            modifierShortcut = GlobalShortcutStore.shared.trigger(for: .voiceScratchpad)?.asModifier
        } else {
            modifierShortcut = modifierStore.shortcut
        }
        let hadAccess = modifierShortcutHasAccess
        let hasAccess = accessibilityTrusted()
        modifierShortcutHasAccess = hasAccess
        hasAccessibilityAccess = hasAccess
        guard support, presentWindows else { return }

        if usesSharedStore {
            modifierMonitor.stop()
            onRefreshGlobalModifiers?()
            modifierShortcutIsActive = enabled
                && modifierShortcut != nil
                && GlobalModifierDispatcher.shared.activeShortcut(for: .voiceScratchpad) != nil
            return
        }

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
        GlobalModifierDispatcher.shared.isSuspended = recording
    }

    /// Legacy compatibility setter used by existing migration/voice tests.
    func setOutput(_ output: VoiceCaptureOutput) {
        self.output = output
        preferences.set(output.rawValue, forKey: Self.outputPreferenceKey)
        switch output {
        case .scratchpad:
            legacyDefaultIntent = .scratchpad
        case .clipboard:
            legacyDefaultIntent = .dictate
            setDictationDelivery(.clipboard)
        case .insertAtCursor:
            legacyDefaultIntent = .dictate
            setDictationDelivery(.insertAtCursor)
        }
    }

    func setDictationDelivery(_ delivery: VoiceDictationDelivery) {
        guard delivery != dictationDelivery else { return }
        dictationDelivery = delivery
        preferences.set(delivery.rawValue, forKey: Self.dictationDeliveryPreferenceKey)
    }

    func setDictationAlsoCopiesToClipboard(_ value: Bool) {
        guard value != dictationAlsoCopiesToClipboard else { return }
        dictationAlsoCopiesToClipboard = value
        preferences.set(value, forKey: Self.dictationAlsoClipboardPreferenceKey)
    }

    /// Independent preference for saving an extra local copy in Rasc during Dictate.
    func setStandaloneKeepsHistory(_ value: Bool) {
        guard value != standaloneKeepsHistory else { return }
        standaloneKeepsHistory = value
        preferences.set(value, forKey: Self.dictationSaveCopyPreferenceKey)
        preferences.set(value, forKey: Self.standaloneHistoryPreferenceKey)
    }

    /// True when Accessibility is required for legacy `.output` insertion mode.
    var outputNeedsAccessibility: Bool {
        output == .insertAtCursor && !modifierShortcutHasAccess
    }

    /// True when Dictate is configured for `.insertAtCursor` without Accessibility permission.
    var dictationInsertionNeedsAccessibility: Bool {
        dictationDelivery == .insertAtCursor && !hasAccessibilityAccess
    }

    func refreshAccessibilityStatus() {
        let trusted = accessibilityTrusted()
        hasAccessibilityAccess = trusted
        modifierShortcutHasAccess = trusted
    }

    func requestAccessibilityForInsertion() {
        ModifierShortcutAccess.request()
        refreshModifierShortcut()
    }

    func openAccessibilitySettings() {
        ModifierShortcutAccess.openSettings()
    }

    func resetModifierShortcutState() {
        modifierMonitor.reset()
        GlobalModifierDispatcher.shared.reset()
    }

    func noteExternalChordInput() {
        modifierMonitor.noteOtherKeyDown()
        GlobalModifierDispatcher.shared.noteOtherKeyDown()
    }

    func refreshShortcut() {
        refreshModifierShortcut()
        guard handlesShortcut else { return }
        if enabled {
            KeyboardShortcuts.enable(.voiceCapture)
            KeyboardShortcuts.enable(.voiceDictate)
        } else {
            KeyboardShortcuts.disable(.voiceCapture)
            KeyboardShortcuts.disable(.voiceDictate)
        }
        let active = KeyboardShortcuts.isEnabled(for: .voiceCapture)
        if shortcutIsActive != active { shortcutIsActive = active }
        let dictateActive = KeyboardShortcuts.isEnabled(for: .voiceDictate)
        if dictateShortcutIsActive != dictateActive { dictateShortcutIsActive = dictateActive }
    }

    func handleScratchpadShortcut(_ event: NSEvent) -> Bool {
        guard enabled else { return false }
        let eventShortcut = KeyboardShortcuts.Shortcut(event: event)
        if shortcutIsActive,
           let scratch = KeyboardShortcuts.getShortcut(for: .voiceCapture),
           eventShortcut == scratch {
            if !event.isARepeat {
                noteExternalChordInput()
                activate(intent: .scratchpad, fromShortcut: true)
            }
            return true
        }
        if dictateShortcutIsActive,
           let dictate = KeyboardShortcuts.getShortcut(for: .voiceDictate),
           eventShortcut == dictate {
            if !event.isARepeat {
                noteExternalChordInput()
                activate(intent: .dictate, fromShortcut: true)
            }
            return true
        }
        return false
    }

    private func reloadDictationPreferences() {
        if let raw = preferences.string(forKey: Self.dictationDeliveryPreferenceKey),
           let delivery = VoiceDictationDelivery(rawValue: raw) {
            dictationDelivery = delivery
        }
        if preferences.object(forKey: Self.dictationAlsoClipboardPreferenceKey) != nil {
            dictationAlsoCopiesToClipboard = preferences.bool(forKey: Self.dictationAlsoClipboardPreferenceKey)
        }
        if preferences.object(forKey: Self.dictationSaveCopyPreferenceKey) != nil {
            standaloneKeepsHistory = preferences.bool(forKey: Self.dictationSaveCopyPreferenceKey)
        } else if preferences.object(forKey: Self.standaloneHistoryPreferenceKey) != nil {
            standaloneKeepsHistory = preferences.bool(forKey: Self.standaloneHistoryPreferenceKey)
        }
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

    func activate(intent: VoiceCaptureIntent? = nil, fromShortcut: Bool = false) {
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
        let resolvedIntent = intent ?? legacyDefaultIntent ?? .scratchpad
        switch phase {
        case .idle:
            activeIntent = resolvedIntent
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
        case .copied, .inserted, .insertedAndCopied, .copiedFallback:
            dismiss()
            activeIntent = resolvedIntent
            begin()
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
        targetApplication = NSWorkspace.shared.frontmostApplication.flatMap { $0 == .current ? nil : $0 }
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
            if let frontmost = NSWorkspace.shared.frontmostApplication, frontmost != .current {
                targetApplication = frontmost
            }
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
                    recordingStartedAt = .now
                    recordingElapsedSeconds = 0
                    transition(.listening)
                    prepareModel()
                }
                if phase == .starting, started.duration(to: .now) > .seconds(2) {
                    interruptInput()
                    return
                }
                if phase == .listening {
                    inputLevel.update(state.rms)
                    if let recordingStartedAt {
                        let elapsed = Int((recordingStartedAt.duration(to: .now) / .seconds(1)).rounded(.towardZero))
                        if elapsed != recordingElapsedSeconds {
                            recordingElapsedSeconds = elapsed
                        }
                    }
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
        if !interrupted {
            clearCancelConfirmation()
        }
        if let recordingStartedAt {
            recordedAudioDuration = max(recordedAudioDuration, recordingStartedAt.duration(to: .now))
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
            recordedAudioDuration = max(recordedAudioDuration, .seconds(audio.activitySeconds))
            guard audio.activitySeconds >= 0.07 else {
                clearCancelConfirmation()
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
        recordedAudioDuration = max(recordedAudioDuration, .seconds(audio.activitySeconds))
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
                    clearCancelConfirmation()
                    transition(.issue(.noSpeech))
                    return
                }
                pendingTranscript = text
                Self.logger.debug("Finish to transcript: \(Self.ms(start), privacy: .public) ms")
                if isConfirmingCancel {
                    // Hold delivery until the user decides whether to Keep or Discard.
                    pendingConfirmedDelivery = (text, token)
                    return
                }
                await deliverTranscript(text, owner: token)
            } catch {
                guard owns(token), decodeID == attempt else { return }
                clearCancelConfirmation()
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

    /// Deliver a finished transcript according to `activeIntent` and `dictationDelivery`.
    /// Focus is never stolen; no Scratchpad window opens in `.dictate` mode.
    private func deliverTranscript(_ text: String, owner token: UUID) async {
        guard owns(token) else { return }
        switch activeIntent {
        case .scratchpad:
            await saveAndOpenScratch(owner: token)
        case .dictate:
            pendingTranscript = nil
            switch dictationDelivery {
            case .clipboard:
                VoiceTextInsertion.copy(text, to: pasteboard)
                transition(.copied)
                scheduleDeliveryDismiss(.copied, after: .milliseconds(1400))
            case .insertAtCursor:
                let app = currentTargetApplication()
                let result = insertText(text, app, pasteboard)
                switch result {
                case .inserted:
                    if dictationAlsoCopiesToClipboard {
                        VoiceTextInsertion.copy(text, to: pasteboard)
                        transition(.insertedAndCopied)
                        scheduleDeliveryDismiss(.insertedAndCopied, after: .milliseconds(1400))
                    } else {
                        transition(.inserted)
                        scheduleDeliveryDismiss(.inserted, after: .milliseconds(1400))
                    }
                case .copiedToClipboard:
                    // Honest fallback: text is on the clipboard, keep the capsule up.
                    transition(.copiedFallback)
                }
            }
            enqueueStandaloneHistoryIfNeeded(text)
        }
    }

    /// Saves a copy in Rasc's local store only when the user asked for standalone history.
    private func enqueueStandaloneHistoryIfNeeded(_ text: String) {
        guard standaloneKeepsHistory, let repository else { return }
        let previous = standaloneHistoryTask
        standaloneHistoryTask = Task { [weak self] in
            await previous?.value
            do {
                _ = try await repository.createScratch(content: text)
                self?.onNotesChanged?()
            } catch {
                // Standalone history must never block delivery of the transcript.
                Self.logger.error("Standalone history save failed")
            }
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

    private func saveAndOpenScratch(owner token: UUID? = nil) async {
        if let token { guard owns(token) else { return } }
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
        await standaloneHistoryTask?.value
        if phase == .copied || phase == .inserted || phase == .insertedAndCopied || phase == .copiedFallback {
            return true
        }
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

    /// Unified entrypoint for Escape or `✕` button clicks during active capture.
    /// Recordings under `cancelConfirmationThreshold` (30s) cancel immediately;
    /// longer recordings prompt for confirmation without interrupting capture or stealing focus.
    func requestCancel(fromEscape: Bool = false) {
        if isConfirmingCancel {
            if fromEscape,
               let started = confirmingCancelStartedAt,
               started.duration(to: .now) < escapeConfirmGuard {
                return
            }
            confirmDiscard()
            return
        }

        switch phase {
        case .checking, .starting:
            cancel()
        case .listening:
            let elapsed = recordingElapsedDuration()
            if elapsed >= cancelConfirmationThreshold {
                beginCancelConfirmation(elapsed: elapsed)
            } else {
                cancel()
            }
        case .finishing, .waitingForModel, .transcribing:
            let elapsed = max(recordedAudioDuration, recordingElapsedDuration())
            if elapsed >= cancelConfirmationThreshold {
                beginCancelConfirmation(elapsed: elapsed)
            } else {
                cancel()
            }
        case .issue, .ready, .copied, .inserted, .insertedAndCopied, .copiedFallback:
            dismiss()
        default:
            break
        }
    }

    func confirmDiscard() {
        clearCancelConfirmation()
        cancel()
    }

    func keepRecording() {
        let heldDelivery = pendingConfirmedDelivery
        clearCancelConfirmation()
        if let heldDelivery, owns(heldDelivery.token) {
            Task { [weak self] in
                await self?.deliverTranscript(heldDelivery.text, owner: heldDelivery.token)
            }
        }
    }

    func cancel() {
        modifierMonitor.reset()
        GlobalModifierDispatcher.shared.reset()
        clearCancelConfirmation()
        pendingConfirmedDelivery = nil
        switch phase {
        case .checking, .starting, .listening, .finishing, .waitingForModel, .transcribing:
            let owner = id
            id = nil
            decodeID = nil
            pendingTranscript = nil
            capturedScratchID = nil
            if awaitingMicrophonePermission, presentWindows { windows.restorePreviousApplicationAfterPermission() }
            awaitingMicrophonePermission = false
            operation?.cancel()
            resetInput()
            transition(.stopping)
            operation = Task {
                if let owner { await input.stop(owner) }
                dismiss()
            }
        case .issue, .ready, .copied, .inserted, .insertedAndCopied, .copiedFallback:
            dismiss()
        default:
            break
        }
    }

    private func recordingElapsedDuration() -> Duration {
        guard let recordingStartedAt else { return .zero }
        return max(.zero, recordingStartedAt.duration(to: .now))
    }

    private func beginCancelConfirmation(elapsed: Duration) {
        confirmingCancelStartedAt = .now
        confirmCancelDurationSeconds = max(1, Int((elapsed / .seconds(1)).rounded(.towardZero)))
        isConfirmingCancel = true
        if presentWindows {
            windows.announceCancelConfirmation(seconds: confirmCancelDurationSeconds)
        }
        cancelConfirmationTimeoutTask?.cancel()
        cancelConfirmationTimeoutTask = Task { [weak self] in
            do { try await Task.sleep(for: self?.cancelConfirmationTimeout ?? .seconds(6)) } catch { return }
            guard let self, self.isConfirmingCancel else { return }
            self.keepRecording()
        }
    }

    private func clearCancelConfirmation() {
        cancelConfirmationTimeoutTask?.cancel()
        cancelConfirmationTimeoutTask = nil
        confirmingCancelStartedAt = nil
        isConfirmingCancel = false
        confirmCancelDurationSeconds = 0
        pendingConfirmedDelivery = nil
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
        clearCancelConfirmation()
        deliveryDismissTask?.cancel()
        deliveryDismissTask = nil
        targetApplication = nil
        modifierMonitor.reset()
        GlobalModifierDispatcher.shared.reset()
        resetInput()
        id = nil
        activatedAt = nil
        recordingStartedAt = nil
        recordingElapsedSeconds = 0
        recordedAudioDuration = .zero
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
        updateEscapeInterceptor(for: next)
        switch next {
        case .idle, .issue, .saving, .copied, .inserted, .insertedAndCopied, .copiedFallback:
            if releaseAfterCapture { releaseModelWhenSafe() }
        default:
            break
        }
        if presentWindows { windows.announce(next) }
    }

    private func updateEscapeInterceptor(for phase: Phase) {
        let shouldArm: Bool = switch phase {
        case .checking, .starting, .listening, .finishing, .waitingForModel, .transcribing:
            true
        default:
            false
        }
        isEscapeCancelArmed = shouldArm
        guard presentWindows else { return }
        if shouldArm {
            ActiveCaptureEscapeInterceptor.shared.start { [weak self] in
                self?.requestCancel(fromEscape: true)
            }
        } else {
            ActiveCaptureEscapeInterceptor.shared.stop()
        }
    }

    private static func ms(_ start: ContinuousClock.Instant) -> Int {
        Int((start.duration(to: .now) / .milliseconds(1)).rounded())
    }
}
