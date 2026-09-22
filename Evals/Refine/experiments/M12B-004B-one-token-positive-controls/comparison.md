# M12B-004B — One-token positive-control comparison

| Field | Value |
|---|---|
| Production change | None |
| Prompt | Accepted M12B-001 (`refine-v2-language`) |
| Challenge | 42 separate maintainer-unapproved targeted cases |
| Holdout | Not loaded or run |
| Recommendation | **A — unconditional one-content-unit whole-note noChange gate** |

## Primary metrics

| Metric | Current | Policy A | Policy B |
|---|---:|---:|---:|
| Harmful edits | 26 | 0 | 1 |
| Useful repairs retained | 4 | 0 | 2 |
| Exact canonical corrections | 2 | 0 | 2 |
| Useful case-variant corrections | 2 | 0 | 0 |
| Useful repairs missed | 17 | 21 | 19 |
| Wrong-language outputs | 8 | 0 | 0 |
| Invented information | 10 | 0 | 0 |
| Excessive expansions | 14 | 0 | 0 |
| Unnecessary edits | 13 | 0 | 1 |
| Should-not-change accuracy | 6 | 15 | 14 |
| Ambiguous safe | 2 | 6 | 6 |

Policy A: 6.50 harms prevented per currently demonstrated useful repair lost.

Policy B: 12.50 harms prevented per currently demonstrated useful repair lost.

## Stability (15 cases ×5)

| Policy | Action-instability cases | Success-instability cases | Provider-error runs |
|---|---:|---:|---:|
| Current | 12 | 4 | 1 |
| Policy A | 0 | 0 | 0 |
| Policy B | 2 | 2 | 0 |

## Breakdowns

### byDisposition

| Group | Current exact-expectation success | Current harm | A exact-expectation success | A harm | B exact-expectation success | B harm |
|---|---:|---:|---:|---:|---:|---:|
| ambiguous | 2/6 | 4 | 6/6 | 0 | 6/6 | 0 |
| shouldChange | 2/21 | 13 | 0/21 | 0 | 2/21 | 0 |
| shouldNotChange | 6/15 | 9 | 15/15 | 0 | 14/15 | 1 |

### byLanguage

| Group | Current exact-expectation success | Current harm | A exact-expectation success | A harm | B exact-expectation success | B harm |
|---|---:|---:|---:|---:|---:|---:|
| en | 4/14 | 7 | 7/14 | 0 | 7/14 | 1 |
| es | 2/14 | 11 | 7/14 | 0 | 7/14 | 0 |
| pt | 4/14 | 8 | 7/14 | 0 | 8/14 | 0 |

## Useful refinements Policy A would lose

- `urgnete` → `urgente` (otpc-pt-change-006)
- `recieve` → `Receive` (otpc-en-change-001)
- `seperate` → `Separate` (otpc-en-change-004)
- `untill` → `until` (otpc-en-change-005)

## Useful refinements Policy B would lose

- `recieve` → `Receive` (otpc-en-change-001)
- `seperate` → `Separate` (otpc-en-change-004)

## Policy B envelope

Policy B uses only output-surface and existing language-safety evidence: an accepted changed output, at most two lexical units, length ratio 0.75–1.34, preserved case pattern, and either diacritic-only, exact whitespace split, or one-word edit distance ≤2. Capitalization-only and punctuation-only changes are rejected. It has no word list and does not inspect challenge expectations when deciding acceptance.

## Product asymmetry

A missed minor spelling repair is low cost. An invented, translated, formalized, or substantially changed one-word note is a high trust cost. A narrow envelope is warranted only if the observed retained corrections are meaningful, reliable across PT/EN/ES, stable, and do not reopen material harm.

## Combined decision context

M12B-004A found 13 harmful edits prevented, zero demonstrated utility loss in its original cohort, four wrong-language outputs eliminated, and 15/18 stability-covered cases flapping. M12B-004B supplies the missing positive controls but remains frontier-generated and maintainer-unapproved.

## R$ future issue

`R$` → `$` remains separately flagged as a likely missing protected-token constraint. This experiment does not alter or solve protected-token production behavior.

## Recommendation — A

Recommend **A: unconditional one-content-unit whole-note noChange gate**. This report is evaluation evidence only; the recommendation is not implemented.

Policy A prevents 26 challenge harms at the cost of 4 demonstrated repairs (6.50 harms prevented per repair lost). Policy B retains 2 of 4 demonstrated repairs but reopens 1 unnecessary edit and has 2 action-unstable stability cases. Only 4 of 21 positive controls produced useful canonical or case-variant repairs in the one-pass run, none in Spanish; this limited utility does not justify the semantic risk and extra envelope complexity under Rasc's asymmetric trust cost.
