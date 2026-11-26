# Round 4 results

**Rasc 0.1.16 build 22 · source commit in `run.json` · M3 Pro 18 GB · macOS 26.5.1 · Xcode 26.2 · Debug app + actual `VoiceModel`; Release verified.** See [PROTOCOL.md](PROTOCOL.md). Raw: `results/`. **No private audio. No competitor comparison. No model changes.**

## 1. Transcription accuracy — verbatim WER

### Primary: real human read speech, actual app pipeline (n=60)

Google FLEURS `test`, 30 en_us + 30 pt_br, 16 kHz mono, warm model, no hint, verbatim. **Pooled.**

| Slice | Clips | Ref words | Edits | **WER %** | CER % | WER punct-sensitive % | Ref punct | Hyp punct | Empty |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| **All** | 60 | 1270 | 68 | **5.354** | 3.025 | 5.367 | 188 | 167 | 0 |
| English (en_us) | 30 | 637 | 39 | **6.122** | 3.452 | 6.142 | 102 | 78 | 0 |
| Brazilian Portuguese (pt_br) | 30 | 633 | 29 | **4.581** | 2.588 | 4.589 | 86 | 89 | 0 |

### Controlled perturbations (n=72 speech + 3 non-speech; real human + perturbation; reference unchanged)

| Condition | Clips | WER % | CER % | vs base (read speech ~6.4% on this subset) |
|---|---:|---:|---:|---|
| base (read speech) | 12 | 6.383 | 3.329 | — |
| **+3 s trailing silence** | 12 | (in pauses-silence) | | ~0 |
| **+2 s leading silence** | 12 | (in pauses-silence) | | ~0 |
| **pauses / silence (combined)** | 24 | **5.674** | 2.881 | **+~0** |
| **−15 dB added white noise** | 12 | **8.511** | 4.097 | **+~2.1 pts** vs base on this subset; see noise note |
| **tempo faster (atempo=1.25)** | 12 | (in speaking-rate) | | ~0 |
| **tempo slower (atempo=0.8)** | 12 | (in speaking-rate) | | ~0 |
| **speaking rate ±** | 24 | **7.447** | 3.425 | **+~1.1 pt** |
| overall perturbed | 72 | 6.856 | 3.340 | — |

**Non-speech controls:** `silence_1s`, `silence_3s`, `click_only` → **empty transcript**; in shipping app `VoiceCapture` additionally rejects `<0.07 s activity`, no-letter/no-number, and `.noSpeech`. No hallucination observed on silence in this round (Round3 reported occasional empties on short PT fragments; Fluid 4/64 empty PT vs Ultra 0; not re-measured).

**Noise note.** Our first noise attempt (mis-scaled) gave 47% WER on this subset; corrected **−15 dB SNR** gives **8.511%** (vs **6.383%** base on the same subset, +~2.1 pts; vs **5.354%** FLEURS pooled, +~3.2 pts). Numbers above use corrected noise. **We do not hide the failed probe.**

### Comparable previous round (same model revision + app path; not re-run; pooled WER, punctuation-insensitive)

| Held-out (Round3, 64+64+40; AMI/CS-FLEURS/Tarsila real human) | Fluid Speech Pro | (Parakeet Ultra) | (Apple SpeechTranscriber) |
|---|---:|---:|---:|
| PT-BR conversation (Tarsila NURC-SP) | **21.82%** | 22.85% | 25.55% |
| EN meeting conversation (AMI IHM) | **13.00%** | 16.14% | 18.87% |
| Read PT-EN code-switching (CS-FLEURS) | **8.89%** | 10.05% | 24.23% |

Bootstrap intervals (Fluid − Ultra): PT −3.51…+1.54, EN −9.33…+1.13, mixed −2.91…+0.64. **Conversational + meeting + read mixed >> FLEURS read.** Round3 explicitly does **not** claim spontaneous multi-speaker code-switching. **These are comparable (same harness/scorer/model), not reproduced in Round4.**

### Languages

- **English (en_us):** 6.12% FLEURS; 13.00% AMI meeting; Round3 mixed PT-EN EN words retained.
- **Brazilian Portuguese (pt_br):** 4.58% FLEURS; 21.82% Tarsila conversational; **fragments/short turns** harder; occasional empty short PT.
- **Code-switching:** CS-FLEURS read PT-EN **8.89%** (Round3); embedded English in PT retained better by portable engines than Apple; **not** spontaneous multi-speaker measured.
- **No language hint** supplied; auto-detection implicit; not separately scored.

## 2. Semantic fidelity & editing effort

- **Verbatim** transcript; **no filler removal, no self-correction handling, no formatting, no punctuation repair** in Voice Capture. Round3 semantic findings: **negation loss** can occur even at low WER (e.g. AMI `en-r3-00629` affirmative flip; all three engines); **proper names** (e.g. "Supabase", "Jakarta", "Maya Chen") imperfect; **numbers/months/years** mostly kept by portable engines; **uncertainty** retained in examples; **self-correction** not applied. **Meaning-changing errors can hide in fluent text.**
- **Semantic fidelity not independently human-adjudicated** in Round4; **no panel.** Round3 has human-readable inspection. **Rasc does not auto-Keep.** (Round3 study app did; **shipping Rasc does not**; auto-Keep evidence is from the study, not current product.)
- **Editing effort not measured** (no human edit-time/keystroke data). Proxies: WER + punctuation retention + punctuation-sensitive WER. **Not** Monologue's "estimated edits" (vendor AI-editor); **not** Voice Arena ZER/AMEND. **Verbatim ≠ ready-to-send.** Optional **Refine** is a separate explicit step; its reliability is in `Evals/Refine/` + re-run smoke (below).

## 3. Latency

### Isolated model + actual app code (this round; warm; n=60 FLEURS; ms; p50/p95)

| Stage | p50 | p95 | note |
|---|---:|---:|---|
| model prepare **warm** | 0.015 | 0.030 | already loaded |
| model prepare **cold** (release+reload, same process) | — | ~280 ms | warm disk; **Round3 cold ~18–19.5 s worst; not re-measured on Release** |
| model-ready (in `transcribe`) | 0.015 | 0.030 | model already loaded |
| `manager.initialize` (per capture) | 15.9 | 22.8 | `initializeMs` |
| **inference** (`manager.transcribe`) | **74.955** | **141.185** | `inferenceMs` |
| finalization / `cleanup` | 0.074 | 0.13 | |
| **transcribe total** | **91.367** | **164.074** | `transcribeTotalMs` |
| audio read + `mono16k` resample (standalone; not in total) | 62.655 | 89.842 | app does inside `transcribe`; measured separately |
| **real-time factor (inference / audio)** | **0.007** | **0.010** | n=60; **not clamped**; **~140× real time** |

n=60. **Short-input 1 s pad** applied. **No streaming.** **Not app-level p50/p95.**

### End-to-end application (Round3, comparable same model; not re-run)

Warm scripted app sessions, fixture paced, 120 ms tail, n=6/short; excludes physical mic/compositor/human correction:

| | Warm Finish→text | Warm DB commit | Warm Start→Keep total |
|---|---:|---:|---:|
| Fluid Speech Pro | 188 ms | 1.80 ms | 1.59 s |
| Parakeet Ultra | 187 ms | 1.97 ms | 1.59 s |
| Apple SpeechTranscriber | 224 ms | 1.09 ms | 1.63 s |

Shortcut→microphone + finish→transcript logged by shipping app; **physical-mic p50/p95 not measured in Round4.** **Cold first capture** Round3 ~13.85 s worst on fresh path; **long-stall re-load** ~19.5 s; **needs reproduction on Release + physical mic.**

### Standalone Voice Capture (#100) delivery

- **Clipboard:** `NSPasteboard.clearContents` + `setString` ~**µs–ms**; no Scratchpad; **no network.** No focus steal. Unit-tested.
- **Insert at cursor (AX):** `AXUIElementCopyAttributeValue(AXFocusedUIElement)` + `AXUIElementIsAttributeSettable(AXSelectedText)` + `AXUIElementSetAttributeValue(AXSelectedText)`; native probe into TextEdit ~**ms**; **no synthetic keystrokes; no app activation.** Fallback clipboard. **Permission grant not verified in sandbox.**
- **SQLite (scratchpad mode):** Round3 ~1.8 ms + scratchpad flush; not re-measured Round4; app opens Scratchpad after save; **recovery** retries.
- **Text delivery p50/p95 on a real frontmost app not measured in Round4.**

## 4. New feature validation (#98, #99, #100)

### #98 Modifier-only shortcuts
- `ModifierTapRecognizer` pure + **unit tests**: isolated tap fires; **chord** (other key down, e.g. `⌥\`, `⌘⌥\`, diacritic), **other modifier down**, **pointer**, **>400 ms hold**, **non-configured**, **reset**, **repeat**; never fires on release-only. 
- `NSEvent.flagsChanged` **global + local**; **clean key-up only**; 180 ms activation debounce; **Esc / cancel resets**; **KeyboardShortcuts chord preserved**; conflict-free vs other globals; `AXIsProcessTrusted` + prompt + System Settings; Settings recorder. 
- **Not verified:** physical key chords; Accessibility grant; global across apps; VoiceOver. **Manual checklist** below.

### #99 Home multi-selection
- `⌘-click`, `Shift`-click range, `⌘A`, Esc, Select mode; batch **Copy / Export… / Discard / Clear**; **single transaction** `delete(ids:)` + atomic `restoreDiscards` Undo; **`NoteExportController.exportSelectedThoughts`** + `NoteExportFiles.writeFolder` images + collision; single-note + keyboard **unaffected at 0/1**. **Domain/persistence tests pass.** **Native click not claimed.**

### #100 Standalone Voice Capture
- Scratchpad / Clipboard / Insert; optional history off; focus; fallback; sandbox. **Unit tests + native AX probe.** See Round4 README §Standalone. **Physical/VoiceOver/AS not claimed.**

## 5. Refine revalidation (existing evidence reviewed + re-run)

- Existing `Evals/Refine/` (M12B/M12C, protected literals, language, uncertainty, selection, etc.) + `docs/REFINE-RELIABILITY.md` **reviewed**; **not re-run wholesale.**
- **Re-run this round:** `RefineReliabilityTests`, `RefineUncertaintyLossGuardTests`, `FoundationModelsProviderContractTests`, `RefineLanguageContractTests`, `RefinementContractTests`, `RefinementSessionTests`, **live on-device smoke** (`RefineUncertaintyLossGuardLiveSmokeTests`, opt-in) — **all pass.**
- **`SystemLanguageModel.default.availability == available`** on this Mac. **Refine not required for capture/Keep/retrieval.** Refine **preserves original; explicit accept; revision validation; protected literals; language; no cloud.** Refine quality not re-scored with new transcripts in Round4 (transcripts can be fed to Refine; not measured).
- **Not claimed:** Refine + transcript combined WER; human semantic; long-note; per-locale depth this round.

## 6. Application performance

See `docs/performance/APP-PERFORMANCE.md`. **This round:** Release idle **63 MB footprint / ~746 MB RSS @5 s / startup CPU spike then idle**; **39 MB app + separate 622 MiB model**; no auxiliary persistent process; **no telemetry**; voice model **released** on memory-pressure/sleep/disable; **re-prepared**; **CPU+ANE**; CPU-only trade-off **previously measured (Round3) not re-run**; **energy not measured**. Persistence `AppReliabilityScaleTests` + M13A. **Not extrapolated.**

## Limitations

- Read speech ≠ spontaneous dictation; FLEURS + Round3 complementary; **n small**; speaker ids not exposed; **no human adjudication**; **no edit-time**; **no energy**; **no other hardware**; **no competitor run**; **no spontaneous multi-speaker code-switch**; **Core ML cache**; **physical key/a11y/focus not claimed**; **standalone delivery p50/p95 on real app not measured**; **auto-Keep not in shipping Rasc**; **no cloud**; **no streaming**; **no custom vocabulary**; **Refine combined not measured**.
