# Round 4 results

**Rasc 0.1.16 build 22 · source commit in `run.json` · M3 Pro 18 GB · macOS 26.5.1 · Xcode 26.2 · Debug app + actual `VoiceModel`; Release verified.** See [PROTOCOL.md](PROTOCOL.md). Raw: `results/`. **No private audio. No competitor comparison. No model changes.**

## 1. Transcription accuracy — verbatim WER

### Primary: real human read speech, actual app pipeline (n=60)

Google FLEURS `test`, 30 en_us + 30 pt_br, 16 kHz mono, warm model, no hint, verbatim. **Pooled.**

| Slice | Clips | Ref words | Edits | **WER %** | Norm CER % | Raw CER % | WER punct-sensitive % | Ref punct | Hyp punct | Empty |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| **All** | 60 | 1270 | 68 | **5.354** | 2.054 | 3.025 | **8.884** | 188 | 167 | 0 |
| English (en_us) | 30 | 637 | 39 | **6.122** | 2.189 | 3.452 | **11.020** | 102 | 78 | 0 |
| Brazilian Portuguese (pt_br) | 30 | 633 | 29 | **4.581** | 1.915 | 2.588 | **6.695** | 86 | 89 | 0 |

### Controlled perturbations (n=72 speech + 3 non-speech; real human + perturbation; reference unchanged)

| Condition | Clips | **WER %** | Norm CER % | Raw CER % | Punct-sens WER % | Δ vs base (`6.383%` on this subset) |
|---|---:|---:|---:|---:|---:|---|
| base (read speech) | 12 | 6.383 | 2.489 | 3.329 | 10.559 | — |
| **+3 s trailing silence** | 12 | **6.383** | 2.358 | 3.137 | 10.248 | **0.000 pts** |
| **+2 s leading silence** | 12 | **4.965** | 1.965 | 2.625 | 7.453 | **−1.418 pts** |
| **pauses / silence (combined)** | 24 | **5.674** | 2.161 | 2.881 | 8.851 | **−0.709 pts** |
| **+15 dB SNR pink-filtered noise** | 12 | **8.511** | 3.340 | 4.097 | 11.801 | **+2.128 pts** (noise −15 dB below speech) |
| **tempo faster (atempo=1.25)** | 12 | **6.738** | 2.816 | 3.585 | 11.180 | **+0.355 pts** |
| **tempo slower (atempo=0.8)** | 12 | **8.156** | 2.620 | 3.265 | 11.180 | **+1.773 pts** |
| **speaking rate ± (combined)** | 24 | **7.447** | 2.718 | 3.425 | 11.180 | **+1.064 pts** |
| overall perturbed | 72 | 6.856 | 2.598 | 3.340 | 10.404 | — |

**Non-speech controls:** `silence_1s`, `silence_3s`, `click_only` → **empty transcript**; in shipping app `VoiceCapture` additionally rejects `<0.07 s activity`, no-letter/no-number, and `.noSpeech`. No hallucination observed on silence in this round (Round3 reported occasional empties on short PT fragments; Fluid 4/64 empty PT vs Ultra 0; not re-measured).

**Noise note.** `scripts/perturb.py` synthesizes one-pole low-pass ("pink-ish") noise scaled to **+15 dB SNR** (`rms * 10**(-15/20)`, i.e. noise 15 dB quieter than speech; suffix `noise_m15db`). Our earlier mis-scaled noise probe gave ~47% WER on this subset; corrected **+15 dB SNR** gives **8.511%** (vs **6.383%** base on the same subset, **+2.128 pts**; vs **5.354%** FLEURS pooled, **+3.157 pts**). Numbers above use corrected noise. **We do not hide the failed probe.**

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
| model prepare **warm** (`run.json`) | 0.020 | — | already loaded (`warmLoadMs`: `0.020 ms` fleurs-60 / `0.017 ms` perturbed-75) |
| model prepare **cold** (`release()` + `prepare()`) | — | — | **11,339.71 ms (11.34 s)** on first fresh-binary run (`fleurs-60`); **107.73 ms** warm-OS-cache follow-up (`perturbed-75`); Round3 ~18–19.5 s worst; needs Release reproduction |
| model load / model-ready (warm per-clip) | 0.012 | 0.014 | `modelLoadMs` p50 `0.012` / p95 `0.013`; `modelReadyMs` p50 `0.012` / p95 `0.014` |
| `audioPrepare` (`mono16k` + 1 s pad + `AsrManager()`) | **12.888** | **17.936** | measured inside `VoiceModel.transcribe` (`mean 12.726 ms`) |
| `manager.initialize` (per capture) | **0.034** | **0.036** | `initializeMs` |
| **inference** (`manager.transcribe`) | **55.749** | **107.849** | `inferenceMs` (`mean 61.135 ms`) |
| finalization / `cleanup` | **0.050** | **0.059** | `cleanupMs` |
| **transcribe total** | **69.900** | **126.344** | `transcribeTotalMs` (includes `audioPrepare`) |
| `audioLoad` (WAV disk read in CLI; not in total) | 41.364 | 59.878 | `audioLoadMs`; standalone file I/O in eval runner |
| **real-time factor (`inferenceMs / audioSeconds`)** | **0.005** | **0.008** | n=60 (`p50 0.00533`, `p95 0.00810`, `max 0.011`); **not clamped** |

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

- **Standalone Voice Capture (#100) delivery:** Clipboard (`NSPasteboard.clearContents` + `setString`) and Accessibility `AXSelectedText` insertion (`VoiceTextInsertion.insert`, no synthetic keystrokes, no app activation, clipboard fallback) are verified via unit/domain tests; live external-app delivery latencies and TCC permission/focus transitions across Spaces/fullscreen require manual macOS verification (`docs/audits/2026-11-26-phase1/NATIVE-VALIDATION.md`).
- **SQLite (scratchpad mode):** Round3 ~1.8 ms + scratchpad flush; not re-measured Round4; app opens Scratchpad after save; **recovery** retries.
- **Text delivery p50/p95 on a real frontmost app not measured in Round4.**

## 4. New feature validation (#98, #99, #100 — unmerged Phase 1 PRs `#101`–`#103`)

See `docs/audits/2026-11-26-phase1/NATIVE-VALIDATION.md` for per-PR verification details. In summary, domain/persistence/session tests and Debug+Release builds pass on each PR (`#101`–`#103`), while physical keyboard/modifier interaction, native AppKit click/focus/VoiceOver, and live TCC Accessibility/microphone permission flows are pending GitHub Actions `macos-26` CI / manual interactive desktop checks (`xcodebuild test` cannot launch the test runner in this sandbox due to `IDELaunchErrorDomain Code=20`).

## 5. Refine revalidation (existing evidence reviewed + re-run)

- Existing `Evals/Refine/` (M12B/M12C, protected literals, language, uncertainty, selection, etc.) + `docs/REFINE-RELIABILITY.md` **reviewed**; **not re-run wholesale.**
- **Re-run this round:** `RefineReliabilityTests`, `RefineUncertaintyLossGuardTests`, `FoundationModelsProviderContractTests`, `RefineLanguageContractTests`, `RefinementContractTests`, `RefinementSessionTests`, **live on-device smoke** (`RefineUncertaintyLossGuardLiveSmokeTests`, opt-in) — **all pass.**
- **`SystemLanguageModel.default.availability == available`** on this Mac. **Refine not required for capture/Keep/retrieval.** Refine **preserves original; explicit accept; revision validation; protected literals; language; no cloud.** Refine quality not re-scored with new transcripts in Round4 (transcripts can be fed to Refine; not measured).
- **Not claimed:** Refine + transcript combined WER; human semantic; long-note; per-locale depth this round.

## 6. Application performance

See `docs/performance/APP-PERFORMANCE.md`. **This round:** Release idle **63 MB footprint / ~746 MB RSS @5 s / startup CPU spike then idle**; **39 MB app + separate 622 MiB model**; no auxiliary persistent process; **no telemetry**; voice model **released** on memory-pressure/sleep/disable; **re-prepared**; **CPU+ANE**; CPU-only trade-off **previously measured (Round3) not re-run**; **energy not measured**. Persistence `AppReliabilityScaleTests` + M13A. **Not extrapolated.**

## Limitations

- Read speech ≠ spontaneous dictation; FLEURS + Round3 complementary; **n small**; speaker ids not exposed; **no human adjudication**; **no edit-time**; **no energy**; **no other hardware**; **no competitor run**; **no spontaneous multi-speaker code-switch**; **Core ML cache**; **physical key/a11y/focus not claimed**; **standalone delivery p50/p95 on real app not measured**; **auto-Keep not in shipping Rasc**; **no cloud**; **no streaming**; **no custom vocabulary**; **Refine combined not measured**.
