# M12B-007A resolver candidate

Evaluation-only implementation: `RefineEvalLanguageResolverCandidate`.

## Design goals

- Fix the dominant production failure mode: PT/ES notes with embedded technical English were labeled `mixed` or forced to English.
- Stop treating system locale as evidence about note language.
- Prefer unresolved over confident wrong language on tiny or technical-only fragments.

## Rule summary

1. **Technical-only / tiny guard** — If input has ≤3 tokens, or every token is in a small technical allowlist and there are no romance markers, return `ambiguous` with `insufficient` confidence. No system fallback.
2. **Marker scoring without technical-English boost** — Reuse the same romance marker lists as production detection, but do **not** boost English for `retry`, `queue`, or `_`. Require clearer margins before emitting `mixed`:
   - score ≥2 and margin ≥2 → single language
   - score ≥1 and all other language scores 0 → single language
   - score ≥2 on two languages with margin ≤1 → `mixed`
   - otherwise defer
3. **Natural-language tie-break** — For combined note+context text ≥20 characters, when markers are inconclusive, use `NLLanguageRecognizer` only if top hypothesis ≥0.55 and beats second place by ≥0.20, mapped to pt/en/es.
4. **Otherwise unresolved** — Return `ambiguous` / `insufficient`; never substitute `Locale.preferredLanguages`.

## Explicit non-goals

- No benchmark-ID special casing
- No validator, prompt, or GenerationOptions changes
- No production wiring in M12B-007A
