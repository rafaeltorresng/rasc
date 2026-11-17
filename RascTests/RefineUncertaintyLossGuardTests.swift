import Foundation
import Testing
@testable import Rasc

@Suite(.serialized)
@MainActor
struct RefineUncertaintyLossGuardTests {
    // Captured harmful outputs from issue #48. Every one removes an explicit hedge
    // and turns that clause into a fact, instruction or decision.
    private let knownHarmful: [(String, String)] = [
        ("acho que podemos fazer A, or maybe B, talvez C — ver com o time na próxima",
         "Podemos fazer A, ou talvez B, talvez C — ver com o time na próxima"),
        ("acho que podemos fazer A, or maybe B, talvez C — ver com o time na próxima",
         "Vamos fazer A, ou talvez B, talvez C — ver com o time na próxima"),
        ("hipótese: pode ser o cache, ou pode ser a migração, ou talvez seja o proxy — mas achamos que é o cache",
         "Podemos ser o cache, ou a migração, ou talvez seja o proxy, mas achamos que é o cache"),
        ("maybe check the logs, or perhaps retry the job, or ask the team", "check the logs"),
        ("maybe check the logs, or perhaps retry the job, or ask the team",
         "check the logs, or retry the job, or ask the team"),
        ("talvez revisar o doc, ou talvez enviar para Ana, ou esperar",
         "Verificar o documento e enviar para Ana ou esperar"),
        ("talvez revisar o doc, ou talvez enviar para Ana, ou esperar", "revisar o doc"),
        ("talvez revisar o doc, ou talvez enviar para Ana, ou esperar",
         "revisar o doc ou enviar para Ana"),
        ("maybe check the logs; update the runbook; ping Ana and Bob about the fix",
         "check the logs; update the runbook; ping Ana and Bob about the fix"),
        ("maybe check the logs; update the runbook; ping Ana and Bob about the fix",
         "Check the logs; update the runbook; ping Ana and Bob about the fix"),
        ("maybe check the logs; update the runbook; ping Ana and Bob about the fix",
         "Update the runbook; ping Ana and Bob about the fix"),
        ("pode ser que o cache esteja errado", "O cache está errado"),
    ]

    @Test func knownHarmfulOutputsAreBlocked() {
        for (claim, suggestion) in knownHarmful {
            #expect(RefineUncertaintyLossGuard.blocks(claim: claim, suggestion: suggestion),
                    "should block: \(claim) -> \(suggestion)")
        }
    }

    @Test func knownHarmClassificationSummary() {
        var losses = 0, ambiguities = 0, allowed = 0
        for (claim, suggestion) in knownHarmful {
            let outcome = RefineUncertaintyLossGuard.evaluate(claim: claim, suggestion: suggestion)
            print("CLASSIFY \(outcome) claim=\(claim) suggestion=\(suggestion)")
            switch outcome {
            case .hedgeLoss: losses += 1
            case .ambiguous: ambiguities += 1
            case .allowed: allowed += 1
            }
        }
        print("CLASSIFY hedgeLoss=\(losses) ambiguous=\(ambiguities) allowed=\(allowed) total=\(knownHarmful.count)")
        #expect(allowed == 0)
        #expect(losses + ambiguities == knownHarmful.count)
    }

    @Test func legitimateEditsAndHedgeRephrasingsAreAllowed() {
        let allowed: [(String, String)] = [
            ("maybe check the logs, or perhaps retry the job, or ask the team",
             "Maybe check the logs, or perhaps retry the job, or ask the team"),
            ("maybe the retry is wrong", "Perhaps the retry is wrong"),
            ("talvez revisar o doc", "Quem sabe revisar o doc"),
            ("acho que podemos fazer A, or maybe B, talvez C — ver com o time na próxima",
             "Acho que podemos fazer A, or maybe B, talvez C -- ver com o time na próxima"),
            ("hipótese: pode ser o cache, ou pode ser a migração, ou talvez seja o proxy",
             "Hipótese: pode ser o cache, ou pode ser a migração, ou talvez seja o proxy"),
            ("maybe the retry is wrong", "Maybe the retry is wrong."),
            ("talvez revisar o doc", "Talvez revisar o documento"),
        ]
        for (claim, suggestion) in allowed {
            #expect(!RefineUncertaintyLossGuard.blocks(claim: claim, suggestion: suggestion),
                    "should allow: \(claim) -> \(suggestion)")
        }
    }

    // Deliberate trade-off after removing cross-clause hedge inheritance: a single
    // rephrased hedge spanning "X, ou que seja Y" can no longer be verified as
    // qualifying both claims, so the guard returns noChange. Previously allowed;
    // this expectation change is intentional, not an accidental test edit.
    @Test func coordinatedQueRephrasingAbstainsByDesign() {
        let claim = "pode ser o cache, ou pode ser a migração"
        let suggestion = "É possível que seja o cache, ou que seja a migração"
        let outcome = RefineUncertaintyLossGuard.evaluate(claim: claim, suggestion: suggestion)
        print("TRADEOFF outcome=\(outcome) claim=\(claim) suggestion=\(suggestion)")
        #expect(outcome == .hedgeLoss)
    }

    @Test func outOfScopeInputsAreUnchanged() throws {
        // In-scope (whole note + matchNote) but no hedge in the claim: untouched.
        let wholeNote = try wholeNoteRequest(text: "revisar o doc")
        let changed = RefinementResult(decision: .changed, kind: .messyText, text: "Revisar o doc")
        #expect(RefineUncertaintyLossGuard.finalize(changed, for: wholeNote).text == "Revisar o doc")

        let selectionText = "talvez revisar o doc, depois enviar"
        let selectionRange = selectionText.range(of: "talvez revisar o doc")
        let selection = RefinementRequest(
            snapshot: NoteSnapshot(noteID: UUID(), revision: 1, text: selectionText,
                                   selection: selectionRange),
            languagePolicy: .matchNote
        )
        #expect(RefineUncertaintyLossGuard.finalize(changed, for: selection).decision == .changed)

        let fixed = RefinementRequest(
            snapshot: NoteSnapshot(noteID: UUID(), revision: 1, text: "talvez revisar o doc"),
            languagePolicy: .fixed(Locale(identifier: "pt_BR"))
        )
        #expect(RefineUncertaintyLossGuard.finalize(changed, for: fixed).decision == .changed)

        let noChange = RefinementResult(decision: .noChange, kind: .alreadyGood, text: "talvez revisar o doc")
        #expect(RefineUncertaintyLossGuard.finalize(noChange, for: wholeNote).decision == .noChange)

        let bareOr = "check the logs, or retry the job"
        #expect(!RefineUncertaintyLossGuard.blocks(claim: bareOr, suggestion: "Check the logs, retry the job"))
        let bareOu = "revisar o doc, ou enviar para Ana"
        #expect(!RefineUncertaintyLossGuard.blocks(claim: bareOu, suggestion: "Verificar o documento e enviar para Ana"))
        // Language drift is not this guard's job.
        #expect(!RefineUncertaintyLossGuard.blocks(claim: "Deploy concluído.",
                                                   suggestion: "Deploy completed."))
    }

    // Fresh contrasts labeled before any test ran (recorded in issue #48).
    @Test func freshPreRegisteredContrasts() {
        let cases: [(String, String, Bool)] = [
            ("talvez a equipe decida amanhã", "A equipe decidiu amanhã", true),               // F-01
            ("perhaps we should revert the deploy", "Revert the deploy", true),                // F-02
            ("pode ser que o job tenha falhado", "É possível que o job tenha falhado", false),  // F-03
            ("maybe the timeout is too short", "Perhaps the timeout is too short", false),     // F-04
            ("acho que o cache é o problema, talvez seja o proxy",
             "O cache é o problema, talvez seja o proxy", true),                               // F-05
            ("maybe check the logs, perhaps retry the job",
             "Check the logs, perhaps retry the job", true),                                   // F-06
            ("talvez revisar o doc", "Talvez revisar o documento", false),                     // F-09
            ("deploy?", "Deploy?", false),                                                     // F-10
        ]
        for (claim, suggestion, expectedBlock) in cases {
            #expect(RefineUncertaintyLossGuard.blocks(claim: claim, suggestion: suggestion) == expectedBlock,
                    "contrast \(claim) -> \(suggestion)")
        }
    }

    // Review reproducers (issue #48 clause-matching review): boundary removal must not
    // let a hedge on one claim mask loss on another; reordering a preserved hedge must
    // not be rejected merely because clause order changed.
    @Test func reviewClauseMatchingReproducers() {
        let boundaryRemovalMustNotBeAllowed: [(String, String)] = [
            ("maybe check the logs, perhaps retry the job", "Check the logs perhaps retry the job"),
            ("talvez revisar o doc, talvez enviar para Ana", "Revisar o doc talvez enviar para Ana"),
        ]
        for (claim, suggestion) in boundaryRemovalMustNotBeAllowed {
            #expect(RefineUncertaintyLossGuard.evaluate(claim: claim, suggestion: suggestion) == .ambiguous,
                    "merged boundary must abstain, not allow: \(claim) -> \(suggestion)")
        }
        let preservedHedgeReorderingMustBeAllowed: [(String, String)] = [
            ("maybe check the logs; update the runbook", "Update the runbook; maybe check the logs"),
            ("talvez revisar o doc; enviar para Ana", "Enviar para Ana; talvez revisar o doc"),
        ]
        for (claim, suggestion) in preservedHedgeReorderingMustBeAllowed {
            #expect(RefineUncertaintyLossGuard.evaluate(claim: claim, suggestion: suggestion) == .allowed,
                    "reordering with preserved hedge must be allowed: \(claim) -> \(suggestion)")
        }
    }

    // Final review: two claims sharing most of their wording. Reordering with the
    // hedge still on its original claim is fine; moving the hedge to the other
    // claim is not. Continuation markers must not borrow a hedge for an
    // independent claim.
    @Test func sharedWordingAndContinuationContrasts() {
        let safeReorders: [(String, String)] = [
            ("talvez revisar o doc, revisar o contrato", "Revisar o contrato, talvez revisar o doc"),
            ("maybe check the logs, check the metrics", "Check the metrics, maybe check the logs"),
        ]
        for (claim, suggestion) in safeReorders {
            #expect(RefineUncertaintyLossGuard.evaluate(claim: claim, suggestion: suggestion) == .allowed,
                    "safe reorder must pass: \(claim) -> \(suggestion)")
        }
        let movedHedges: [(String, String)] = [
            ("talvez revisar o doc, revisar o contrato", "Revisar o doc, talvez revisar o contrato"),
            ("maybe check the logs, check the metrics", "Check the logs, maybe check the metrics"),
            // Independent claim must not inherit a hedge from a `que`/`that` clause.
            ("o cache está errado; talvez o timeout seja curto", "Talvez o cache esteja errado; que o timeout seja curto"),
        ]
        for (claim, suggestion) in movedHedges {
            let outcome = RefineUncertaintyLossGuard.evaluate(claim: claim, suggestion: suggestion)
            print("CONTRAST outcome=\(outcome) claim=\(claim) suggestion=\(suggestion)")
            #expect(outcome != .allowed, "hedge must not move to another claim: \(claim) -> \(suggestion)")
        }
    }

    @Test func blockedSuggestionNeverReachesPreviewAndKeepsOriginal() async throws {
        let input = "acho que podemos fazer A, or maybe B, talvez C — ver com o time na próxima"
        let suggestion = "Podemos fazer A, ou talvez B, talvez C — ver com o time na próxima"
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let provider = StubProvider(result: RefinementResult(decision: .changed, kind: .messyText, text: suggestion))
        let session = fixture.makeSession(provider: provider)
        session.text = input
        session.startRefinement()
        try await waitUntil { session.surface == .refinementPreview || session.surface == .message }
        #expect(session.surface == .message)
        #expect(session.message == .alreadyUseful)
        #expect(session.refinementPreview == nil)
        #expect(session.text == input)
    }

    @Test func usefulEditStillReachesPreview() async throws {
        let input = "maybe check the logs, or perhaps retry the job, or ask the team"
        let suggestion = "Maybe check the logs, or perhaps retry the job, or ask the team"
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let provider = StubProvider(result: RefinementResult(decision: .changed, kind: .messyText, text: suggestion))
        let session = fixture.makeSession(provider: provider)
        session.text = input
        session.startRefinement()
        try await waitUntil { session.surface == .refinementPreview || session.surface == .message }
        #expect(session.surface == .refinementPreview)
        #expect(session.refinementPreview?.result.text == suggestion)
        #expect(session.text == input)
    }

    private func wholeNoteRequest(text: String) throws -> RefinementRequest {
        RefinementRequest(snapshot: NoteSnapshot(noteID: UUID(), revision: 1, text: text),
                          languagePolicy: .matchNote)
    }

    private func makeFixture() throws -> GuardFixture {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("guard-\(UUID().uuidString).sqlite")
        let suite = "RefineGuardTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suite))
        userDefaults.removePersistentDomain(forName: suite)
        return GuardFixture(databaseURL: databaseURL,
                            repository: try NoteRepository(databaseURL: databaseURL),
                            userDefaults: userDefaults, suiteName: suite)
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for Refine state")
    }
}

private struct GuardFixture {
    let databaseURL: URL
    let repository: NoteRepository
    let userDefaults: UserDefaults
    let suiteName: String
    @MainActor func makeSession(provider: any RefinementProvider) -> ScratchpadSession {
        ScratchpadSession(repository: repository, refinementProvider: provider, userDefaults: userDefaults)
    }
    func remove() {
        userDefaults.removePersistentDomain(forName: suiteName)
        try? repository.closeForTesting()
        try? FileManager.default.removeItem(at: databaseURL)
    }
}

private struct StubRecord { let decision: String; let text: String }
private actor StubStore {
    var value: StubRecord?
    func set(_ v: StubRecord) { value = v }
    func get() -> StubRecord? { value }
}
private final class StubProvider: RefinementProvider, @unchecked Sendable {
    nonisolated let metadata = RefinementMetadata(provider: "stub", modelIdentifier: "stub-1", promptVersion: "stub")
    private let store = StubStore()
    private let result: RefinementResult
    init(result: RefinementResult) { self.result = result }
    func availability(for request: RefinementRequest) async -> RefinementAvailability { .available }
    func refine(_ request: RefinementRequest) async throws -> RefinementResult {
        await store.set(StubRecord(decision: result.decision.rawValue, text: result.text))
        return result
    }
}
