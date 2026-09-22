# Final accepted production reliability stack (M12B)

Verified active in production/eval-faithful path:

1. **Preflight** — `RefinementPreflightPolicy` one-content-unit whole-note noChange (M12B-004C).
2. **Language resolver v2** — `RefineLanguageResolver` (M12B-007B).
3. **FM generation** — single `LanguageModelSession` response per request.
4. **High-confidence language validator** — `RefineLanguageValidator` calibrated thresholds (M12B-007E).
5. **Strict unresolved-language guard** — `RefineUnresolvedLanguageGuard.isStrictUnresolvedEligible` only (M12B-007G).
6. **Protected literal validators** — exact, money, percentage, time finalize chain (M12B-005B–005F).
7. **Selection guards** — replacement-only, size cap, duplicate-after-context (M12B-006A/006B).

## Rejected code not active

- **M12B-007F broad guard** — replaced by strict eligibility in 007G (`isStrictUnresolvedEligible`; mixed/high bypass).
- **M12B-007C short-PT calibration** — no production code present.
- No benchmark-ID conditional logic in guards.
