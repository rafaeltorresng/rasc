# Semantic money policy

## Definition

Only explicit `R$`, `US$`, `$`, `€`, `£`, `BRL`, `USD`, `EUR`, or `GBP` markers are extracted. Bare numbers are never money.

## Currency identity

- `R$`/`BRL`, `US$`/`USD`, `€`/`EUR`, and `£`/`GBP` retain their explicit currency identity.
- Bare `$` has its own ambiguous-dollar identity and is never inferred to mean USD.
- Weakening `R$` to `$`, changing identities, or dropping the marker rejects the proposal.

## Amount parsing

- Integers and one/two-digit decimal fractions parse directly.
- Mixed decimal/grouping punctuation parses only when grouping and the final one/two-digit fraction are structurally unambiguous.
- Repeated three-digit grouping parses deterministically.
- A single separator followed by exactly three digits is ambiguous and requires exact whole-literal preservation.
- Invalid or ambiguous source forms never receive guessed semantic equivalence.

## Matching

Money literals use one-to-one multiset matching. Currency, value, count, and duplicate multiplicity must survive. Safe spacing or provably equivalent punctuation may pass; the validator never rewrites a literal itself.

## Scope and privacy

Selection validation uses only `request.inputText`, so surrounding-note money is not an obligation. Diagnostics store only the class and rejection reason, never note text, currency values, or monetary amounts.

## Explicit exclusions

Time, percentage, date, bare/generic numbers, decimals without currency identity, and formatted numbers remain outside this production policy.
