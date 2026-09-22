# M12B-004B challenge-set summary

This is a separate targeted challenge, not dev, validation, regression, or holdout. It does not alter `corpus.v1.jsonl`, `splits.v1.json`, or baseline artifacts. Every case is frontier-generated, `humanValidated=false`, and maintainer-unapproved.

- Cases: 42
- Languages: PT=14, EN=14, ES=14
- Dispositions: shouldChange=21, shouldNotChange=15, ambiguous=6
- Critical stability subset: 15 cases ×5
- Positive controls use exact canonical outputs only; no subjective ‘make nicer’ expectations are present.
- The stock scorer normalizes case/diacritics, so this experiment independently scores exact NFC surface outputs to distinguish `nao` from `não`.

## Category counts

- acronym: 3
- already-valid: 4
- ambiguous-fragment: 6
- diacritic-repair: 8
- foreign-technical-term: 4
- obvious-typo: 10
- proper-technical-name: 3
- spacing-repair: 3
- technical-term: 1
- valid-slang: 3

## Product asymmetry

Missing a minor spelling repair has low cost for Rasc. Inventing, translating, formalizing, or substantially changing a one-word note has high trust cost. Policy B is preferable only if its simple envelope retains meaningful, highly reliable utility without reopening meaningful harm.

## Separate R$ flag

`R$` → `$` remains a future protected-token issue from M12B-004A. No corpus or production correction is applied here.
