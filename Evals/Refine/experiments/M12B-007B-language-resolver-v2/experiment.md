# M12B-007B — Production language resolver v2

## Hypothesis

M12B-007A showed resolver-only gains from v2 architecture plus boundary-aware marker matching. M12B-007B wires that resolver into production generation and measures end-to-end wrong-language safety.

## Scope

- Production resolver v2 only
- No validator, selection-guard, sampling, noChange, UX, DB, or generation-count changes
- One Foundation Models generation per eligible request
- Eval shadow records legacy resolver v1 alongside v2

## Runs

- Full dev
- Full validation
- Permanent regression
- Critical stability ×5
- Targeted language slice
