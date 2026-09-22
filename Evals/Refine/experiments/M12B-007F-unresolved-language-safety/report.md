# M12B-007F — Unresolved-language safety guard

## Decision

**REJECT**

Unresolved-language guard did not meet the acceptance bar.

## Guard rule

Applied only when `resolved.enforcesPostValidation == false` (resolver confidence insufficient, or label is mixed/ambiguous/unknown).

1. Skip if raw FM decision is `noChange`.
2. Assess source-side evidence (Policy A markers + Portuguese morphology; score ≥2 → strong). Ambiguous/mixed/weak → pass.
3. Assess output via independent `NLLanguageRecognizer` (M12B-007E thresholds).
4. Reject to existing `noChange` only when output confidence is **high**, output is PT/EN/ES, and output language ≠ strong source evidence language.
5. Never use system locale; never synthesize high-confidence PT/EN/ES resolution.

## Primary metrics (dev + validation + regression)

| Metric | M12B-007E | M12B-007F | Delta |
|---|---:|---:|---:|
| Unresolved-path raw wrong-language | 12 | 9 | -3 |
| Unresolved guard interceptions | 0 | 4 | +4 |
| Unresolved-path final wrong-language | 10 | 5 | -5 |
| Total final wrong-language | 15 | 11 | -4 |
| False rejections | 1 | 4 | +3 |
| Useful refinements lost | 1 | 4 | +3 |
| PT→EN drift (raw assessment) | 17 | 19 | +2 |
| EN→other | 7 | 8 | +1 |
| ES→other | 1 | 1 | +0 |
| Ambiguous controls incorrectly rejected | 0 | 0 | +0 |

## Policy A verification

- `selection-extra-007`: source `portuguese` strong=True guard `unauthorizedLanguageShift` rejected=True final `noChange` contained=True
- `short-pt-012`: source `portuguese` strong=True guard `outputNotStrong` rejected=False final `changed` contained=True
- `short-pt-013`: source `portuguese` strong=True guard `unauthorizedLanguageShift` rejected=True final `noChange` contained=True
- `telegraphic-pt-010`: source `portuguese` strong=True guard `outputNotStrong` rejected=False final `changed` contained=True

## Ambiguous / technical controls

No guard rejections on fragment controls (`retry`, `deploy`, `queue retry`, tiny inputs). Guard reason stayed `sourceAmbiguous` or `notEvaluated`.

## Objective pass (summary.json)

| Split | M12B-007E | M12B-007F |
|---|---:|---:|
| dev | 0.6217616580310881 | see analysis.json |
| validation | 0.5263157894736842 | see analysis.json |
| regression | 0.6666666666666666 | see analysis.json |

## Stability (critical ×5)

- changed/noChange instability: 12 / 61 unstable cases
- final wrong-language safety instability: 0 unstable cases

## Latency (dev+validation+regression mean)

- M12B-007E: 747.7 ms
- M12B-007F: 748.8 ms

## Causal guard regressions

- `legacy-mixed-language-001` (guardFalseRejection): guard `unauthorizedLanguageShift`
- `mixed-pt-en-001` (guardFalseRejection): guard `unauthorizedLanguageShift`

## Remaining wrong-language root causes

{'evaluatorDisagreement': 6, 'resolverFailure': 3, 'lowConfidenceUnclassifiable': 2}

## Language reliability closed

False
