# Unresolved-language policy — M12B-007F

Applied only when resolver confidence is insufficient (`enforcesPostValidation == false`).

1. Skip when raw decision is `noChange`.
2. Assess **source evidence** via boundary-aware markers + Portuguese morphology (score ≥2 required for strong evidence). Ambiguous/mixed/weak source → **pass** (do not invent language).
3. Assess **output** via `NLLanguageRecognizer` (same thresholds as M12B-007E independent assessment).
4. Reject only when output confidence is **high**, output maps to PT/EN/ES, and output language ≠ strong source evidence language.
5. Never upgrade unresolved inputs to high-confidence PT/EN/ES resolution.

Technical fragments (`retry`, `API retry`, `deploy`) remain unblocked because source evidence stays ambiguous.
