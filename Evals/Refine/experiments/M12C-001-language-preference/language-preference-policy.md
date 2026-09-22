# M12C-001 language preference policy

## Default
- Match note language (`RefineLanguagePolicy.matchNote`)

## Fixed locale
- User selects a supported Foundation Models locale in Settings → Refine → Language
- Resolver uses fixed target contract (`fixed_locale_policy`)
- Validator checks output against selected target, not source note language
- Intentional translation is authorized; ignored target rejects to existing noChange

## Unsupported saved locale
- Execute with Match note language
- Keep stored preference; surface fallback in Settings

## Safety invariants
- Preflight, protected literals, money/percentage/time, selection guards remain active
- One Foundation Models generation only
