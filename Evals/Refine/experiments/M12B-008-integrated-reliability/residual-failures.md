# Residual user-visible failures

## Top clusters (dev + validation + holdout)

- **protectedLiteralCorruption** (33): es-003, es-009, legacy-selection-en-fragment-001, legacy-selection-unicode-pt-001, legacy-telegraphic-work-note-pt-001 — blocksBeta=False
- **wrongLanguage** (10): es-002, meeting-dump-003, numbers-003, short-pt-004, telegraphic-pt-009 — blocksBeta=False
- **unnecessaryEdit** (9): es-004, legacy-ambiguous-fragment-pt-001, legacy-casual-slang-pt-001, legacy-selection-ambiguous-nochange-001, medium-en-006 — blocksBeta=False
- **excessiveExpansion** (5): short-pt-002, telegraphic-en-002, telegraphic-en-008, variant-en-052, variant-pt-018 — blocksBeta=False

## Frontier secondary evidence

- Former product failures reviewed: 42
- Now safe/noChange: 19
- Still failures: 23
- Remaining labels: {'unnecessaryEdit': 13, 'wrongLanguage': 18, 'inventedInformation': 3, 'excessiveExpansion': 5, 'selectionLeak': 1, 'meaningChanged': 13, 'styleVoiceDamage': 4, 'other': 3, 'protectedTokenMutation': 2}

No adjudication files were modified.
