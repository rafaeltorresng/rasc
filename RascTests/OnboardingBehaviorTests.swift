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

    private func makeFixture() throws -> ScratchpadTestFixture {
        try ScratchpadTestFixture()
    }
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
