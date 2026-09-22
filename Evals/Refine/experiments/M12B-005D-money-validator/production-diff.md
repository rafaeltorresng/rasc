# M12B-005D production diff

- Added `RefineMoneyLiteralValidator` beside the existing exact validator.
- Added explicit money currency/value parsing, ambiguity states, and one-to-one multiplicity matching.
- Extended internal protected-literal diagnostics with `money` and money-specific rejection reasons; no user content is logged.
- Chained money finalization after exact protected-literal finalization in the Scratchpad and eval pipelines.
- Expanded exact-validator semantic exclusions to reserve explicit currency-code spans for the money validator.
- Added deterministic contract, selection, multiplicity, known-failure, and one-generation tests.

No prompt, resolver, language validator, sampling, provider session, preflight, UX, schema, or retry behavior changed.
