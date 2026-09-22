# M12B-007G — Strict unresolved-language safety guard

## Decision

**ACCEPT**

Strict guard eliminated 007F mixed false positives while retaining unresolved drift containment without guard-caused refinement loss.

## Primary metrics vs M12B-007E (dev + validation + regression)

| Metric | 007E | 007G | Delta |
|---|---:|---:|---:|
| Strict-eligible cases | — | 62 | — |
| Strict-eligible final wrong-language | — | 7 | — |
| Guard interceptions | 0 | 5 | +5 |
| Mixed-language guard interceptions | 0 | 0 | +0 |
| Total final wrong-language | 15 | 12 | -3 |
| Guard-caused false rejections | 0 | 0 | +0 |
| Guard-caused useful refinements lost | 0 | 0 | +0 |

## 007F mixed false-positive regression check

- `legacy-mixed-language-001` resolver `mixed/high` eligible=False guardRejected=False final `changed`
- `mixed-pt-en-001` resolver `mixed/high` eligible=False guardRejected=False final `changed`

## Policy case verification

- `selection-extra-007` resolver `ambiguous/insufficient` eligible=True guard `unauthorizedLanguageShift` rejected=True contained=True
- `short-pt-012` resolver `ambiguous/insufficient` eligible=True guard `unauthorizedLanguageShift` rejected=True contained=True
- `short-pt-013` resolver `ambiguous/insufficient` eligible=True guard `unauthorizedLanguageShift` rejected=True contained=True
- `telegraphic-pt-010` resolver `ambiguous/insufficient` eligible=True guard `unauthorizedLanguageShift` rejected=True contained=True

## LANGUAGE RELIABILITY FOR M12B

**CLOSE**
