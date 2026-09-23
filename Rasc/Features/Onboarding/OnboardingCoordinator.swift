import AppKit
import Foundation

@MainActor
@Observable
final class OnboardingCoordinator {
    private let store: OnboardingStore
    private let activeNoteStore: ActiveNoteStore
    private let windowFrameStore: WindowFrameStore
    private let loginItemController: LoginItemController
    private let windowController = OnboardingWindowController()

    private weak var bootstrap: AppBootstrap?
    private weak var panelController: PanelController?
    private var practiceScreen: NSScreen?

    private(set) var isActive = false
    private(set) var presentedStep: OnboardingStep = .welcome
    private(set) var captureSubstep: OnboardingCaptureSubstep = .waitingForShortcut
    private(set) var scratchpadGuidance = OnboardingScratchpadGuidance.inactive
    private(set) var isYieldingForShortcut = false
    private(set) var shortcutKeycapPressed = false
    private var shortcutKeycapFlashTask: Task<Void, Never>?
    private(set) var loginItemState = LoginItemState.disabled
    private(set) var loginItemError: String?
    private(set) var isUpdatingLoginItem = false

    var isWaitingForShortcut: Bool {
        isActive
            && (presentedStep == .capturePractice || presentedStep == .refinePractice)
            && captureSubstep == .waitingForShortcut
    }

    var isLivePracticeActive: Bool {
        isActive && (presentedStep == .capturePractice || presentedStep == .refinePractice)
            && captureSubstep == .liveCapture
    }

    init(
        store: OnboardingStore = OnboardingStore(),
        activeNoteStore: ActiveNoteStore = ActiveNoteStore(),
        windowFrameStore: WindowFrameStore = WindowFrameStore(),
        loginItemController: LoginItemController = LoginItemController()
    ) {
        self.store = store
        self.activeNoteStore = activeNoteStore
        self.windowFrameStore = windowFrameStore
        self.loginItemController = loginItemController
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

        guard shouldPresent else { return }

        panel?.onboardingDelegate = self
        panel?.scratchpadGuidance = scratchpadGuidance
        restorePersistedState()
        isActive = true
        presentWindow()
    }

    func resetOnboardingStateOnly() {
        store.resetOnboardingStateOnly()
        isActive = true
        presentedStep = .welcome
        captureSubstep = .waitingForShortcut
        scratchpadGuidance = .inactive
        panelController?.onboardingDelegate = self
        panelController?.scratchpadGuidance = .inactive
        presentWindow()
    }

    func skipSetup() {
        store.markCompleted()
        tearDown(preservePracticeNote: false)
    }

    func continueFromWelcome() {
        presentedStep = .shortcut
        store.persistProgress(step: .shortcut)
    }

    func continueFromShortcut() {
        presentedStep = .capturePractice
        captureSubstep = .waitingForShortcut
        store.persistProgress(step: .capturePractice, captureSubstep: .waitingForShortcut)
        isYieldingForShortcut = true
        windowController.resignKey()
    }

    func finish() {
        store.markCompleted()
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

        captureSubstep = .liveCapture
        store.persistProgress(step: .capturePractice, captureSubstep: .liveCapture)
        isYieldingForShortcut = false
        windowController.hide()

        scratchpadGuidance = OnboardingScratchpadGuidance(isActive: true)
        panelController?.scratchpadGuidance = scratchpadGuidance

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

    func dismissRefineUnavailable() {
        store.refineSkipped = true
        scratchpadGuidance.unavailablePresentation = nil
        scratchpadGuidance.showEscapeHint = true
        panelController?.scratchpadGuidance = scratchpadGuidance
        presentedStep = .refinePractice
        store.persistProgress(step: .refinePractice, captureSubstep: .liveCapture)
    }

    func openRefineSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Siri") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - OnboardingPanelDelegate

    func panelDidShow() {
        guard isLivePracticeActive else { return }
        windowController.hide()
    }

    func panelDidHide() {
        guard isLivePracticeActive else { return }

        scratchpadGuidance = .inactive
        panelController?.scratchpadGuidance = .inactive

        if canAdvanceToCompletionAfterHide() {
            advanceToCompletion()
        } else {
            captureSubstep = .waitingForShortcut
            store.persistProgress(step: .capturePractice, captureSubstep: .waitingForShortcut)
            isYieldingForShortcut = true
            presentWindow()
        }
    }

    func sessionTextDidChange(_ text: String) {
        guard isLivePracticeActive else { return }

        if OnboardingMeaningfulInput.isMeaningful(text) {
            store.meaningfulTextEntered = true
            scratchpadGuidance.showEmptyHint = false
            if !scratchpadGuidance.showEscapeHint {
                scratchpadGuidance.showRefineHint = true
            }
            panelController?.scratchpadGuidance = scratchpadGuidance
        }
    }

    func sessionSurfaceDidChange(_ surface: ScratchpadSession.Surface) {
        guard isLivePracticeActive else { return }

        switch surface {
        case .refining:
            store.refineAttempted = true
            scratchpadGuidance.showRefineHint = false
            scratchpadGuidance.unavailablePresentation = nil
            panelController?.scratchpadGuidance = scratchpadGuidance
            presentedStep = .refinePractice
            store.persistProgress(step: .refinePractice, captureSubstep: .liveCapture)
        case .refinementPreview:
            store.refineAttempted = true
            scratchpadGuidance.showRefineHint = false
            panelController?.scratchpadGuidance = scratchpadGuidance
        case .message:
            break
        case .editor:
            if store.refineAttempted || store.refineSkipped {
                scratchpadGuidance.showEscapeHint = true
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
            store.refineAttempted = true
            scratchpadGuidance.showRefineHint = false
            scratchpadGuidance.showEscapeHint = true
            panelController?.scratchpadGuidance = scratchpadGuidance
        case .unavailable(let reason):
            store.refineAttempted = true
            scratchpadGuidance.showRefineHint = false
            scratchpadGuidance.unavailablePresentation = mapUnavailable(reason)
            panelController?.scratchpadGuidance = scratchpadGuidance
        case .couldNotRefine, .couldNotSafelyRefineSelection, .couldNotSaveRefinement, .contextTooLarge:
            store.refineAttempted = true
            scratchpadGuidance.showRefineHint = false
            scratchpadGuidance.showEscapeHint = true
            panelController?.scratchpadGuidance = scratchpadGuidance
        case .nothingToRefine, .multipleSelection:
            break
        }
    }

    // MARK: - Private

    private func restorePersistedState() {
        presentedStep = store.step == .finished ? .welcome : store.step
        captureSubstep = store.captureSubstep

        if presentedStep == .capturePractice || presentedStep == .refinePractice {
            captureSubstep = .waitingForShortcut
        }

        if presentedStep == .completion {
            refreshLoginItemState()
        }
    }

    private func presentWindow() {
        windowController.show(coordinator: self)
        if isWaitingForShortcut {
            isYieldingForShortcut = true
            windowController.resignKey()
        }
    }

    private func advanceToCompletion() {
        presentedStep = .completion
        captureSubstep = .waitingForShortcut
        store.persistProgress(step: .completion)
        refreshLoginItemState()
        presentWindow()
    }

    private func canAdvanceToCompletionAfterHide() -> Bool {
        store.meaningfulTextEntered
    }

    private func tearDown(preservePracticeNote: Bool) {
        isActive = false
        isYieldingForShortcut = false
        scratchpadGuidance = .inactive
        panelController?.scratchpadGuidance = .inactive
        panelController?.onboardingDelegate = nil
        windowController.close()

        if !preservePracticeNote {
            // Skip setup must not create notes; nothing to do because skip never opens panel.
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
    func dismissRefineUnavailable()
    func openRefineSystemSettings()
}

extension OnboardingCoordinator: OnboardingPanelDelegate {}
