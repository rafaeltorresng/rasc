# M12B-007D counterfactuals

Recorded-output simulations only. Production resolver-v2 unchanged unless noted.

## Policy A — unresolved-language safety guard

For resolver-v2 **unresolved** cases only: when independent output-language assessment is **high confidence** and clearly disagrees with **strong** source-language evidence, reject to `noChange`. Do not act when source evidence is genuinely ambiguous.

| Metric | Current | Policy A |
|---|---:|---:|
| Final wrong-language changes | 20 | 16 |
| Wrong-language edits prevented | — | 4 |
| False rejections added | — | 0 |
| Useful refinements lost | — | 0 |

Cases prevented: `selection-extra-007`, `short-pt-012`, `short-pt-013`, `telegraphic-pt-010`

Cases still wrong after A: `acronym-004`, `legacy-selection-unicode-pt-001`, `meeting-dump-003`, `numbers-003`, `selection-extra-001`, `short-pt-009`, `telegraphic-pt-001`, `telegraphic-pt-004`, `telegraphic-pt-005`, `telegraphic-pt-009`, `variant-pt-013`, `variant-pt-014`, `variant-pt-015`, `variant-pt-022`, `variant-pt-023`, `variant-pt-024`

## Policy B — validator calibration

Keep resolver-v2 unchanged. Smallest combined adjustment from false-rejection pattern:

1. **Relax**: accept when independent output assessment is `high` and matches resolved target (even if marker detect disagrees).
2. **Tighten**: reject when independent output assessment is `high` and mismatches resolved target (covers current false negatives).

| Metric | Current | Policy B |
|---|---:|---:|
| Final wrong-language changes | 20 | 19 |
| Wrong-language edits prevented | — | 1 |
| False rejections removed | 13 | 2 |
| New validator misses | — | 0 |
| Useful refinements lost | — | 0 |

False rejections fixed: `already-good-010`, `injection-004`, `medium-pt-010`, `mixed-tech-004`, `mixed-tech-008`, `names-004`, `numbers-002`, `numbers-004`, `numbers-005`, `uncertainty-pt-001`, `variant-pt-028`

New misses: none

## Policy C — resolver changes (report only)

Do **not** implement another resolver heuristic. M12B-007C already rejected short-PT morphology overlay.

| Failure bucket | Cases | Notes |
|---|---:|---|
| Wrong high-confidence resolver target | 4 | Includes mixed PT+EN telegraphic misclassified as EN |
| Unresolved short/telegraphic PT | 13 | 007C fixed 1/6 causal regressions at cost of +4 false PT |
| Theoretically resolver-addressable total | 17 | Not recommended for production |

Generation/validator failures (3) remain even with perfect resolution.
