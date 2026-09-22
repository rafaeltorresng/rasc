# M12C-002 production diff

## Added
- `RefinePreferenceSettingsStore`
- Settings → Refine → Refine preferences text field
- `RefinementRequest.stylePreference`

## Changed
- `RefinementPrompt` preference authority + optional `<refine_preference>` block
- Prompt version → `refine-v2-global-preference`

## Unchanged
- All deterministic safety guards
- Language preference behavior
