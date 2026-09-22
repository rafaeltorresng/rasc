# M12C-002 — Global Refine preference

## Decision: **REJECT**

## Challenge safety

- runs: 52
- inventedInformationCount: 0
- wrongLanguageCount: 5
- protectedLiteralFailureCount: 2
- selectionFailureCount: 0
- excessiveExpansionCount: 1
- inappropriateForcedChangeCount: 1

## Empty preference regression vs M12C-001

- **dev**: objective Δ 0.0259
- **validation**: objective Δ 0.0175
- **regression**: objective Δ 0.1667

## Preference adherence (challenge)

- Overall: {'suppressedForSafety': 9, 'violated': 6, 'partially': 14, 'notApplicable': 6, 'satisfied': 17}

## Blockers

- protected literal failure under preference
- wrong language under preference

See `analysis.json`, `preference-policy.md`, and `production-diff.md`.
