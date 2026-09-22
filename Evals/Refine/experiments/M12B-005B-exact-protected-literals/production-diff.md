# M12B-005B exact production diff

## Production path

1. `RefineProtectedLiteralValidator.swift` adds the small deterministic extractor, exact matcher, rejection reason/class trace, and changed-proposal finalizer.
2. `RefinementResult` adds an optional internal `protectedLiteralTrace`; existing call sites remain source-compatible through a default `nil` value.
3. `ScratchpadSession.performRefinement` still invokes the provider exactly once, then passes that result through the validator. Rejection reuses the existing already-useful/noChange completion path.
4. `RefineEvalRunner` applies the same production finalizer after its single provider call. Evaluation models and reports expose content-free proposal/final-safety counts.
5. The Xcode project adds the new production source file.

```text
request
  -> M12B-004C preflight
  -> existing provider call
  -> existing M12B-001 provider/language validation
  -> exact protected-literal validator
       safe: preserve existing result
       violation: existing noChange result
```

No prompt, Foundation Models provider generation behavior, resolver, language validator, generation options, selection architecture, UX, settings, persistence, or schema changed. There is no retry path and no added-literal guard.
