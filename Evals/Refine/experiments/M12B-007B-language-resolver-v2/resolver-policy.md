# Resolver policy — M12B-007B production v2

1. **Technical-only / tiny guard** — ≤3 tokens, or all tokens in a small technical allowlist with no romance markers → unresolved.
2. **Boundary-aware marker scoring** — lexical markers must match as standalone tokens/phrases; no substring hits (`la` ⊄ `fila`, `el` ⊄ `example`).
3. **No technical-English boost** — `retry`, `queue`, `_` are not standalone language evidence.
4. **Stricter mixed declaration** — require near-tie at score ≥2 on two languages.
5. **NL tie-break** — only when combined text ≥20 chars, top hypothesis ≥0.55, margin ≥0.20.
6. **Unresolved fallback** — ambiguous / insufficient; never `Locale.preferredLanguages`.
