# M12B-007G — Strict unresolved-language safety guard

## Hypothesis

M12B-007F's Policy A safety rule was useful but ran on `mixed/high` resolver cases, causing two false rejections. Restrict guard eligibility to genuinely unresolved resolver output only.

## Eligibility (only change vs 007F)

Run guard only when:
- resolver label is `ambiguous` or `unknown`
- resolver confidence is `insufficient`
- `enforcesPostValidation == false`

Never run when resolver label is `mixed`, `portuguese`, `english`, or `spanish`.

Within eligible scope, reuse M12B-007F guard behavior unchanged.
