# Refine Final Quality & Reliability Re-Validation Report

**Date:** 2026-11-27  
**Environment:** Apple M3 Pro (18 GiB), macOS `26.5.1 (Build 25F80)`, `FoundationModels` (`system-language-model.default`), `availability = available`, prompt `refine-v2-language-preference`, app `0.1.16`  
**Branch:** `exp/voice-competitive-and-refine-evals`  
**Privacy:** Zero personal notes or personal SQLite databases were touched.

---

## 1. Live M12B Gate Re-Validation (`Scripts/refine-eval.sh`)

| Split (`n`) | Live Objective Pass (2026-11-27) | M12B-008 Baseline (2026-09-22) | Baseline-v2 | Latency p50 / p95 | Protected Literal Corruptions (User-Visible) | Model Proposal Failure Rate | Language Safe Rate |
|---|---:|---:|---:|---:|---:|---:|---:|
| **Validation (`57`)** | **64.9%** (`37/57`) | 54.4% | 43.9% | **747 ms / 1116 ms** | **0** (`2` caught by guard / `12` covered) | **0.0%** | **94.1%** (`2` PT→EN rejected→`noChange`) |
| **Holdout (`72`)** | **63.9%** (`46/72`) | 54.2% | 36.1% | **720 ms / 1105 ms** | **0** (`3` caught by guard / `21` covered) | **0.0%** | **97.1%** (`5` safety rejections) |
| **Regression (`6`)** | **66.7%** (`4/6`) | — | — | **743 ms / 1258 ms** | **0** | **0.0%** | **100.0%** (`0` drift) |

### Regression Case-by-Case Outcomes (`n = 6`)
1. `regression-pt-tiny-expanded-001` (`"deploy?"`): **PASS** (`noChange`, `1.1 ms` preflight `whole_note_single_content_unit`).
2. `regression-pt-to-en-drift-003` (`"falar com João amanhã sobre o export"`): **PASS** (`"Converse com João amanhã sobre o export"` — PT preserved, `João`/`amanhã`/`export` preserved).
3. `regression-over-expansion-005` (`"ver logs"`): **PASS** (`"Ver logs"` — no invented context).
4. `regression-selection-leak-006` (`"ola tudobem"` with surrounding context): **PASS** (`"Olá, tudo bem"` — no leakage of `" como vc ta?"`).
5. `regression-already-good-rewritten-004` (`"Enviar o relatório assinado amanhã."`): Output text identical to input (`"Enviar o relatório assinado amanhã."`); flagged only for `decision=changed` + strict-`noChange` annotation.
6. `regression-pt-ambiguous-fragment-002` (`"ajustar aquilo depois"`): Capitalized first letter only (`"Ajustar aquilo depois"`), failing strict `noChange` without inventing context.

### Verified Safety Guarantees vs Remaining Failure Modes (Live macOS 26.5.1)
- **Zero user-visible corruption of protected literals:** Across `33` covered runs (`12` validation + `21` holdout), the deterministic validator chain caught all `5` raw model corruptions (`3` identifier, `1` integer, plus `2` validation identifiers) and converted them safely to `noChange`.
- **Zero crashes / proposal failures** across all `135` `refine-eval.sh` cases (`57 + 72 + 6`).
- **Residual model boundaries observed in live Holdout/Validation:**
  - *Ultra-short uncertainty dropping:* `short-pt-003` (`"talvez amanhã"` → `"Amanhã"`) and `variant-en-039` (`"maybe onboarding tomorrow"` → `"Onboarding tomorrow"`).
  - *Trailing ellipsis completion:* `incomplete-004` (`"need to check whether..."` → `"need to check whether the new features are working as expected"`, expansion `2.58×`).
  - *Short PT/ES drift or diacritic slip:* `short-pt-004` (`"deploy hoje?"` → `"Deploy today?"`), `variant-es-006` (`"quizás..."` → `"Quizñas..."`).
  - *(Note: `names-001/002` and `meeting-dump-002` in `summary.md` show frozen `corpus.v1` cross-variant `mustPreserve` metadata lists rather than actual hallucination by the model.)*

---

## 2. Live End-to-End Voice → Refine & Multilingual Stress Checks

### A. VoiceArena Spoken-to-Intended Dictation (`n = 151`, US EN)
- **Raw ASR → Refine:** `139 changed`, `11 noChange`, `1 providerFailure` (`dict_0279`), `p50 1043.1 ms` / `p95 3695.6 ms`.
- **Quantitative gains where notes match Refine's role:**
  - `numericEmailUrlRetainedPercent` rose from **`68.78% → 74.15%`** (`141/205 → 152/205`), normalizing spoken symbols (`"at ... dot io"` → `@...`, spoken dollar sums → `$2400`/`$2100`/`$240`, spoken times → `6:30 PM`).
  - `long_form` `intended_text` normalized CER improved from **`3.802% → 3.106%`**.
  - Exact `intended_text` matches rose `12/151 → 15/151` (`docs_notes 1→3`, `personal_messaging 0→3`, `work_chat 5→6`).
- **Clear failure boundary:** When an unedited voice note is an imperative **AI prompt / bare question** (e.g., `ai_prompt` domain `dict_0182`: `"How do I fix a squeaky door hinge?"`), the 3B on-device model answered the question (`normCER 7.10% → 56.25%`) despite explicit prompt guards (`RefinementPrompt.swift:18`). This reinforces why Rasc makes Refine **explicit, previewed, and non-destructive** rather than automatic.

### B. Curated PT-BR & Code-Switched PT-EN Voice → Refine (`n = 16` CC-BY-4.0 clips)
- **Results:** `11 changed`, `4 noChange`, `1 providerFailure` (`mix-r3-por_1706_CC`, `Easter Vigil` safety filter), Refine latency **`p50 1047.2 ms`**, **`p95 1252.8 ms`**.
- **Strengths observed:** Formatted quoted titles cleanly (`Oliver Sachs, em seu artigo O Discurso do Presidente...` → `"O Discurso do Presidente,"`), respected clean PT sentences (`"O Aerosmith cancelou..."` → `noChange`), and preserved balanced PT-EN sentences (`"Everything no universo is made de matéria..."` → `noChange`).
- **Boundaries observed:** Occasional PT diacritic omissions (`pt_br-000001674`: `"água"` → `"agua"`, `"são"` → `"sao"`, dropped `"é"`; `pt_br-000001686`: `"organização"` → `"organizacao"`) and English normalization when English tokens outnumber Portuguese ones inside CS-FLEURS (`mix-r3-por_1689_CC`).

### C. Synthetic Notes Evaluation (`n = 8`, Zero Personal Data)
- **Wins:** Preserved PT hypothesis/uncertainty verbatim (`syn_pt_uncertainty`), preserved all tasks/PR numbers/amounts (`syn_pt_tasks`, `syn_en_numbers_urls`: `8841`, `northwind.io`, `12.5%`), kept clean actionable English note identical (`syn_en_already_good`).
- **Boundary reproduced:** `syn_mixed_bare_prompt` (`"Como configurar retenção automática do modelo no macOS 26?"`) produced a 5-step answer instead of preserving the question; `syn_pt_mixed_tech` translated `"feature flag"` → `"flag de recurso"` while preserving `checkout_v2` and `` `payload.retryCount > 3` ``.

---

## 3. Curated Publishable Examples (CC-BY / Synthetic, Ready for `rasc-web`)

| Category | Input (ASR / Note) | Refine Output | Verdict |
|---|---|---|---|
| **Voice → Money & Invoice Normalization** (`VoiceArena dict_0474`, `CC-BY-NC-4.0`) | *"Hi, Carlos. We got invoice number eight eight four one, but it's I think it's showing twenty four hundred dollars, instead of the twenty one hundred we agreed on. Can you send a corrected one?"* | *"Hi Carlos. We got invoice number 8841, but it's showing $2400 instead of the $2100 we agreed on. Can you send a corrected one?"* | **Win** (`8841`, `$2400`, `$2100`) |
| **Voice → Spoken Self-Correction Cleanup** (`VoiceArena dict_0371`, `CC-BY-NC-4.0`) | *"Lent the tent to my cousin. Actually it was the camping stove, not the tent. He said he'd bring it back after Thanksgiving."* | *"Lent the camping stove to my cousin. He said he'd bring it back after Thanksgiving."* | **Win** (`-49` char edits vs intended) |
| **Long-Form Meeting Recap** (`VoiceArena dict_0544`, `CC-BY-NC-4.0`) | *"...Printed flyers were two hundred and forty dollars... Next check-in call is Thursday at 6 30 PM, and if anything changes before then, email me at fooddrive at eastsidehelps dot org."* | *"...Printed flyers were $240. That comes out of the general fund. Next check-in call is Thursday at 6:30 PM, and if anything changes before then, email me at fooddrive@eastsidehelps.org."* | **Win** (`$240`, `6:30 PM`, `@` email) |
| **PT-BR Uncertainty Preservation** (Synthetic `syn_pt_uncertainty`) | *"talvez o gargalo esteja no checkpoint do SQLite WAL ou no debounce do editor, ainda preciso medir"* | *"talvez o gargalo esteja no checkpoint do SQLite WAL ou no debounce do editor, ainda preciso medir"* | **Win** (hypothesis & IDs intact) |
| **Honest `noChange` Restraint** (`VoiceArena dict_0083`, `CC-BY-NC-4.0`) | *"Hey, just wanted to say, great job on the presentation today. The client clearly loved it and you handled their questions really well."* | Unchanged (`noChange`) | **Win** (voice & intent preserved) |
| **Honest Limitation — Bare Question** (`VoiceArena dict_0182`, `CC-BY-NC-4.0`) | *"How do I fix a squeaky door hinge?"* | *"Try lubricating the hinge with WD-40 or a silicone spray..."* | **Boundary** (3B FM answers bare questions; preview prevents blind overwrite) |
