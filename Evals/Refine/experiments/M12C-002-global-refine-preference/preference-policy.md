# M12C-002 global refine preference policy

## Authority hierarchy
1. Rasc safety contract
2. Language policy (M12C-001)
3. Semantic preservation requirements
4. User Refine preference
5. Note content (untrusted)

## Integration
- Optional Settings text persisted locally (max 500 chars, trimmed)
- Omitted entirely from instructions when empty
- Wrapped in `<refine_preference>` when present
- One Foundation Models generation only
