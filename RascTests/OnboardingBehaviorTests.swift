import AppKit
import Foundation
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
        #expect(RascSurfaceMetrics.commandPaletteHeight(commandCount: 4) == 248)
        #expect(RascSurfaceMetrics.commandPaletteHeight(commandCount: 4) < 360)
    }

    @Test
    func actionAccentFillKeepsProminentButtonLabelsReadable() throws {
        let darkAccent = RascSurfacePalette.actionAccentFillNSColor(for: .dark)
        let lightAccent = RascSurfacePalette.actionAccentFillNSColor(for: .light)

        #expect(try contrastRatio(darkAccent, .white) >= 4.5)
        #expect(try contrastRatio(lightAccent, .white) >= 4.5)
    }

    @Test
    func accentAliasesActionAccent() {
        #expect(RascSurfacePalette.accentNSColor(for: .light) == RascSurfacePalette.actionAccentNSColor(for: .light))
        #expect(RascSurfacePalette.accentNSColor(for: .dark) == RascSurfacePalette.actionAccentNSColor(for: .dark))
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
