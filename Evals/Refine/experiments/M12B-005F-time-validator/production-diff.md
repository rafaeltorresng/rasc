# M12B-005F production diff

- Added `RefineTimeLiteralValidator` beside existing semantic validators.
- Added explicit time extraction, same-family parsing, and one-to-one multiplicity matching.
- Added time-specific rejection reasons: `ampmChanged`, `crossFamilyRewrite`.
- Extended internal protected-literal diagnostics with `time`.
- Chained time finalization after percentage finalization in Scratchpad and eval pipelines.
- Added deterministic contract, selection, multiplicity, cross-family, and one-generation tests.

No prompt, resolver, language validator, sampling, provider session, preflight, UX, schema, or retry behavior changed.
