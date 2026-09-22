# M12B-007E — Production language validator calibration

## Hypothesis

M12B-007D Policy B: when resolver confidence is high, trust high-confidence independent NaturalLanguage output assessment over marker-detect disagreement for accept/reject decisions.

## Scope

- `RefineLanguageValidator` only
- No resolver, prompt, sampling, unresolved policy, selection/literal guards, UX, DB, or generation-count changes
- One Foundation Models generation per eligible request
