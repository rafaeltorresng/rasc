import AppKit
import AVFoundation
import Foundation

@MainActor
@Observable
final class OnboardingCoordinator {
    static let replayNotification = Notification.Name("RascReplayOnboarding")

    private let store: OnboardingStore
    private let activeNoteStore: ActiveNoteStore
    private let windowFrameStore: WindowFrameStore
    private let loginItemController: LoginItemController
    private let windowController = OnboardingWindowController()
    private let voiceCapture: VoiceCapture
    private let shortcutStore: GlobalShortcutStore
    private let microphoneStatusProvider: @Sendable () -> AVAuthorizationStatus
    private let accessibilityTrusted: @Sendable () -> Bool
    private let refineAvailabilityCheck: @Sendable () async -> Bool
    private let requestMicrophoneAccessHandler: @Sendable () async -> Bool
    private let presentUIWindows: Bool
    @ObservationIgnored private nonisolated(unsafe) var replayObserver: (any NSObjectProtocol)?

    private weak var bootstrap: AppBootstrap?
    private weak var panelController: PanelController?
    private var practiceScreen: NSScreen?

    private(set) var isActive = false
    private(set) var isReplaying = false
    private(set) var presentedStep: OnboardingStep = .welcome
    private(set) var captureSubstep: OnboardingCaptureSubstep = .waitingForShortcut
    private(set) var scratchpadGuidance = OnboardingScratchpadGuidance.inactive
    private(set) var isYieldingForShortcut = false
    private(set) var shortcutKeycapPressed = false
    private var shortcutKeycapFlashTask: Task<Void, Never>?
    private(set) var loginItemState = LoginItemState.disabled
    private(set) var loginItemError: String?
    private(set) var isUpdatingLoginItem = false

    private(set) var environment: OnboardingEnvironment
    private(set) var selectedFocus: OnboardingFocus
    private(set) var practiceWasKept = false
    private(set) var isRequestingMicrophone = false
    private var practiceMeaningfulTextEntered = false
    private var practiceRefineAttemptedOrSkipped = false

    var isWaitingForShortcut: Bool {
        isActive
            && (presentedStep == .capturePractice || presentedStep == .refinePractice)
            && (captureSubstep == .waitingForShortcut || captureSubstep == .waitingToResume)
    }

    var isLivePracticeActive: Bool {
        isActive
            && (presentedStep == .capturePractice || presentedStep == .refinePractice)
            && (captureSubstep == .liveCapture || captureSubstep == .liveResume)
    }

    var showsVoiceStepInFlow: Bool {
        environment.isVoiceSupported && selectedFocus == .scratchpadAndVoice
    }

    var progressStepCount: Int {
        showsVoiceStepInFlow ? 4 : 3
    }

    var isVoiceEnabled: Bool {
        voiceCapture.enabled
    }

    var voiceCaptureSession: VoiceCapture {
        voiceCapture
    }

    var shortcutStoreInstance: GlobalShortcutStore {
        shortcutStore
    }

    var voiceSetupState: VoiceCapture.Setup {
        voiceCapture.setup
    }

    var voiceDownloadSizeBytes: Int64 {
        voiceCapture.modelDownloadSizeBytes
    }

    var dictationDelivery: VoiceDictationDelivery {
        voiceCapture.dictationDelivery
    }

    var dictationAlsoCopiesToClipboard: Bool {
        voiceCapture.dictationAlsoCopiesToClipboard
    }

    var dictationSaveCopyInRasc: Bool {
        voiceCapture.standaloneKeepsHistory
    }

    var needsAccessibilityForScratchpadShortcut: Bool {
        shortcutStore.trigger(for: .toggleScratchpad)?.needsAccessibilityPermission == true
            && !environment.isAccessibilityTrusted
    }

    var needsAccessibilityForVoiceSetup: Bool {
        guard !environment.isAccessibilityTrusted else { return false }
        let hasDictateShortcut = shortcutStore.trigger(for: .voiceDictate) != nil
        let insertWithDictate = hasDictateShortcut && voiceCapture.dictationDelivery == .insertAtCursor
        let modifierVoice =
            shortcutStore.trigger(for: .voiceScratchpad)?.needsAccessibilityPermission == true
            || shortcutStore.trigger(for: .voiceDictate)?.needsAccessibilityPermission == true
        return insertWithDictate || modifierVoice
    }

    init(
        store: OnboardingStore = OnboardingStore(),
        activeNoteStore: ActiveNoteStore = ActiveNoteStore(),
        windowFrameStore: WindowFrameStore = WindowFrameStore(),
        loginItemController: LoginItemController = LoginItemController(),
        voiceCapture: VoiceCapture = .shared,
        shortcutStore: GlobalShortcutStore = .shared,
        isVoiceSupported: Bool = VoiceCapture.isSupported,
        presentUIWindows: Bool = true,
        microphoneStatus: (@Sendable () -> AVAuthorizationStatus)? = nil,
        microphoneAuthorized: (@Sendable () -> Bool)? = nil,
        accessibilityTrusted: @escaping @Sendable () -> Bool = {
            ModifierShortcutAccess.isTrusted
        },
        refineAvailabilityCheck: @escaping @Sendable () async -> Bool = {
            let provider = FoundationModelsRefinementProvider()
            let availability = await provider.availability(
                for: RefinementRequest(
                    snapshot: NoteSnapshot(noteID: UUID(), revision: 0, text: "status check")
                )
            )
            return availability == .available
        },
        requestMicrophoneAccessHandler: @escaping @Sendable () async -> Bool = {
            await AVCaptureDevice.requestAccess(for: .audio)
        }
    ) {
        self.store = store
        self.activeNoteStore = activeNoteStore
        self.windowFrameStore = windowFrameStore
        self.loginItemController = loginItemController
        self.voiceCapture = voiceCapture
        self.shortcutStore = shortcutStore
        self.presentUIWindows = presentUIWindows
        if let microphoneStatus {
            self.microphoneStatusProvider = microphoneStatus
        } else if let microphoneAuthorized {
            self.microphoneStatusProvider = { microphoneAuthorized() ? .authorized : .notDetermined }
        } else {
            self.microphoneStatusProvider = { AVCaptureDevice.authorizationStatus(for: .audio) }
        }
        self.accessibilityTrusted = accessibilityTrusted
        self.refineAvailabilityCheck = refineAvailabilityCheck
        self.requestMicrophoneAccessHandler = requestMicrophoneAccessHandler

        let initialEnvironment = OnboardingEnvironment(
            isVoiceSupported: isVoiceSupported,
            isVoiceModelInstalled: voiceCapture.setup == .installed || voiceCapture.setup == .preparing,
            microphoneStatus: self.microphoneStatusProvider(),
            isAccessibilityTrusted: accessibilityTrusted(),
            isRefineAvailable: false
        )
        self.environment = initialEnvironment
        if let savedFocus = store.focus {
            self.selectedFocus = isVoiceSupported ? savedFocus : .scratchpadOnly
        } else {
            self.selectedFocus = isVoiceSupported ? .scratchpadAndVoice : .scratchpadOnly
        }
        self.practiceWasKept = store.practiceKept
        self.practiceMeaningfulTextEntered = store.meaningfulTextEntered

        windowController.onWindowClosedByUser = { [weak self] in
            self?.dismissByWindowClose()
        }

        if presentUIWindows {
            replayObserver = NotificationCenter.default.addObserver(
                forName: Self.replayNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    await self?.replayOnboarding()
                }
            }
        }
    }

    deinit {
        if let replayObserver {
            NotificationCenter.default.removeObserver(replayObserver)
        }
    }

    func prepare(
        bootstrap: AppBootstrap,
        forceReset: Bool
    ) async {
        self.bootstrap = bootstrap

        let panel = await bootstrap.awaitPanel()
        panelController = panel

        guard let repository = panel?.repository else { return }

        let hasSavedNotes: Bool
        do {
            hasSavedNotes = try await repository.fetchMostRecent() != nil
        } catch {
            hasSavedNotes = false
        }

        let shouldPresent = OnboardingEligibility.shouldPresentOnboarding(
            OnboardingEligibility.Context(
                store: store,
                activeNoteStore: activeNoteStore,
                hasSavedNotes: hasSavedNotes,
                hasSavedWindowFrame: windowFrameStore.hasSavedFrame,
                forceReset: forceReset
            )
        )

        await refreshEnvironmentAsync()
        guard shouldPresent else { return }

        activateOnboardingSession(restoringProgress: true)
    }

    func replayOnboarding() async {
        if panelController == nil, let panel = await bootstrap?.awaitPanel() {
            panelController = panel
        }
        await refreshEnvironmentAsync()
        isReplaying = true
        if let savedFocus = store.focus {
            selectedFocus = environment.isVoiceSupported ? savedFocus : .scratchpadOnly
        } else {
            selectedFocus = environment.isVoiceSupported ? .scratchpadAndVoice : .scratchpadOnly
        }
        practiceWasKept = false
        practiceMeaningfulTextEntered = false
        practiceRefineAttemptedOrSkipped = false
        activateOnboardingSession(restoringProgress: false)
    }

    func resetOnboardingStateOnly() {
        isReplaying = false
        store.resetOnboardingStateOnly()
        selectedFocus = environment.isVoiceSupported ? .scratchpadAndVoice : .scratchpadOnly
        practiceWasKept = false
        practiceMeaningfulTextEntered = false
        practiceRefineAttemptedOrSkipped = false
        refreshEnvironmentSync()
        activateOnboardingSession(restoringProgress: false)
    }

    func skipSetup() {
        let wasReplaying = isReplaying
        isReplaying = false
        if !wasReplaying {
            store.markCompleted()
        }
        tearDown(preservePracticeNote: wasReplaying)
    }

    func dismissByWindowClose() {
        let wasReplaying = isReplaying
        isReplaying = false
        tearDown(preservePracticeNote: wasReplaying)
    }

    func selectFocus(_ focus: OnboardingFocus) {
        let resolved: OnboardingFocus = environment.isVoiceSupported ? focus : .scratchpadOnly
        selectedFocus = resolved
        if !isReplaying {
            store.focus = resolved
        }
    }

    func continueFromWelcome() {
        if !isReplaying {
            store.focus = selectedFocus
            store.persistProgress(step: .shortcut)
        }
        refreshEnvironmentSync()
        presentedStep = .shortcut
        Task { await refreshEnvironmentAsync() }
    }

    func continueFromShortcut() {
        refreshEnvironmentSync()
        presentedStep = .capturePractice
        captureSubstep = .waitingForShortcut
        if !isReplaying {
            store.persistProgress(step: .capturePractice, captureSubstep: .waitingForShortcut)
        }
        isYieldingForShortcut = true
        windowController.resignKey()
    }

    func openScratchpadForPracticeDirectly() async {
        _ = await handleGlobalShortcut()
    }

    func continueFromResumeCard() {
        if !isReplaying {
            store.resumeCompleted = true
        }
        advanceAfterPractice()
    }

    func enableVoiceSetup() {
        guard environment.isVoiceSupported else { return }
        if !isReplaying {
            store.voiceOptedIn = true
        }
        voiceCapture.enableAndDownloadIfMissing()
        refreshEnvironmentSync()
    }

    func downloadVoiceModel() {
        guard environment.isVoiceSupported else { return }
        voiceCapture.enableAndDownloadIfMissing()
        refreshEnvironmentSync()
    }

    func requestMicrophonePermission() async {
        guard !isRequestingMicrophone else { return }
        if environment.isMicrophoneDenied {
            openMicrophoneSettings()
            return
        }
        isRequestingMicrophone = true
        defer { isRequestingMicrophone = false }
        let granted = await requestMicrophoneAccessHandler()
        let liveStatus = microphoneStatusProvider()
        if liveStatus == .denied || liveStatus == .restricted {
            environment.microphoneStatus = liveStatus
        } else if granted || liveStatus == .authorized {
            environment.microphoneStatus = .authorized
        } else {
            environment.microphoneStatus = .denied
        }
    }

    func openMicrophoneSettings() {
        voiceCapture.openMicrophoneSettings()
    }

    func requestAccessibilityPermission() {
        voiceCapture.requestAccessibilityForInsertion()
        refreshEnvironmentSync()
    }

    func openAccessibilitySettings() {
        voiceCapture.openAccessibilitySettings()
    }

    func continueFromVoiceSetup() {
        advanceToCompletion()
    }

    func skipVoiceSetup() {
        advanceToCompletion()
    }

    func finish() {
        let wasReplaying = isReplaying
        isReplaying = false
        if !wasReplaying {
            store.markCompleted()
        }
        tearDown(preservePracticeNote: true)
        Task { @MainActor [weak self] in
            await self?.bootstrap?.openHome()
        }
    }

    func enableLaunchAtLogin() {
        isUpdatingLoginItem = true
        loginItemError = nil
        defer { isUpdatingLoginItem = false }

        do {
            try loginItemController.setEnabled(true)
            refreshLoginItemState()
        } catch {
            refreshLoginItemState()
            loginItemError = "Couldn't enable Launch at Login. You can try again in Settings."
        }
    }

    func handleGlobalShortcut() async -> Bool {
        guard isWaitingForShortcut else { return false }

        if captureSubstep == .waitingToResume {
            captureSubstep = .liveResume
            if !isReplaying {
                store.persistProgress(step: .capturePractice, captureSubstep: .liveResume)
            }
            isYieldingForShortcut = false
            if presentUIWindows { windowController.hide() }

            var guidance = OnboardingScratchpadGuidance(isActive: true)
            guidance.showEmptyHint = false
            guidance.showRefineHint = false
            guidance.showEscapeHint = true
            guidance.showKeepHint = true
            guidance.isResumeBeat = true
            guidance.canShowRefineHint = environment.isRefineAvailable
            scratchpadGuidance = guidance
            panelController?.scratchpadGuidance = guidance

            await panelController?.reopenCurrentScratchForOnboarding()
            practiceScreen = panelController?.panel.screen
            return true
        }

        captureSubstep = .liveCapture
        if !isReplaying {
            store.persistProgress(step: .capturePractice, captureSubstep: .liveCapture)
        }
        isYieldingForShortcut = false
        if presentUIWindows { windowController.hide() }

        var guidance = OnboardingScratchpadGuidance(isActive: true)
        guidance.canShowRefineHint = environment.isRefineAvailable
        scratchpadGuidance = guidance
        panelController?.scratchpadGuidance = guidance

        await panelController?.startNewScratchForOnboarding()
        practiceScreen = panelController?.panel.screen
        return true
    }

    func shouldInterceptPanelToggle() -> Bool {
        isWaitingForShortcut
    }

    func shouldFlashShortcutKeycap() -> Bool {
        isActive && (presentedStep == .shortcut || isWaitingForShortcut)
    }

    func flashShortcutKeycap() {
        shortcutKeycapFlashTask?.cancel()
        shortcutKeycapPressed = true
        shortcutKeycapFlashTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled else { return }
            shortcutKeycapPressed = false
        }
    }

    #if DEBUG
    func restoreVoiceSetupForTest() {
        activateOnboardingSession(restoringProgress: true)
    }
    #endif

    func refreshEnvironmentSync() {
        environment.microphoneStatus = microphoneStatusProvider()
        environment.isAccessibilityTrusted = accessibilityTrusted()
        environment.isVoiceModelInstalled = voiceCapture.setup == .installed || voiceCapture.setup == .preparing
        voiceCapture.refreshAccessibilityStatus()
    }

    func refreshEnvironmentAsync() async {
        refreshEnvironmentSync()
        environment.isRefineAvailable = await refineAvailabilityCheck()
    }

    // MARK: - OnboardingPanelDelegate

    func panelDidShow() {
        guard isLivePracticeActive else { return }
        if presentUIWindows { windowController.hide() }
    }

    func panelDidHide() {
        guard isLivePracticeActive else { return }

        scratchpadGuidance = .inactive
        panelController?.scratchpadGuidance = .inactive

        if captureSubstep == .liveResume {
            if !isReplaying { store.resumeCompleted = true }
            advanceAfterPractice()
            return
        }

        if practiceWasKept || (!isReplaying && store.practiceKept) {
            if !isReplaying { store.resumeCompleted = true }
            advanceAfterPractice()
            return
        }

        if practiceMeaningfulTextEntered || (!isReplaying && store.meaningfulTextEntered) {
            captureSubstep = .waitingToResume
            if !isReplaying {
                store.persistProgress(step: .capturePractice, captureSubstep: .waitingToResume)
            }
            isYieldingForShortcut = true
            presentWindow()
        } else {
            captureSubstep = .waitingForShortcut
            if !isReplaying {
                store.persistProgress(step: .capturePractice, captureSubstep: .waitingForShortcut)
            }
            isYieldingForShortcut = true
            presentWindow()
        }
    }

    func sessionTextDidChange(_ text: String) {
        guard isLivePracticeActive else { return }
        guard captureSubstep == .liveCapture else { return }

        if OnboardingMeaningfulInput.isMeaningful(text) {
            practiceMeaningfulTextEntered = true
            if !isReplaying { store.meaningfulTextEntered = true }
            scratchpadGuidance.showEmptyHint = false
            scratchpadGuidance.showRefineHint = environment.isRefineAvailable
            scratchpadGuidance.showEscapeHint = true
            panelController?.scratchpadGuidance = scratchpadGuidance
        }
    }

    func sessionSurfaceDidChange(_ surface: ScratchpadSession.Surface) {
        guard isLivePracticeActive else { return }

        switch surface {
        case .refining:
            practiceRefineAttemptedOrSkipped = true
            if !isReplaying { store.refineAttempted = true }
            scratchpadGuidance.showRefineHint = false
            scratchpadGuidance.unavailablePresentation = nil
            panelController?.scratchpadGuidance = scratchpadGuidance
            presentedStep = .refinePractice
            if !isReplaying {
                store.persistProgress(step: .refinePractice, captureSubstep: captureSubstep)
            }
        case .refinementPreview:
            practiceRefineAttemptedOrSkipped = true
            if !isReplaying { store.refineAttempted = true }
            scratchpadGuidance.showRefineHint = false
            panelController?.scratchpadGuidance = scratchpadGuidance
        case .message:
            break
        case .editor:
            if practiceRefineAttemptedOrSkipped || (!isReplaying && (store.refineAttempted || store.refineSkipped)) {
                scratchpadGuidance.showEscapeHint = true
                if captureSubstep == .liveResume {
                    scratchpadGuidance.showKeepHint = true
                }
                panelController?.scratchpadGuidance = scratchpadGuidance
            }
        default:
            break
        }
    }

    func sessionMessageDidShow(_ message: RefinementMessage?) {
        guard isLivePracticeActive, let message else { return }

        switch message {
        case .alreadyUseful:
            practiceRefineAttemptedOrSkipped = true
            if !isReplaying { store.refineAttempted = true }
            scratchpadGuidance.showRefineHint = false
            scratchpadGuidance.showEscapeHint = true
            panelController?.scratchpadGuidance = scratchpadGuidance
        case .unavailable(let reason):
            practiceRefineAttemptedOrSkipped = true
            if !isReplaying { store.refineAttempted = true }
            scratchpadGuidance.showRefineHint = false
            scratchpadGuidance.unavailablePresentation = mapUnavailable(reason)
            panelController?.scratchpadGuidance = scratchpadGuidance
        case .couldNotRefine, .couldNotSafelyRefineSelection, .couldNotSaveRefinement, .contextTooLarge:
            practiceRefineAttemptedOrSkipped = true
            if !isReplaying { store.refineAttempted = true }
            scratchpadGuidance.showRefineHint = false
            scratchpadGuidance.showEscapeHint = true
            panelController?.scratchpadGuidance = scratchpadGuidance
        case .nothingToRefine, .multipleSelection, .containsImages:
            break
        }
    }

    func sessionDidKeepNote() {
        guard isLivePracticeActive else { return }
        if !isReplaying { store.practiceKept = true }
        practiceWasKept = true
    }

    func dismissRefineUnavailable() {
        practiceRefineAttemptedOrSkipped = true
        if !isReplaying { store.refineSkipped = true }
        scratchpadGuidance.unavailablePresentation = nil
        scratchpadGuidance.showRefineHint = false
        scratchpadGuidance.showEscapeHint = true
        panelController?.scratchpadGuidance = scratchpadGuidance
        presentedStep = .refinePractice
        if !isReplaying {
            store.persistProgress(step: .refinePractice, captureSubstep: captureSubstep)
        }
    }

    func openRefineSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Siri") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Private

    private func activateOnboardingSession(restoringProgress: Bool) {
        panelController?.onboardingDelegate = self
        scratchpadGuidance = .inactive
        panelController?.scratchpadGuidance = .inactive
        if restoringProgress {
            restorePersistedState()
        } else {
            presentedStep = .welcome
            captureSubstep = .waitingForShortcut
        }
        isActive = true
        presentWindow()
    }

    private func restorePersistedState() {
        presentedStep = store.step == .finished ? .welcome : store.step
        captureSubstep = store.captureSubstep
        practiceWasKept = store.practiceKept

        if let savedFocus = store.focus {
            selectedFocus = environment.isVoiceSupported ? savedFocus : .scratchpadOnly
        }

        if presentedStep == .capturePractice || presentedStep == .refinePractice {
            if captureSubstep == .liveResume || store.meaningfulTextEntered {
                captureSubstep = .waitingToResume
            } else {
                captureSubstep = .waitingForShortcut
            }
        }

        if presentedStep == .voiceSetup {
            if !showsVoiceStepInFlow {
                presentedStep = .completion
            } else if voiceCapture.enabled, voiceCapture.setup == .unchecked {
                voiceCapture.checkSetup(prepare: true)
            }
        }

        if presentedStep == .completion {
            refreshLoginItemState()
        }
    }

    private func presentWindow() {
        guard presentUIWindows else { return }
        windowController.show(coordinator: self)
        if isWaitingForShortcut {
            isYieldingForShortcut = true
            windowController.resignKey()
        }
    }

    private func advanceAfterPractice() {
        refreshEnvironmentSync()
        if showsVoiceStepInFlow {
            presentedStep = .voiceSetup
            captureSubstep = .waitingForShortcut
            isYieldingForShortcut = false
            if !isReplaying {
                store.persistProgress(step: .voiceSetup)
            }
            if voiceCapture.enabled, voiceCapture.setup == .unchecked {
                voiceCapture.checkSetup(prepare: true)
            }
            presentWindow()
        } else {
            advanceToCompletion()
        }
    }

    private func advanceToCompletion() {
        presentedStep = .completion
        captureSubstep = .waitingForShortcut
        isYieldingForShortcut = false
        if !isReplaying {
            store.persistProgress(step: .completion)
        }
        refreshLoginItemState()
        presentWindow()
    }

    private func tearDown(preservePracticeNote: Bool) {
        isActive = false
        isYieldingForShortcut = false
        scratchpadGuidance = .inactive
        panelController?.scratchpadGuidance = .inactive
        panelController?.onboardingDelegate = nil
        if presentUIWindows { windowController.close() }

        if !preservePracticeNote {
            // Skip setup intentionally leaves no tutorial artifacts behind.
        }
    }

    private func refreshLoginItemState() {
        loginItemState = loginItemController.state()
    }

    private func mapUnavailable(
        _ reason: RefinementUnavailableReason
    ) -> OnboardingRefineUnavailablePresentation {
        switch reason {
        case .appleIntelligenceNotEnabled:
            .appleIntelligenceDisabled
        case .modelNotReady:
            .modelPreparing
        case .deviceNotEligible, .unsupportedEnvironment, .unknown:
            .unsupported
        }
    }
}

@MainActor
protocol OnboardingPanelDelegate: AnyObject {
    func panelDidShow()
    func panelDidHide()
    func sessionTextDidChange(_ text: String)
    func sessionSurfaceDidChange(_ surface: ScratchpadSession.Surface)
    func sessionMessageDidShow(_ message: RefinementMessage?)
    func sessionDidKeepNote()
    func dismissRefineUnavailable()
    func openRefineSystemSettings()
}

extension OnboardingCoordinator: OnboardingPanelDelegate {}
