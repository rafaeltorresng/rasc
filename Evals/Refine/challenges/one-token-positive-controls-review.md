# One-token positive controls v1 — maintainer review

> Status: generated frontier challenge; **not human validated and not maintainer approved**. Review does not modify frozen corpus or establish ground truth.

| ID | Lang | Input | Disposition | Allowed output | Category | Confidence | Semantic note |
|---|---|---|---|---|---|---|---|
| otpc-pt-change-001 | pt | `nao` | shouldChange | `não` | one-token-positive-control, diacritic-repair | high | Portuguese negation; the canonical diacritic repair is narrow and highly defensible. |
| otpc-pt-change-002 | pt | `voce` | shouldChange | `você` | one-token-positive-control, diacritic-repair | high | Common Portuguese pronoun with one canonical circumflex repair. |
| otpc-pt-change-003 | pt | `tambem` | shouldChange | `também` | one-token-positive-control, diacritic-repair | high | Common Portuguese adverb with one canonical acute-accent repair. |
| otpc-pt-change-004 | pt | `reuniao` | shouldChange | `reunião` | one-token-positive-control, diacritic-repair | high | Common Portuguese noun with a canonical tilde repair. |
| otpc-pt-change-005 | pt | `mensgem` | shouldChange | `mensagem` | one-token-positive-control, obvious-typo | high | Single missing-letter typo; mensagem is overwhelmingly likely in Portuguese. |
| otpc-pt-change-006 | pt | `urgnete` | shouldChange | `urgente` | one-token-positive-control, obvious-typo | high | Adjacent-letter transposition with a highly defensible intended Portuguese word. |
| otpc-pt-change-007 | pt | `tudobem` | shouldChange | `tudo bem` | one-token-positive-control, spacing-repair | high | Highly conventional Portuguese phrase with an obvious missing space. |
| otpc-pt-nochange-001 | pt | `café` | shouldNotChange | `café` | one-token-positive-control, already-valid | high | Already-correct ordinary Portuguese word. |
| otpc-pt-nochange-002 | pt | `deploy` | shouldNotChange | `deploy` | one-token-positive-control, foreign-technical-term | high | Common technical borrowing in a Portuguese work note; capitalization or expansion adds no utility. |
| otpc-pt-nochange-003 | pt | `API` | shouldNotChange | `API` | one-token-positive-control, acronym | high | Technical acronym already usable as captured. |
| otpc-pt-nochange-004 | pt | `Swift` | shouldNotChange | `Swift` | one-token-positive-control, proper-technical-name | high | Correct product/language name; do not paraphrase or expand. |
| otpc-pt-nochange-005 | pt | `blz` | shouldNotChange | `blz` | one-token-positive-control, valid-slang | high | Common Brazilian Portuguese chat shorthand; preserving casual voice is safer than speculative expansion. |
| otpc-pt-ambiguous-001 | pt | `ok` | ambiguous | `ok` | one-token-positive-control, ambiguous-fragment | medium | Language-neutral acknowledgement; insufficient evidence for expansion or capitalization. |
| otpc-pt-ambiguous-002 | pt | `draft` | ambiguous | `draft` | one-token-positive-control, ambiguous-fragment, foreign-technical-term | medium | Could be a status, label, noun, or command; expansion requires guessing. |
| otpc-en-change-001 | en | `recieve` | shouldChange | `receive` | one-token-positive-control, obvious-typo | high | Common adjacent-letter transposition with one overwhelmingly likely English correction. |
| otpc-en-change-002 | en | `adress` | shouldChange | `address` | one-token-positive-control, obvious-typo | high | Single missing-letter spelling error with a canonical English correction. |
| otpc-en-change-003 | en | `definately` | shouldChange | `definitely` | one-token-positive-control, obvious-typo | high | Canonical misspelling with one overwhelmingly likely English correction. |
| otpc-en-change-004 | en | `seperate` | shouldChange | `separate` | one-token-positive-control, obvious-typo | high | Canonical misspelling with one overwhelmingly likely English correction. |
| otpc-en-change-005 | en | `untill` | shouldChange | `until` | one-token-positive-control, obvious-typo | high | One extra-letter typo with a canonical English correction. |
| otpc-en-change-006 | en | `teh` | shouldChange | `the` | one-token-positive-control, obvious-typo | high | Common transposition with a canonical English correction. |
| otpc-en-change-007 | en | `alot` | shouldChange | `a lot` | one-token-positive-control, spacing-repair | high | Standard English requires the highly conventional two-word form a lot. |
| otpc-en-nochange-001 | en | `tomorrow` | shouldNotChange | `tomorrow` | one-token-positive-control, already-valid | high | Already-correct ordinary English word. |
| otpc-en-nochange-002 | en | `deploy` | shouldNotChange | `deploy` | one-token-positive-control, technical-term | high | Valid technical term; capitalization or expansion is not useful by itself. |
| otpc-en-nochange-003 | en | `API` | shouldNotChange | `API` | one-token-positive-control, acronym | high | Technical acronym already usable as captured. |
| otpc-en-nochange-004 | en | `Redis` | shouldNotChange | `Redis` | one-token-positive-control, proper-technical-name | high | Correct proper technical name; do not paraphrase or expand. |
| otpc-en-nochange-005 | en | `gonna` | shouldNotChange | `gonna` | one-token-positive-control, valid-slang | high | Intentional casual English; formalization without context would damage voice. |
| otpc-en-ambiguous-001 | en | `fine` | ambiguous | `fine` | one-token-positive-control, ambiguous-fragment | medium | Could express status, approval, quality, or a noun; expansion requires guessing. |
| otpc-en-ambiguous-002 | en | `draft` | ambiguous | `draft` | one-token-positive-control, ambiguous-fragment | medium | Could be a status, label, noun, or command; expansion requires guessing. |
| otpc-es-change-001 | es | `manana` | shouldChange | `mañana` | one-token-positive-control, diacritic-repair | high | Common Spanish word with a canonical tilde repair and clear lexical identity. |
| otpc-es-change-002 | es | `tambien` | shouldChange | `también` | one-token-positive-control, diacritic-repair | high | Common Spanish adverb with one canonical acute-accent repair. |
| otpc-es-change-003 | es | `informacion` | shouldChange | `información` | one-token-positive-control, diacritic-repair | high | Common Spanish noun with one canonical acute-accent repair. |
| otpc-es-change-004 | es | `reunion` | shouldChange | `reunión` | one-token-positive-control, diacritic-repair | high | Common Spanish noun with one canonical acute-accent repair. |
| otpc-es-change-005 | es | `necsario` | shouldChange | `necesario` | one-token-positive-control, obvious-typo | high | Single missing-letter typo with a canonical Spanish correction. |
| otpc-es-change-006 | es | `urgnte` | shouldChange | `urgente` | one-token-positive-control, obvious-typo | high | Single missing-letter typo with a canonical Spanish correction. |
| otpc-es-change-007 | es | `porfavor` | shouldChange | `por favor` | one-token-positive-control, spacing-repair | high | Highly conventional Spanish phrase with an obvious missing space. |
| otpc-es-nochange-001 | es | `vale` | shouldNotChange | `vale` | one-token-positive-control, already-valid, valid-slang | high | Valid conversational Spanish acknowledgement; preserve casual tone. |
| otpc-es-nochange-002 | es | `deploy` | shouldNotChange | `deploy` | one-token-positive-control, foreign-technical-term | high | Common technical borrowing in a Spanish work note; capitalization or expansion adds no utility. |
| otpc-es-nochange-003 | es | `API` | shouldNotChange | `API` | one-token-positive-control, acronym | high | Technical acronym already usable as captured. |
| otpc-es-nochange-004 | es | `Redis` | shouldNotChange | `Redis` | one-token-positive-control, proper-technical-name | high | Correct proper technical name; do not paraphrase or expand. |
| otpc-es-nochange-005 | es | `mañana` | shouldNotChange | `mañana` | one-token-positive-control, already-valid | high | Already-correct ordinary Spanish word. |
| otpc-es-ambiguous-001 | es | `ok` | ambiguous | `ok` | one-token-positive-control, ambiguous-fragment | medium | Language-neutral acknowledgement; insufficient evidence for expansion or capitalization. |
| otpc-es-ambiguous-002 | es | `chat` | ambiguous | `chat` | one-token-positive-control, ambiguous-fragment, foreign-technical-term | medium | Could be a borrowed noun, label, or command; expansion requires guessing. |

## Separate future protected-token issue

M12B-004A observed `R$` → `$`. Frontier review identified a likely missing protected-token constraint. This issue is recorded for future review only; M12B-004B does not modify the frozen corpus, benchmark constraint, validator, or production guard.
