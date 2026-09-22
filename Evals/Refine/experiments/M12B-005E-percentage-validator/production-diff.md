# M12B-005E production diff

- Added `RefinePercentageLiteralValidator` beside the existing exact and money validators.
- Added explicit percentage extraction, numeric parsing, and one-to-one multiplicity matching.
- Extended internal protected-literal diagnostics with `percentage` and percentage-specific rejection reasons.
- Chained percentage finalization after money finalization in the Scratchpad and eval pipelines.
- Added deterministic contract, selection, multiplicity, known-failure, and one-generation tests.

No prompt, resolver, language validator, sampling, provider session, preflight, UX, schema, or retry behavior changed.
