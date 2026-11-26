import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Rasc

@Suite(.serialized)
@MainActor
struct OnboardingBehaviorTests {
    @Test
    func meaningfulInputThreshold() {
        #expect(!OnboardingMeaningfulInput.isMeaningful(""))
        #expect(!OnboardingMeaningfulInput.isMeaningful("  "))
        #expect(!OnboardingMeaningfulInput.isMeaningful("ab"))
        #expect(OnboardingMeaningfulInput.isMeaningful("abc"))
    }

    @Test
    @MainActor
    func shortcutFormattingUsesProductionSourceOfTruth() {
        #expect(GlobalShortcutFormatting.hasValidToggleShortcut())
        #expect(!GlobalShortcutFormatting.currentToggleShortcutDisplay().isEmpty)
    }

    @Test
    func skipSetupMarksOnboardingCompleteWithoutCreatingNotes() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }

        let defaults = fixture.userDefaults
        let coordinator = OnboardingCoordinator(
            store: OnboardingStore(userDefaults: defaults),
            activeNoteStore: ActiveNoteStore(userDefaults: defaults),
            windowFrameStore: WindowFrameStore(userDefaults: defaults)
        )
        coordinator.skipSetup()

        #expect(OnboardingStore(userDefaults: defaults).isCompleted)
        #expect(try await fixture.repository.fetchMostRecent() == nil)
    }

    @Test
    func onboardingGuidanceRemainsSeparateFromScratchpadSessionSurface() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }

        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )

        session.scratchpadGuidance = OnboardingScratchpadGuidance(isActive: true)
        session.scratchpadGuidance.showRefineHint = true

        #expect(session.surface == .editor)
        #expect(session.scratchpadGuidance.showRefineHint)
    }

    @Test
    func coreSurfaceMetricsKeepWritingAndTransientSurfacesInOneVisualSystem() {
        #expect(
            RascSurfaceMetrics.placeholderLeadingInset
                == RascSurfaceLayout.horizontalInset
                    + RascSurfaceLayout.textContainerHorizontalInset
        )
        #expect(RascSurfaceMetrics.previewCornerRadius > RascSurfaceMetrics.feedbackCornerRadius)
        #expect(RascSurfaceMetrics.inlineOrbSize == 20)
        #expect(RascTransientPanelSizing.paletteHeight(commandCount: 4) == 266)
        #expect(RascTransientPanelSizing.paletteHeight(commandCount: 4) < 360)
    }

    @Test
    func actionPrimaryFillKeepsProminentButtonLabelsReadable() throws {
        for colorScheme in [ColorScheme.light, .dark] {
            let fill = RascSurfacePalette.standard.actionPrimaryFillNSColor(for: colorScheme)
            let label = RascSurfacePalette.standard.actionPrimaryLabelNSColor(for: colorScheme)
            #expect(try contrastRatio(fill, label) >= 4.5)
        }
    }

    @Test
    func keepAccentKeepsTheApprovedCopperFillReadable() throws {
        for colorScheme in [ColorScheme.light, .dark] {
            let accent = RascSurfacePalette.standard.keepAccentNSColor(for: colorScheme)
            let fill = RascSurfacePalette.standard.keepFillNSColor(for: colorScheme)
            #expect(try contrastRatio(accent, fill) >= 4.5)
        }
    }

    @Test
    func adaptiveFlowCoversPracticeResumeKeepAndSkipsVoiceWhenUnsupported() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let defaults = fixture.userDefaults

        // 1. Unsupported Mac skips Voice Setup automatically.
        let unsupported = OnboardingCoordinator(
            store: OnboardingStore(userDefaults: defaults),
            activeNoteStore: ActiveNoteStore(userDefaults: defaults),
            windowFrameStore: WindowFrameStore(userDefaults: defaults),
            shortcutStore: GlobalShortcutStore(userDefaults: defaults, chordBacking: .userDefaultsOnly),
            isVoiceSupported: false,
            presentUIWindows: false,
            microphoneAuthorized: { false },
            accessibilityTrusted: { false },
            refineAvailabilityCheck: { false }
        )
        #expect(unsupported.selectedFocus == .scratchpadOnly)
        #expect(!unsupported.showsVoiceStepInFlow)
        #expect(unsupported.progressStepCount == 3)
        unsupported.resetOnboardingStateOnly()
        #expect(unsupported.isActive)

        unsupported.continueFromWelcome()
        #expect(unsupported.presentedStep == .shortcut)
        unsupported.continueFromShortcut()
        #expect(unsupported.presentedStep == .capturePractice)
        #expect(unsupported.captureSubstep == .waitingForShortcut)

        #expect(await unsupported.handleGlobalShortcut())
        #expect(unsupported.captureSubstep == .liveCapture)
        #expect(!unsupported.scratchpadGuidance.canShowRefineHint)

        // Meaningful draft -> Esc hides -> Beat 2 waitingToResume.
        unsupported.sessionTextDidChange("Ideia em andamento")
        #expect(unsupported.scratchpadGuidance.showEscapeHint)
        #expect(!unsupported.scratchpadGuidance.showRefineHint)
        unsupported.panelDidHide()
        #expect(unsupported.captureSubstep == .waitingToResume)

        // Second shortcut invocation enters Beat 2 resume with Keep guidance.
        #expect(await unsupported.handleGlobalShortcut())
        #expect(unsupported.captureSubstep == .liveResume)
        #expect(unsupported.scratchpadGuidance.isResumeBeat)
        #expect(unsupported.scratchpadGuidance.showKeepHint)

        unsupported.sessionDidKeepNote()
        unsupported.panelDidHide()
        #expect(unsupported.practiceWasKept)
        #expect(unsupported.presentedStep == .completion)
    }

    @Test
    func supportedMacEnablesVoiceAsynchronouslyWithoutBlockingAndPreservesDictateDefaults() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let defaults = fixture.userDefaults
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        let capture = VoiceCapture(
            preferences: defaults,
            supported: true,
            input: .init(
                authorization: { .notDetermined },
                requestAccess: { true },
                start: { _, _ in MicBuffer(rate: 16_000) },
                stop: { _ in }
            ),
            presentWindows: false,
            speech: .init(
                assetsAvailable: { false },
                hasInstalledAssets: { false },
                download: { _ in try? await Task.sleep(for: .milliseconds(30)) },
                prepare: {},
                transcribe: { _, _ in "" },
                release: {}
            ),
            accessibilityTrusted: { false },
            pasteboard: pasteboard
        )
        let shortcuts = GlobalShortcutStore(userDefaults: defaults, chordBacking: .userDefaultsOnly)

        let coordinator = OnboardingCoordinator(
            store: OnboardingStore(userDefaults: defaults),
            activeNoteStore: ActiveNoteStore(userDefaults: defaults),
            windowFrameStore: WindowFrameStore(userDefaults: defaults),
            voiceCapture: capture,
            shortcutStore: shortcuts,
            isVoiceSupported: true,
            presentUIWindows: false,
            microphoneAuthorized: { false },
            accessibilityTrusted: { false },
            refineAvailabilityCheck: { true },
            requestMicrophoneAccessHandler: { true }
        )

        #expect(coordinator.selectedFocus == .scratchpadAndVoice)
        #expect(coordinator.showsVoiceStepInFlow)
        #expect(coordinator.progressStepCount == 4)
        #expect(coordinator.dictationDelivery == .insertAtCursor)
        #expect(coordinator.dictationAlsoCopiesToClipboard)
        #expect(coordinator.dictationSaveCopyInRasc)
        coordinator.resetOnboardingStateOnly()

        // Selecting scratchpadOnly bypasses Voice setup; selecting scratchpadAndVoice routes through it.
        coordinator.continueFromWelcome()
        coordinator.continueFromShortcut()
        #expect(await coordinator.handleGlobalShortcut())
        coordinator.sessionTextDidChange("Nota de teste")
        coordinator.panelDidHide()
        coordinator.continueFromResumeCard()
        #expect(coordinator.presentedStep == .voiceSetup)

        // Enabling Voice starts download without blocking completion; Dictate defaults stay intact.
        coordinator.enableVoiceSetup()
        #expect(coordinator.isVoiceEnabled)
        #expect(coordinator.dictationAlsoCopiesToClipboard)
        #expect(coordinator.dictationSaveCopyInRasc)

        // Accessibility only requested when Dictate shortcut is configured (with insertAtCursor) or single modifier used.
        #expect(!coordinator.needsAccessibilityForVoiceSetup)
        #expect(shortcuts.set(.modifier(.control), for: .voiceDictate) == nil)
        #expect(coordinator.needsAccessibilityForVoiceSetup)

        await coordinator.requestMicrophonePermission()
        #expect(coordinator.environment.isMicrophoneAuthorized)

        // User can finish onboarding immediately without waiting for download.
        coordinator.continueFromVoiceSetup()
        #expect(coordinator.presentedStep == .completion)
    }

    @Test
    func replayPreservesExistingNotesShortcutsAndPreferences() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let defaults = fixture.userDefaults
        _ = try await fixture.repository.createScratch(content: "Nota já salva")

        let shortcuts = GlobalShortcutStore(userDefaults: defaults, chordBacking: .userDefaultsOnly)
        #expect(shortcuts.set(.modifier(.option), for: .toggleScratchpad) == nil)

        let store = OnboardingStore(userDefaults: defaults)
        store.markCompletedForExistingUser()

        let coordinator = OnboardingCoordinator(
            store: store,
            activeNoteStore: ActiveNoteStore(userDefaults: defaults),
            windowFrameStore: WindowFrameStore(userDefaults: defaults),
            shortcutStore: shortcuts,
            isVoiceSupported: true,
            presentUIWindows: false
        )
        await coordinator.replayOnboarding()

        #expect(coordinator.isActive)
        #expect(coordinator.presentedStep == .welcome)
        #expect(shortcuts.trigger(for: .toggleScratchpad) == .modifier(.option))
        let notes = try await fixture.repository.fetchAllNonDeleted()
        #expect(notes.map(\.content) == ["Nota já salva"])
    }

    @Test
    func redesignedOnboardingRendersCleanlyAcrossThemesAndNarrowSize() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let defaults = fixture.userDefaults
        let shortcuts = GlobalShortcutStore(userDefaults: defaults, chordBacking: .userDefaultsOnly)

        let coordinator = OnboardingCoordinator(
            store: OnboardingStore(userDefaults: defaults),
            activeNoteStore: ActiveNoteStore(userDefaults: defaults),
            windowFrameStore: WindowFrameStore(userDefaults: defaults),
            shortcutStore: shortcuts,
            isVoiceSupported: true,
            presentUIWindows: false,
            microphoneAuthorized: { false },
            accessibilityTrusted: { false },
            refineAvailabilityCheck: { true }
        )
        coordinator.resetOnboardingStateOnly()
        let renderer = HomeSnapshotTests()

        for scheme in [ColorScheme.light, .dark] {
            try renderer.renderPNG(
                OnboardingView(coordinator: coordinator),
                width: RascWindowMetrics.onboarding.width,
                height: RascWindowMetrics.onboarding.height,
                scheme: scheme,
                name: "onboarding-v2-welcome-\(scheme)"
            )
        }

        coordinator.continueFromWelcome()
        try renderer.renderPNG(
            OnboardingView(coordinator: coordinator),
            width: 560,
            height: 480,
            scheme: .light,
            name: "onboarding-v2-shortcut-narrow"
        )

        coordinator.continueFromShortcut()
        #expect(await coordinator.handleGlobalShortcut())
        coordinator.sessionTextDidChange("Fragmento inicial")
        coordinator.panelDidHide()
        #expect(coordinator.captureSubstep == .waitingToResume)

        try renderer.renderPNG(
            OnboardingView(coordinator: coordinator),
            width: RascWindowMetrics.onboarding.width,
            height: RascWindowMetrics.onboarding.height,
            scheme: .light,
            name: "onboarding-v2-resume-light"
        )

        try renderer.renderPNG(
            OnboardingScratchpadOverlay(
                guidance: {
                    var g = OnboardingScratchpadGuidance(isActive: true)
                    g.isResumeBeat = true
                    g.showKeepHint = true
                    g.showEscapeHint = true
                    g.showEmptyHint = false
                    return g
                }(),
                editorText: "Ideia ainda crua"
            )
            .frame(width: 520, height: 84),
            width: 520,
            height: 84,
            scheme: .dark,
            name: "onboarding-v2-overlay-resume-dark"
        )

        coordinator.continueFromResumeCard()
        #expect(coordinator.presentedStep == .voiceSetup)
        for scheme in [ColorScheme.light, .dark] {
            try renderer.renderPNG(
                OnboardingView(coordinator: coordinator),
                width: RascWindowMetrics.onboarding.width,
                height: RascWindowMetrics.onboarding.height,
                scheme: scheme,
                name: "onboarding-v2-voice-\(scheme)"
            )
        }
        try renderer.renderPNG(
            OnboardingView(coordinator: coordinator),
            width: 560,
            height: 480,
            scheme: .dark,
            name: "onboarding-v2-voice-narrow-dark"
        )

        coordinator.continueFromVoiceSetup()
        #expect(coordinator.presentedStep == .completion)
        for scheme in [ColorScheme.light, .dark] {
            try renderer.renderPNG(
                OnboardingView(coordinator: coordinator),
                width: RascWindowMetrics.onboarding.width,
                height: RascWindowMetrics.onboarding.height,
                scheme: scheme,
                name: "onboarding-v2-completion-\(scheme)"
            )
        }
    }

    private func makeFixture() throws -> ScratchpadTestFixture {
        try ScratchpadTestFixture()
    }
}

private func contrastRatio(_ first: NSColor, _ second: NSColor) throws -> Double {
    let firstLuminance = try relativeLuminance(first)
    let secondLuminance = try relativeLuminance(second)
    return (max(firstLuminance, secondLuminance) + 0.05)
        / (min(firstLuminance, secondLuminance) + 0.05)
}

private func relativeLuminance(_ color: NSColor) throws -> Double {
    let color = try #require(color.usingColorSpace(.sRGB))
    let components = [color.redComponent, color.greenComponent, color.blueComponent]
        .map { component in
            component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }
    return (0.2126 * components[0]) + (0.7152 * components[1]) + (0.0722 * components[2])
}

private struct ScratchpadTestFixture {
    let repository: NoteRepository
    let userDefaults: UserDefaults
    private let databaseURL: URL
    private let defaultsSuite: String

    init() throws {
        defaultsSuite = "RascTests.OnboardingBehavior.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: defaultsSuite)!
        userDefaults.removePersistentDomain(forName: defaultsSuite)
        databaseURL = FileManager.default.temporaryDirectory
            .appending(path: "onboarding-\(UUID().uuidString).sqlite")
        repository = try NoteRepository(databaseURL: databaseURL)
    }

    func remove() {
        userDefaults.removePersistentDomain(forName: defaultsSuite)
        try? repository.closeForTesting()
        try? FileManager.default.removeItem(at: databaseURL)
    }
}
