# M12B-004A one-token counterfactual — case table

Primary scope: executable whole-note M12B-001 dev, validation, and permanent-regression cases containing exactly one classified lexical/content unit. Frontier judgments are secondary evidence only.

| Split | Case | Input | Shape / subtype | Actual output | Actual result | Forced-noChange result | Frontier judgment | Effect | Reason |
|---|---|---|---|---|---|---|---|---|---|
| dev | tiny-en-001 | `maybe` | lexicalWord / ambiguous fragment | `maybe` | noChange; pass | noChange; pass | languageAmbiguous | B — neutral | The actual user-visible result was already noChange; the counterfactual is behaviorally equivalent. |
| dev | tiny-en-002 | `deploy` | lexicalWord / foreign technical term | `Deploy the new feature to production.` | changed; unexpectedChange, expansionExceeded, forbiddenContentIntroduced | noChange; pass | productFailure | A — harm prevented | The recorded visible change failed existing constraints; forced noChange passes and removes the edit. |
| dev | tiny-en-003 | `urgent` | lexicalWord / capitalization-only issue | `Urgent` | changed; unexpectedChange | noChange; pass | productFailure | A — harm prevented | The recorded visible change failed existing constraints; forced noChange passes and removes the edit. |
| dev | tiny-en-004 | `ok` | lexicalWord / already-valid word | `ok` | noChange; pass | noChange; pass | languageAmbiguous | B — neutral | The actual user-visible result was already noChange; the counterfactual is behaviorally equivalent. |
| dev | tiny-en-005 | `retry` | lexicalWord / capitalization-only issue | `Retry` | changed; unexpectedChange | noChange; pass | productFailure | A — harm prevented | The recorded visible change failed existing constraints; forced noChange passes and removes the edit. |
| dev | tiny-en-010 | `draft` | lexicalWord / ambiguous fragment | `draft` | noChange; pass | noChange; pass | — | B — neutral | The actual user-visible result was already noChange; the counterfactual is behaviorally equivalent. |
| dev | tiny-pt-001 | `talvez` | lexicalWord / ambiguous fragment | `talvez` | noChange; pass | noChange; pass | outputAcceptable | B — neutral | The actual user-visible result was already noChange; the counterfactual is behaviorally equivalent. |
| dev | tiny-pt-002 | `deploy?` | wordWithAttachedPunctuation / capitalization-only issue | `Deploy?` | changed; unexpectedChange | noChange; pass | — | A — harm prevented | The recorded visible change failed existing constraints; forced noChange passes and removes the edit. |
| dev | tiny-pt-004 | `café` | lexicalWord / already-valid word | `café` | noChange; pass | noChange; pass | — | B — neutral | The actual user-visible result was already noChange; the counterfactual is behaviorally equivalent. |
| dev | tiny-pt-005 | `ok` | lexicalWord / already-valid word | `ok` | noChange; pass | noChange; pass | — | B — neutral | The actual user-visible result was already noChange; the counterfactual is behaviorally equivalent. |
| dev | tiny-pt-006 | `retry` | lexicalWord / capitalization-only issue | `Retry` | changed; unexpectedChange | noChange; pass | — | A — harm prevented | The recorded visible change failed existing constraints; forced noChange passes and removes the edit. |
| dev | tiny-pt-008 | `R$` | moneyFragment / URL / handle / number / money / emoji (classification note: Currency marker lacks an amount.) | `$` | changed; unexpectedChange | noChange; pass | productFailure | E — frontier/benchmark disagreement | Frontier review materially disagrees with the deterministic benchmark verdict or its recorded failure constraints. |
| dev | tiny-pt-009 | `@ana` | handle / URL / handle / number / money / emoji | `@ana` | noChange; pass | noChange; pass | — | B — neutral | The actual user-visible result was already noChange; the counterfactual is behaviorally equivalent. |
| dev | tiny-pt-010 | `bug` | lexicalWord / foreign technical term | `I have found a bug.` | changed; unexpectedChange, expansionExceeded, forbiddenContentIntroduced | noChange; pass | — | A — harm prevented | The recorded visible change failed existing constraints; forced noChange passes and removes the edit. |
| dev | tiny-pt-011 | `sim` | lexicalWord / already-valid word | `You are welcome to chat with me anytime.` | changed; unexpectedChange, expansionExceeded, forbiddenContentIntroduced | noChange; pass | — | A — harm prevented | The recorded visible change failed existing constraints; forced noChange passes and removes the edit. |
| dev | tiny-pt-012 | `hmm` | lexicalWord / capitalization-only issue | `Hmm` | changed; unexpectedChange | noChange; pass | — | A — harm prevented | The recorded visible change failed existing constraints; forced noChange passes and removes the edit. |
| dev | tiny-pt-014 | `oi` | lexicalWord / ambiguous fragment | `Hello` | changed; unexpectedChange, expansionExceeded | noChange; pass | — | A — harm prevented | The recorded visible change failed existing constraints; forced noChange passes and removes the edit. |
| dev | tiny-pt-015 | `draft` | lexicalWord / foreign technical term | `Hello, team! I've reviewed the draft and noticed a few areas that could be improved for clarity and conciseness. Here are some suggestions: 1. Use specific numbers for quantities whenever possible. 2. Break down complex sentences into simpler ones. 3. Consider adding more context or examples to clarify some points. 4. Ensure that all instructions are clear and unambiguous. 5. Review the formatting to make it more visually appealing. Let me know your thoughts on these suggestions!` | changed; unexpectedChange, expansionExceeded, forbiddenContentIntroduced | noChange; pass | — | A — harm prevented | The recorded visible change failed existing constraints; forced noChange passes and removes the edit. |
| regression | regression-pt-tiny-expanded-001 | `deploy?` | wordWithAttachedPunctuation / capitalization-only issue | `Deploy?` | changed; unexpectedChange | noChange; pass | defer | A — harm prevented | The recorded visible change failed existing constraints; forced noChange passes and removes the edit. |
| validation | tiny-en-006 | `tomorrow` | lexicalWord / ambiguous fragment | `tomorrow` | noChange; pass | noChange; pass | — | B — neutral | The actual user-visible result was already noChange; the counterfactual is behaviorally equivalent. |
| validation | tiny-en-007 | `@sam` | handle / URL / handle / number / money / emoji | `@sam` | changed; productionGuardRejection, unexpectedChange; guard=no_change | noChange; pass | — | B — neutral | The actual user-visible result was already noChange; the counterfactual is behaviorally equivalent. |
| validation | tiny-en-008 | `bug` | lexicalWord / foreign technical term | `bug` | noChange; pass | noChange; pass | — | B — neutral | The actual user-visible result was already noChange; the counterfactual is behaviorally equivalent. |
| validation | tiny-pt-007 | `amanhã` | lexicalWord / capitalization-only issue | `Amanhã` | changed; unexpectedChange | noChange; pass | — | A — harm prevented | The recorded visible change failed existing constraints; forced noChange passes and removes the edit. |
| validation | tiny-pt-013 | `queue` | lexicalWord / foreign technical term | `queue` | noChange; pass | noChange; pass | — | B — neutral | The actual user-visible result was already noChange; the counterfactual is behaviorally equivalent. |

## Excluded selection subgroup

Selection cases are observational only and are not included in primary metrics or policy simulations.

| Split | Case | Input | Shape | Actual action | Actual output |
|---|---|---|---|---|---|
| dev | selection-extra-001 | `next_retry_at` | identifier | changed | `next_retry_at` |
| dev | selection-extra-002 | `Talvez` | lexicalWord | changed | `Talvez seja melhor esperar.` |
| dev | selection-leak-test-007 | `selection` | lexicalWord | changed | `eleicao` |
| dev | selection-pt-tiny-008 | `talvez` | lexicalWord | changed | `talvez seja` |

## Other exclusions

- Non-executable whole-note one-content-unit cases without M12B-001 output: tiny-pt-003.
- Ambiguous one-whitespace-group classifications excluded from primary eligibility: none.
