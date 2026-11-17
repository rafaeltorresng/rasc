import Foundation
import Testing
@testable import Rasc

// Short on-device smoke test for the production-patch guard. Not a regression suite.
@Suite(.serialized)
@MainActor
struct RefineUncertaintyLossGuardLiveSmokeTests {
    @Test
    func liveOnDeviceSmoke() async throws {
        // Opt-in only: normal CI (and local runs without Apple Intelligence) must
        // not require the on-device model. Create ~/.rasc-live-fm-smoke-optin to run.
        let optIn = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".rasc-live-fm-smoke-optin")
        guard FileManager.default.fileExists(atPath: optIn.path) else { return }
        let cases = [
            "maybe check the logs; update the runbook; ping Ana and Bob about the fix",
            "acho que podemos fazer A, or maybe B, talvez C — ver com o time na próxima",
            "talvez revisar o doc, ou talvez enviar para Ana, ou esperar",
            "maybe the retry is wrong, or perhaps the timeout is too short, or it could be the token expiry",
        ]
        struct Row: Codable {
            let input: String
            let attempt: Int
            let policy: String
            let rawDecision: String?
            let rawText: String?
            let guardWouldBlock: Bool
            let surface: String
            let message: String?
            let previewText: String?
            let originalIntact: Bool
        }
        var rows: [Row] = []
        for input in cases {
            for attempt in 0..<2 {
                let db = FileManager.default.temporaryDirectory
                    .appendingPathComponent("guard-smoke-\(UUID().uuidString).sqlite")
                let suite = "GuardSmoke.\(UUID().uuidString)"
                let defaults = UserDefaults(suiteName: suite)!
                let repo = try NoteRepository(databaseURL: db)
                let policy = RefineLanguageSettingsStore(userDefaults: defaults)
                    .resolveEffectivePreference().effectivePolicy
                let recorder = RecordingProvider()
                let session = ScratchpadSession(repository: repo, refinementProvider: recorder,
                                                userDefaults: defaults)
                session.text = input
                session.startRefinement()
                for _ in 0..<1500 {
                    if session.surface == .refinementPreview || session.surface == .message { break }
                    try await Task.sleep(for: .milliseconds(10))
                }
                let raw = await recorder.lastRecorded()
                rows.append(Row(
                    input: input, attempt: attempt, policy: String(describing: policy),
                    rawDecision: raw?.decision, rawText: raw?.text,
                    guardWouldBlock: raw.map { RefineUncertaintyLossGuard.blocks(claim: input, suggestion: $0.text) } ?? false,
                    surface: String(describing: session.surface),
                    message: session.message.map { String(describing: $0) },
                    previewText: session.refinementPreview?.result.text,
                    originalIntact: session.text == input
                ))
                session.cancelRefinement()
                defaults.removePersistentDomain(forName: suite)
                try? repo.closeForTesting()
                try? FileManager.default.removeItem(at: db)
            }
        }
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        try enc.encode(rows).write(to: URL(fileURLWithPath: "/Users/rafatorres/Desktop/rasc/build/native-refine-v2-baseline-48/guardpatch-live-smoke.json"))
    }
}

private struct SmokeRecord { let decision: String; let text: String }
private actor SmokeStore {
    var value: SmokeRecord?
    func set(_ v: SmokeRecord) { value = v }
    func get() -> SmokeRecord? { value }
}
private final class RecordingProvider: RefinementProvider, @unchecked Sendable {
    nonisolated let metadata = FoundationModelsRefinementProvider().metadata
    private let provider = FoundationModelsRefinementProvider()
    private let store = SmokeStore()
    func lastRecorded() async -> SmokeRecord? { await store.get() }
    func availability(for request: RefinementRequest) async -> RefinementAvailability {
        await provider.availability(for: request)
    }
    func refine(_ request: RefinementRequest) async throws -> RefinementResult {
        let result = try await provider.refine(request)
        await store.set(SmokeRecord(decision: result.decision.rawValue, text: result.text))
        return result
    }
}
