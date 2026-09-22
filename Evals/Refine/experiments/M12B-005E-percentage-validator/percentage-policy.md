# Semantic percentage policy

## Definition

Only explicit `%`-marked spans are extracted. Bare numbers are never percentages.

## Invariants

- Numeric percentage value preserved
- Percent notation (`%`) preserved in accepted proposals
- Literal count and duplicate multiplicity preserved via one-to-one multiset matching

## Safe normalizations

- Spacing around `%` (`50%` ↔ `50 %`)
- Decimal separator equivalence when parsing is unambiguous (`12,5%` ↔ `12.5%`)

## Rejections

- Value changes (`50%` → `55%`)
- Marker loss (`50%` → `50`)
- Representation changes (`50%` → `0.5`)
- Multiplicity changes
- Ambiguous source forms transformed without exact literal preservation

## Scope and privacy

Selection validation uses only `request.inputText`. Diagnostics store only class and rejection reason, never note text or numeric values.

## Explicit exclusions

Time, money, date, bare/generic numbers, decimals without `%`, and formatted numbers remain outside this production policy.
