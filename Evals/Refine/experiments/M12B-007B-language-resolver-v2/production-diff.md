# Production diff — M12B-007B

## Resolver

- `RefineLanguageResolver` now implements v2:
  - boundary-aware marker scoring via `RefineLanguageDetection.containsMarker`
  - no technical-English boost
  - stricter mixed threshold
  - short/all-technical unresolved path
  - `NLLanguageRecognizer` tie-break only for text ≥20 chars with strong margin
  - no system-locale fallback as note-language evidence
- Legacy v1 preserved in `RefineLanguageResolverV1` for eval shadow only

## Unresolved behavior

- unresolved inputs use neutral "preserve the input language" instructions
- post-generation validation remains non-enforcing when resolver confidence is insufficient

## Eval diagnostics

- `RefinementLanguageTrace` and `RefineEvalLanguageDiagnostics` record legacy v1 resolver fields alongside v2
