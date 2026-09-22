# M12B-005A evaluation token policy

This policy is evaluation-only. It does not change production Refine behavior, prompts, generation, language handling, selection handling, corpus data, or UX.

## Extraction rules

Extraction is deterministic and precedence-based. Compound spans claim their range before simpler patterns, preventing the digits inside a date, percentage, money value, URL, or identifier from being counted again as plain numbers.

| Class | High-confidence rule | Evaluation preservation |
|---|---|---|
| URL | `http://` or `https://` followed by a non-space URL span | Exact |
| Email | Conventional local-part, `@`, dotted host | Exact |
| Handle | `@` plus 1–32 ASCII word characters; emails take precedence | Exact |
| Money | `R$`, `US$`, `$`, `€`, `£`, or `¥`, optionally followed by an amount | Semantic: whitespace around the currency marker may change; marker and amount may not |
| Date | ISO `YYYY-MM-DD` or slash date `D/M[/Y]` | Semantic class, but only identical surface is currently accepted; no locale guessing |
| Time | 24-hour colon, Portuguese `h`, or AM/PM clock forms | Semantic by exact minute-of-day equivalence |
| Number | Standalone integer/decimal-like literal, after compound classes | Semantic class, but only identical surface is currently accepted; no separator guessing |
| Percentage | Numeric literal plus `%` | Semantic: whitespace before `%` may change; value and `%` may not |
| Identifier | snake_case, camelCase, conservative technical PascalCase, version/mixed-alphanumeric, or technical kebab form | Exact |
| Code-like | Function/member-call or path-like literal | Exact |
| Quoted literal | Double-, single-, or backtick-delimited nontrivial span | Exact, including delimiters |
| Opaque ID | UUID, ticket-style uppercase ID, or 7–64 character mixed hex hash | Exact |

## Assumptions

- Exact preservation means the original byte/text span must appear in the changed output.
- Safe semantic normalization is intentionally narrow: `R$ 300` ↔ `R$300`, `15h` ↔ `15:00`, and `50%` ↔ `50 %`.
- `R$` → `$`, `31/12` → `12/31`, and `50%` → `50` are not safe normalization.
- Changed proposals that violate the high-confidence contract are simulated as rejected into the existing `noChange` result. There is no regeneration or repair pass.

## Known limitations and false-positive risks

- Dates and plain numbers are detected structurally, not interpreted by locale. Production enforcement is deferred for these classes.
- Version strings, durations such as `45ms`, and mixed alphanumeric values are treated as identifiers only when structural cues are strong.
- Uppercase ordinary words are not automatically identifiers.
- A generated numbered list can introduce protected-like plain numbers without inventing factual content; added-token results are indicators, not automatic failures.
- Quoted natural-language text is protected as a literal even when a user might accept quote-style normalization; this first layer prefers false negatives over broad semantic inference.
- Extraction does not attempt NLP, named-entity recognition, or locale-heavy date parsing.
