# M12B-005B production token policy

## Protected exact classes

| Class | Deterministic extraction | Preservation contract |
|---|---|---|
| URL | `http://` or `https://` followed by a non-space span; trailing `. , ; :` is not part of the URL | Exact extracted value |
| Email | Conventional ASCII local-part plus dotted host | Exact, including case and punctuation |
| @handle | `@` plus 1–32 ASCII word characters; email spans win precedence | Exact |
| Identifier | snake_case, camelCase, conservative technical PascalCase, technical kebab/mixed alphanumeric, versions, and `#digits` | Exact and case-sensitive |
| Code-like | Function/member calls; paths with a leading `/`, `./`, or `../`; or slash paths with an additional technical cue such as `.`, `_`, `-`, or a digit | Exact |
| Quoted literal | Nontrivial double-, single-, or backtick-delimited spans | Exact, including delimiters |
| Opaque ID | UUID, uppercase ticket ID, or mixed hex hash | Exact and case-sensitive |
| Standalone integer | Signed/unsigned integer not embedded in a compound value | Exact; deletion or value change rejects |

Extraction is precedence-based. Higher-confidence compound spans claim their source ranges before simpler patterns, so an email does not become a handle and the digits inside excluded semantic values do not become integers. Duplicate identical values are a single preservation obligation. Matching is class plus exact extracted text; no Unicode, casing, locale, or semantic normalization is attempted.

## Explicit exclusions

Dates, times, money, percentages, decimal values, and formatted numeric values claim their spans only to prevent accidental integer/identifier protection. They are not production-protected by M12B-005B. Added output literals are not rejected.

## Failure behavior

For a changed proposal, the validator checks only literals extracted from `request.inputText`. Whole-note input is the whole note; selection input is only the selected source span. Any missing or different protected value rejects the proposal into the existing `.noChange` / `.alreadyGood` result. There is no repair or second generation call, and diagnostics record only reason and class—never literal content.

## Limitations

- This is syntactic preservation, not semantic parsing.
- Conservative PascalCase/kebab patterns prefer false negatives over ordinary-word false positives.
- Repeated identical literals are presence-protected, not multiplicity-protected.
- Safe semantic conversions and out-of-scope corruption require a separate experiment.
