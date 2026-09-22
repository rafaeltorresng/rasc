# M12C-001 production diff

## Added
- `RefineLanguageSettingsStore` (UserDefaults persistence)
- `RefineSupportedLocales` (SystemLanguageModel.supportedLanguages / supportsLocale)
- Settings → Refine → Language picker

## Changed
- `ScratchpadSession` passes effective language policy into `RefinementRequest`
- `RefinementPrompt` fixed-target instructions + prompt version bump
- Eval runner executes fixedLocale cases via `isExecutableUnderProduction`

## Unchanged
- Match note resolver/validator/unresolved-guard behavior for default preference
- Single-generation FM pipeline and deterministic safety guards
