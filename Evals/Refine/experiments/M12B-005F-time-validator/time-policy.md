# Semantic time policy

## Definition

Only explicit clock-time-shaped literals are extracted:

- 24-hour family: `H` notation and `HH:MM` colon notation
- 12-hour family: hour with explicit `AM`/`PM`

Bare integers, decimal pseudo-times, and inferred natural-language times are excluded.

## Same-family equivalence

### 24-hour family

- `15h` ↔ `15:00`
- `15h30` ↔ `15:30`

### 12-hour family

- `3 PM` ↔ `3:00 PM`
- `3:30 PM` ↔ `3:30PM`

## Rejections

- Value change (`15h` → `17h`, `3 PM` → `5 PM`)
- AM/PM change (`3 PM` → `3 AM`)
- Cross-family rewrite (`15:00` ↔ `3 PM`) even when mathematically equivalent
- Literal drop, multiplicity change, ambiguous transformation

## Scope and privacy

Selection validation uses only `request.inputText`. Diagnostics store only class and rejection reason, never note text or clock values.

## Explicit exclusions

Dates, bare/generic numbers, decimals without clock shape, and formatted numbers remain outside this production policy. This is the final semantic-literal guard for the current iteration.
