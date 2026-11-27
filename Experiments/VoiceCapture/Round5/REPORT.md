# Round 5 Competitive Voice Capture & End-to-End Evaluation Report

**Date:** 2026-11-27  
**Machine:** Apple M3 Pro (18 GiB unified RAM), macOS 26.x  
**Branch:** `exp/voice-competitive-and-refine-evals` (baseline `main @ 578d02a`)  
**Engine under test:** Rasc local **Fluid Speech Pro** (`AsrModelVersion.fluidParakeetPro` / `FluidAudio`, Core ML offline, model revision `3b9d38a93d606f84011e5a0a669b7ea146375a22`) wrapped by real Rasc production types (`VoiceAudio`, `MicBuffer`, `VoiceModel`, `VoiceTranscriptSanitizer`, `NoteRepository`, `VoiceTextInsertion`), compiled in **Release (`-O`)** as `/tmp/rasc-bench-pkg/RascBench.app`.

---

## Methodology Separation (Zero Metric Conflation)

1. **Section A — Paired Local Benchmarks (Identical Hardware, Identical Audio, Identical Scoring):**  
   Direct head-to-head execution on the same M3 Pro Mac using `Experiments/VoiceCapture/Round5/scripts/score_round5.py`:
   - `rasc_fluid`: Rasc `VoiceModel` + `VoiceTranscriptSanitizer`
   - `rasc_fluid_plus_refine`: Rasc `VoiceModel` + `FoundationModelsRefinementProvider` (measured on VoiceArena)
   - `rasc_fluid_pad200`: Ablation testing `+200 ms` leading silence padding on `round3_held`
   - `apple_speech_transcriber`: Apple on-device `SpeechTranscriber` + `SpeechAnalyzer` (`en_US` / `pt_BR`, macOS 26 API)
   - `whisper_large_v3_turbo`: Local Apple-Silicon MLX `mlx-community/whisper-large-v3-turbo` (`temperature=0.0`, representative local Whisper engine behind Superwhisper local / Handy / VoiceInk)
2. **Section B — Non-Paired Public Landscape Context (Published Third-Party Metrics Only):**  
   Explicitly separated metrics from **VoiceArena** (LLM-judged ZER/AMEND), **Codictate** (`ms/s`), and **Open ASR Leaderboard** (server GPU model WER/RTFx). Never mixed into Section A tables.

---

## Section A — Paired Local Benchmarks

### 1. VoiceArena Dictation Benchmark (`n = 151`, US English, 7 real-world dictation domains)

Corpus: Hugging Face `VoiceArena/Dictation_Dataset` (`test` split, `CC-BY-NC-4.0`, dual references: verbatim `spoken_text` and clean target `intended_text`, containing self-corrections, disfluencies, numbers, currencies, emails, URLs, and multi-paragraph speech up to ~90s).

| Engine | Spoken WER ↓ | Spoken CER ↓ | Punct WER ↓ | Intended normCER ↓ | Intended exactCER ↓ | Exact Match ↑ | Num/Email/URL Retained ↑ | Empty | Warm p50 ↓ | Warm p95 ↓ | Peak Memory |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| **Rasc Fluid Speech Pro** | **8.925%** | **7.063%** | **12.827%** | **5.644%** | **8.110%** | 12/151 (7.95%) | 68.78% (141/205) | **0** | **65.6 ms** | **368.8 ms** | **55.9 MiB** (`phys_footprint`) |
| Rasc Fluid Pro + Refine | 20.645% | 17.936% | 24.340% | 13.863% | 16.234% | 15/151 (9.93%) | 74.15% (152/205) | 1 | 65.6 + 1043.1 ms | — | — |
| Apple `SpeechTranscriber` | 11.456% | 8.744% | 15.788% | 5.824% | 8.736% | 14/151 (9.27%) | 71.71% (147/205) | 0 | 218.4 ms | 923.5 ms | System daemon |
| `mlx-whisper` `large-v3-turbo` | 11.609% | 10.212% | 16.618% | 7.115% | 9.870% | **17/151 (11.26%)** | **79.51% (163/205)** | 0 | 1382.8 ms | 3512.0 ms | **2.41 GiB** MLX peak (1.72 GiB RSS) |

*Cold first-load (`modelLoad`): `283.5 ms` for Rasc Fluid Pro; `49.2 s` (`49,218.7 ms`) including Hugging Face weight fetch for `mlx-whisper` (and `2,010–2,197 ms` when cached on subsequent runs).*

#### Domain Breakdown (VoiceArena `n = 151`)

| Domain (`n`) | Fluid WER (Spoken) | Apple WER (Spoken) | Whisper WER (Spoken) | Fluid Intended normCER | Refine Intended normCER | Apple Intended normCER | Whisper Intended normCER | Fluid p50 | Whisper p50 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `ai_prompt` (22) | **5.732%** | 7.472% | 6.141% | 7.097% | 56.251% ⚠️ | 8.284% | **6.878%** | 103.6 ms | 1426.8 ms |
| `code` (26) | 12.148% | 14.736% | **9.674%** | 5.136% | 12.713% | 6.080% | **4.468%** | 61.1 ms | 1366.8 ms |
| `docs_notes` (22) | **9.922%** | 13.446% | 10.836% | 8.820% | 9.612% | 9.203% | **7.073%** | 64.8 ms | 1374.9 ms |
| `email` (22) | **7.338%** | 9.812% | 8.703% | 4.718% | 6.058% | 4.624% | **3.265%** | 128.9 ms | 1513.1 ms |
| `long_form` (10) | **9.772%** | 12.856% | 18.074% | 3.802% | **3.106%** ✅ | 3.802% | 11.364% | **390.6 ms** | 3650.5 ms |
| `personal_messaging` (25) | **7.186%** | 8.832% | 8.982% | 7.335% | 8.086% | 5.015% | **4.708%** | 56.6 ms | 1352.6 ms |
| `work_chat` (24) | **10.114%** | 11.746% | 10.277% | 6.443% | 11.176% | 7.317% | **6.407%** | 58.2 ms | 1361.6 ms |

**Key VoiceArena Insights:**
- **Spoken accuracy & speed:** Rasc Fluid Pro wins overall WER (`8.93%` vs Apple `11.46%` vs Whisper `11.61%`) and runs **`3.3×` faster than Apple `SpeechTranscriber`** and **`21.1×` faster than `mlx-whisper` turbo** at **`55.9 MiB`** peak process footprint (~`40×` less memory than `mlx-whisper`).
- **ITN & Refine complementarity:** Spoken WER understates Fluid Pro's usefulness because VoiceArena `spoken_text` writes verbalized numerals (`"twenty nine fifteen"`, `"four B"`, `"eighty five percent"`) that Parakeet accurately normalizes (`"2915"`, `"4B"`, `"85%"`). Explicit Refine further lifts `num/email/URL` retention (`68.78% → 74.15%`, converting `"Priya.raman at northwind.io"` → `"Priya.raman@northwind.io"`) and improves `long_form` `intended_text` normCER (`3.80% → 3.11%`).
- **Important Refine caveat (`⚠️ ai_prompt`):** Because Refine organizes notes rather than executing prompts, feeding standalone ChatGPT-style questions (e.g., `"How do I fix a squeaky door hinge?"`) triggered the on-device 3B Apple Foundation Model to **answer the question** (`ai_prompt` normCER `7.10% → 56.25%`) and hit 1 `providerFailure` (`dict_0279`). This confirms why Refine in Rasc is strictly **explicit, previewed, and reversible**.

---

### 2. Multilingual & Code-Switching Benchmarks (`Round 3 Held n = 168`, `FLEURS-60 n = 60`)

#### A. Round 3 Held (`n = 168`: `64` AMI EN meeting + `64` Tarsila PT-BR conversation + `40` CS-FLEURS PT-EN)

| Engine | Overall WER ↓ | CER ↓ | Punct WER ↓ | Empty | `en-meeting` (64) | `pt-conversation` (64) | `pt-en-read-switch` (40) | Warm p50 ↓ | Warm p95 ↓ |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| **Rasc Fluid Pro (`0 ms` pad)** | **14.151%** | **7.819%** | **20.665%** | 5 (`1 EN, 4 PT`) | **12.598%** | **21.823%** | **8.668%** | **42.2 ms** | **67.0 ms** |
| Rasc Fluid Pro (`+200 ms` pad) | 15.002% | 7.863% | 21.219% | 5 (`1 EN, 4 PT`) | 12.992% | 23.620% | 8.985% | 42.3 ms | 70.2 ms |
| Apple `SpeechTranscriber` | 23.466% | 12.883% | 32.621% | 8 (`6 EN, 2 PT`) | 18.701% | 25.546% | 24.313% | 68.9 ms | 163.2 ms |
| `mlx-whisper` `large-v3-turbo` | 20.152% | 11.574% | 27.039% | **0** | 26.969% | 26.573% | 11.205% | 1291.3 ms | 1412.8 ms |

**Tarsila (`pt-conversation`) Stratified by Reference Word Count:**
- `<= 5 words` (`n=17`): Rasc Fluid `50.00%` (`3` empties) | Rasc `+200ms` `50.00%` (`4` empties) | Apple `36.21%` (`2` empties) | Whisper `70.69%` (`0` empties, hallucinated Cyrillic `"Мои зямы нашли."` / `"Найди здесь, в округе."` and `"Gracias."` on short clipped turns).
- `6–15 words` (`n=26`): Rasc Fluid **`30.488%`** (`1` empty) | Rasc `+200ms` `35.772%` (`0` empty) | Apple `32.927%` | Whisper `36.179%`.
- `> 15 words` (`n=21`): Rasc Fluid **`13.895%`** (`0` empties) | Rasc `+200ms` `14.105%` | Apple `20.421%` | Whisper `16.211%`.

**Onset Padding Decision:** Adding `200 ms` leading silence rescued 2 specific utterances (`"Mas é uma."`, `"DNA."`) while causing 3 other short clips to flip to empty/hallucinate, worsening `pt-conversation` WER by `+1.80 pp` and overall WER by `+0.85 pp`. **`0 ms` remains strictly better.**

**Sanitizer Validation (`VoiceTranscriptSanitizer`):** Stripped literal `<unk>` tags acting as quote/parenthesis artifacts on `2/151` VoiceArena, `1/168` Round 3, and `3/60` FLEURS-60 clips cleanly (`"centuries <unk> AD"` → `"centuries AD"`) with zero unintended edits.

#### B. FLEURS-60 (`30 EN` + `30 PT-BR` clean read speech)

| Engine | Overall WER ↓ | `en-US` WER (30) ↓ | `pt-BR` WER (30) ↓ | Overall CER ↓ | Punct WER ↓ | Warm p50 ↓ | Warm p95 ↓ |
|---|---:|---:|---:|---:|---:|---:|---:|
| **Rasc Fluid Pro** | **4.961%** | **5.965%** | 3.949% | **1.787%** | **7.920%** | **53.3 ms** (`53.7 EN / 53.1 PT`) | **103.0 ms** |
| `mlx-whisper` `large-v3-turbo` | 5.433% | 7.064% | **3.791%** | 2.267% | 9.022% | 1341.1 ms | 1432.1 ms |
| Apple `SpeechTranscriber` | 8.425% | 9.890% | 6.951% | 3.974% | 13.636% | 130.9 ms | 274.2 ms |

---

### 3. Long-Form Capture (`30 s – 300 s`): `16 kHz`, `48 kHz Mono`, `48 kHz Stereo Ch1`, Mixed `PT-EN`

#### Root-Cause Diagnosis During Investigation (Why Two Separate Long-Form Sets Exist)
1. **Un-normalized `fleurs-en` gain mismatch (`42 dB`):** Measuring `Experiments/VoiceCapture/Round4/corpus/fleurs-en` revealed clip 0 (`"Swirl..."`) has `rms=0.12238` while clips 1–2–5–6–7–8 are `rms=0.00091–0.00278` (`33–43 dB` quieter). Packing a `-18 dBFS` clip and a `-60 dBFS` clip into the same 15 s preprocessor window suppresses the quiet clip in Parakeet's per-chunk mel normalization and triggers repetition loops in `mlx-whisper` (`67.98%` WER at `60s`, `111.40%` at `300s mixed`).
2. **Loudness-matched (`-20 dBFS` RMS per utterance) validation (`longform_norm`):** Normalizing utterances to `-20 dBFS` before stitching restored 21/22 sentences across `300s` (`norm_mixed_300s` improved `36.08% → 11.57%`; overall WER dropped `13.72% → 9.605%`, `CER 5.155%`).
3. **Resampling & Memory (`VoiceAudio.mono16k()` vs `FluidAudio` `ChunkProcessor`):**
   - `VoiceAudio.mono16k()` keeps **100% of frames** (`4,800,000 / 4,800,000` frames at `300s @ 48 kHz`) and `MicBuffer` active-channel selection correctly chose channel 1 on `long_pt_br_300s_48k_stereo_ch1` (`5.143% WER`, whereas `BenchRunner` `apple-speech` read `channels.first` and returned empty `100% WER` on quiet channel 0).
   - However, single-shot `VoiceAudio.mono16k()` allocated full `14.4M`-frame input buffers (`3.2×` slower at `48 kHz / 300 s`: `17–40 ms` single-shot vs `12.5 ms` chunked and `+55 MiB` transient RAM spike). **Production fix scheduled for Stage 4.**
   - A standalone probe of `12.88–27.76 s` recognized the English clause missing around `20.56–25.76 s` in the combined transcript. The trace in the reliability follow-up below shows where the loss occurred. It also separates subword corruption at joins from missing decoder output.

#### Summary: Loudness-Matched (`-20 dBFS`) `30s–300s` (`n = 11`)

| Engine | Overall WER ↓ | Overall CER ↓ | `300s` EN (16k) WER | `300s` PT-BR (16k) WER | `300s` Mixed WER | `300s` 48k Mono WER | Warm p50 ↓ | Warm p95 ↓ | Warm RTF p50 ↓ |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| **Rasc Fluid Pro** | **9.605%** | **5.155%** | **10.31%** (`7.95%` pair avg) | **5.33%** | **11.57%** | 10.31% | **821.3 ms** | **1461.1 ms** | **0.005** (`200× RT`) |
| Apple `SpeechTranscriber` | 16.423% | 9.501% | 10.21% (`avg`) | ~10% | 37.01% | **8.76%** | 1140.7 ms | 3710.8 ms | ~0.006 |
| `mlx-whisper` `large-v3-turbo` | 35.054% | 23.616% | 27.82% | ~28% | 64.41% | 46.74% | 9424.1 ms | 15069.9 ms | ~0.052 |

*(Un-normalized dynamic-range stress test `n=17`: Rasc Fluid Pro `13.720%` WER / `828.1 ms` p50 vs Apple `24.275%` / `909.1 ms` vs Whisper `52.062%` / `9059.5 ms`.)*

---

### 4. End-to-End Voice Latency Breakdown (Release `RascBench`, Awake `caffeinate -i`, Isolated DB & Ephemeral Pasteboard)

Measured across 15 VoiceArena clips (`cold` `n=1`, `warm` `n=15`, `post_idle_release` `n=5` after releasing model weights so Core ML reloads from warm OS page cache):

| Stage / Milestone | Cold First Use | Warm p50 (`n=15`) | Warm p95 (`n=15`) | Post-Idle Release p50 (`n=5`) |
|---|---:|---:|---:|---:|
| **Shortcut → Preflight Ready** (`AVCaptureDevice` + `AXIsProcessTrusted` + `CGSession`) | 46.94 ms | **31.04 ms** | 35.89 ms | 50.56 ms |
| Core ML `modelLoadMs` | 261.70 ms | **0.012 ms** | 0.017 ms | 104.11 ms |
| `audioPrepareMs` (`mono16k` + slice) | 1.51 ms | **0.100 ms** | 0.168 ms | 0.110 ms |
| `AsrManager` `initialize` + `cleanup` | 0.065 ms | **0.040 ms** | 0.052 ms | 0.042 ms |
| Core ML + TDT `inferenceMs` | 116.49 ms | **65.33 ms** | 147.74 ms | 109.55 ms |
| `VoiceTranscriptSanitizer.clean` | 0.98 ms | **0.065 ms** | 0.096 ms | 0.070 ms |
| **Finish → Transcript Ready** | **380.82 ms** | **65.55 ms** | **169.34 ms** | **205.86 ms** |
| GRDB Scratchpad `createScratch` + `fetchEditable` | 2.63 ms | **0.420 ms** | 1.001 ms | 0.417 ms |
| **Finish → Scratchpad Editable** | **383.46 ms** | **65.95 ms** | **169.78 ms** | **206.26 ms** |
| `VoiceTextInsertion` prep + ephemeral copy | 0.316 ms | **0.121 ms** | 0.183 ms | 0.141 ms |
| **Finish → Dictate Delivery** | **381.14 ms** | **65.67 ms** | **169.46 ms** | **205.99 ms** |

*(Dictation insert-at-cursor skips clipboard fallback overhead when `AXUIElementSetAttributeValue` succeeds; end-to-end persistence and clipboard preparation add `< 0.5 ms` p50.)*

---

## Section B — External Competitive Landscape Context (Published Reference Metrics, Non-Paired)

These numbers come from public third-party benchmarks with **different methodologies, runtimes, and/or cloud LLM post-processors**. They frame where Rasc sits in the ecosystem and must **never** be mixed directly into Section A paired tables:

- **VoiceArena Dictation Bench (LLM-judged Zero Edit Rate `ZER` ↑ & `AMEND` ↓ via Claude Opus judges over cloud/hybrid consumer apps):**  
  Wispr Flow `79.4% ZER / 0.40% AMEND`, Gemini Dictation `75.8% / 1.22%`, Willow Voice `75.7% / 1.88%`, Granola `71.7% / 1.04%`, Meta AI `69.4% / 2.54%`, ChatGPT Dictation `64.3% / 1.15%`, Claude Dictation `64.0% / 0.93%`, Superwhisper `59.8% / 1.44%`, Perplexity Dictation `52.7% / 1.85%`, Apple Dictation `34.6% / 2.60%`. *(Rasc `intended_text` deterministic exact/normCER is not LLM-judged ZER.)*
- **Codictate (local macOS dictation `ms/s` wait per second of audio):**  
  Reports NVIDIA Parakeet TDT 0.6B v3 around `11–51 ms/s` (`~80 MB` active footprint class) vs OpenAI Whisper `Large V3 Turbo Q5_0` / `Large V3` around `65–160+ ms/s` (`~700 MB–3.5 GB`). In Rasc's paired M3 Pro test (`5.6 ms/s` = `RTF 0.0056` warm on Fluid Speech Pro Core ML ANE), Rasc aligns with and exceeds the low-latency offline Parakeet profile while adding explicit on-device Apple Foundation Models Refine.
- **Open ASR Leaderboard (model-level Linux GPU evaluation, non-Mac):**  
  `nvidia/parakeet-tdt-0.6b-v3` publishes `~6.34%` English average WER and `~4.81–5.06%` core European multilingual average WER at high server GPU throughput (`>1,500×` RTFx).

## Reliability follow-up after `5c4e5ad`

### Where the audio disappeared

The previously cited **20.56 s** locates the clause near the start of the recording. The missing interval is around **20.56–25.76 s** (about **5.2 s**, 14–15 aligned words), repeated at the same shared offset in normalized English recordings of 30, 60, 180 and 300 s. The 16 kHz source shows the omission without resampling. The 300 s 48 kHz derivative retained all 4,800,000 resampled frames and showed the same omission.

The pinned FluidAudio layout uses 14.88 s acoustic windows, a 12.88 s stride and 80 ms of left mel context after the first window. The original per-window trace shows window 1 (zero-based) going quiet after about 19.12 s in token time despite speech in its remaining PCM. Window 2 starts at 25.76 s and emits the tail of the clause. The merged token stream is already missing the words before its timestamp sort. A standalone decode of the same physical PCM from **12.80–27.76 s** also misses the clause. Moving the left boundary by 80 ms to **12.88 s**, with the right boundary fixed, recovers it. The isolated utterance also recovers it. This links the dropout to acoustic window composition and decoder behavior. The current evidence cannot identify which internal mel or TDT step controls the change.

Timestamp order is a separate defect. In the same 300 s sample the pinned merge yields `dri behver'savior`. A local backport of the order-preserving clamp from FluidAudio #830 restores the word sequence at that seam, with normalized WER **9.605% → 9.384%**. The longest contiguous omission remains **19 words** across the set. Upstream #910 and #1056 cover related blank-window and leading-gap cases on upstream v3. Adopting those paths with the pinned Fluid Speech Pro pack was outside the validated dependency configuration. [Order fix](https://github.com/FluidInference/FluidAudio/pull/830), [Blank-window recovery](https://github.com/FluidInference/FluidAudio/pull/910), [Opening-gap repair](https://github.com/FluidInference/FluidAudio/pull/1056)

Short Round 3 clips provide a different control. The same five empties (0.410–2.221 s) occur in the re-run on the single-window route. In the largest blank case, the source has a 2.31% RMS level and alternate recognizers detect fragments. Adding 200 ms of leading silence recovers some very short cases and creates new blanks or incorrect language on others. Nothing in this route can invoke the multi-chunk merger. These are single-window recognition failures on clipped or conversational material. The study does not attribute every short omission to the same acoustic mechanism.

### Paired alternatives and acceptance

The same M3 Pro, macOS 26.5.1 and 21 SHA-256-verified model files were used for the pinned route, fixed independent cuts, pause-seeking independent cuts, and a bounded re-decode. The final variant checks large token gaps for acoustic activity, tries two shorter windows, and compensates for large gain differences only on a retry. It adopts the retry when more audio has token support and most prior token IDs remain represented. Energy guides the retry, and a quiet or noisy span alone supplies no speech label. There is no model replacement, external inference or global padding change.

| Suite | WER, before → after | Longest contiguous deletion | Deletions ≥5 words |
|---|---:|---:|---:|
| Loudness-matched, 30–300 s (11) | 9.605% → 4.720% | 19 → 2 | 11 → 0 |
| Original raw-gain long stress (15 valid references) | 13.734% → 5.263% | 34 → 6 | 27 → 2 |
| Dense multilingual, gain and boundary matrix (25) | 8.518% → 6.273% | 33 → 3 | 5 → 0 |

The gain-stress comparison excludes the historical truncated tail and onset references. Its residual is the same six-word loss in one 300 s English source and its 48 kHz derivative. On the dense matrix, ordered exact-reference matches rose from **91.994% to 94.508%**, reference spans falling below half exact match fell **3 → 0**, and unmatched words next to annotated utterance boundaries fell **38 → 27**. The alignment identified no adjacent duplicate insertions in either matrix output. Fixed cuts were worse than pause-seeking cuts on the normalized corpus and created new boundary errors in continuous fixtures. The ordinary retry recovered the normalized omissions, and adding level handling recovered the long quiet passages in the raw stress set. These metrics use lexical alignment and utterance spans, with separate review of the instrumented decoder timings and specific seams.

**Temporary limit of 120 s.** Across the seven fixtures at 120 s (EN, PT-BR, PT/EN within utterances, raw-gain variants and stereo speech at the cap), the longest aligned deletion after the fix was one word, with zero empty transcripts or failed decodes. The actual MicBuffer path selected the active stereo channel and converted **5,760,000 input frames at 48 kHz → 1,920,000 output frames at 16 kHz**, preserving the complete final sentence. The digital-silence and stationary-noise controls emitted no text. The 300 s paths remain diagnostic; one known omission and the absence of a sufficiently broad live microphone sample keep five minutes outside the candidate cap.

The rerun kept all 312 outputs at or below 15 s byte-identical. Across entire shorter corpora (some clips exceed 15 s), VoiceArena was **8.925% → 8.119%**, Round 3 Held **14.151% → 14.241%**, and unique FLEURS **5.016% → 5.175%**. The historical FLEURS-60 result counted one WAV twice. Round 3 retained its five single-window blanks. The normalized long suite's median timed decode was **814 ms → 1,063 ms**, with the four 300 s normalized derivatives finishing at about 1.81–2.05 s on this machine. These are software timings from the Release runner.

### Reproduction and boundaries

1. Use the existing Round 3 `Bench/stage-held.py` and Round 5 `stage_corpora.py` / `stage_longform_norm.py` to stage the pinned inputs locally. Run [stage_reliability.py](scripts/stage_reliability.py) for the extra fixtures, context probes and unique FLEURS set.
2. Build with [build_bench_runner.py](scripts/build_bench_runner.py). Run `RascBench voice-reliability --model <verified-model-dir> --manifest <manifest.json> --out <raw.jsonl> --strategies pinned,adaptive,fixed`. For the production-cap PCM test use `long-capture-bench --production-limit`.
3. Run [prepare_seam_probe.py](scripts/prepare_seam_probe.py) against a local FluidAudio checkout to create an isolated source copy. Build the harness with `RASC_BENCH_FLUID_CHECKOUT` and a distinct `RASC_BENCH_DIR`. Set `RASC_TRACE_CHUNKS=1` for the pinned trace or `RASC_KEEP_TOKEN_ORDER=1` for the targeted clamp.
4. Use [score_reliability.py](scripts/score_reliability.py) with the corpus manifest and run JSONL. The local runs and diagnostics are in `build/reliability-final`. Only aggregate restricted-corpus metrics are in the web package. [Machine-readable evidence](../../../docs/evidence/voice-competitive-web-data.json)

The capture matrix uses repeated, stitched, lab-recorded sources and fixture audio. A physical microphone pass, target app AX insertion, Bluetooth behavior and exact hotkey/focus/rendering latency remain separate.
