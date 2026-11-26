# Protocol

Reproducible. No private data. No forced ranking.

## Hardware & software (this round)

- **Mac:** Mac15,6 MacBook Pro, Apple **M3 Pro**, 11 cores (5P+6E), **18 GB**, built-in microphone/speakers. (matches Round3 + M13A machine).
- **macOS:** 26.5.1 (25F80). **Xcode** 26.2 (17C52). **Swift** 6.
- **App:** Rasc **0.1.16 build 22**; source commit recorded in `run.json`. **Debug** build for in-app CLI eval; **Release** build verified separately; no other load; no network for inference.
- **Model:** as in README §Model identity. Model **already installed** locally; `RASC_EVAL_*` env recorded.
- **Foundation Models (Refine):** `SystemLanguageModel.default.availability == available` re-verified; live smoke re-run (opt-in).

## Corpora

### Primary: real human read speech (Google FLEURS, CC-BY-4.0)

- `google/fleurs` `test` split, **en_us** + **pt_br**, deterministic seed `20261126`, **30 clips/language**, 2.0–18.0 s, real human read speech, diverse speakers (speaker ids not exposed; `id` preserved). Reference = `raw_transcription` (with punctuation/case) + `transcription` (normalized) both preserved. 16 kHz mono 16-bit PCM WAV via ffmpeg. **No transcript editing.**
- Reproduce: `scripts/prep_fleurs.py` (download FLEURS test parquet; `--count 30`). Raw audio not committed; `corpus/manifest.json` + per-clip `sourceId`/`sourcePath` + `license`.
- **Read speech, not spontaneous dictation.** Hesitations/fillers/self-correction are in Round3 conversational sets, not FLEURS.

### Controlled perturbations (real human speech + perturbation; labelled)

`scripts/perturb.py`, balanced EN+PT subset, **12 base + variants**. Reference unchanged.

- `trailing_silence_3s`, `leading_silence_2s` → **pauses/silence**
- `added_noise_m15db` → **background noise**, white noise added at **−15 dB SNR** (speech RMS preserved; simple one-pole pink mix; deterministic seed 4567)
- `tempo_fast_1p25`, `tempo_slow_0p8` → **speaking rate** (ffmpeg `atempo`; reference unchanged; pitch preserved-ish)
- **non-speech controls:** `silence_1s`, `silence_3s`, `click_only` (no reference)

### Comparable previous round (not re-run, same model revision)

Round3 held-out, same app-code path, same scoring: **AMI IHM EN 64**, **Tarsila NURC-SP PT-BR conversation 64**, **CS-FLEURS read PT-EN mixed 40**. Pooled WER + 95% bootstrap. Cited as **comparable**, not re-measured. Round1 synthetic TTS corpus (`Experiments/VoiceCapture/corpus.json`, `say` + generated noise) is **synthetic**, engineering probe only.

### Not yet available (honest gaps)

- **Spontaneous multi-speaker code-switching** corpus (CS-FLEURS is read, one speaker per pair). Round3 explicitly notes this.
- **Real human recordings of *this* dictation task** (proper names, technical vocab, numbers, self-correction spoken by real users on this Mac). No private audio. Round3 has some; **synthetic TTS** Round1 has technical probes (labelled synthetic).
- **Accented non-US English / non-PT-BR** variety; FLEURS covers speaker diversity in en_us/pt_br; not measured across other accents.
- **Physical microphone + acoustic-loopback** end-to-end on this Mac with real human voice (we have no speaker-as-human; see §Native).

## Scoring

- **WER** = word edits / reference words; **NFC + casefold + curly-quote + dash normalization + punctuation strip**; standard Levenshtein. **Pooled** (not per-clip average).
- **CER** = char edits / reference chars (stripped).
- **werPunctuationSensitivePercent** = WER keeping punctuation tokens.
- **Punctuation retention:** reference vs hypothesis punctuation-mark counts.
- **Empty transcripts** + **non-speech outcomes** + **errors** reported, never dropped.
- **Semantic fidelity:** not auto-scored; Round3 human-readable semantic findings + a manual inspection of this round's outputs; **no independent adjudication panel**.
- **Editing effort:** **not measured** (no human edits); WER + punctuation as proxies. Round3 notes editing-effort measurement still open. Monologue's "estimated edits" is a separate, vendor, AI-editor metric (see competitive doc) — **not used**.
- **Verbatim vs refinement:** transcription WER is verbatim; **Refine** is separate; not mixed.
- `scripts/score.py`. Round3 reuses `Experiments/VoiceCapture/score.py` + `Bench/score-held.py`.

## Latency

Measured inside the **actual production `VoiceModel.transcribe`** + app boundary, not a reimplementation. **`ContinuousClock`.**

- **Initialization:** `model.prepare()` **cold** (release + reload; fresh process where noted) vs **warm**; `modelLoadMs`; Core ML specialization re-trigger risk documented. `manager.initialize(models:)` per capture = `initializeMs`.
- **Inference:** `manager.transcribe` = `inferenceMs`. **Finalization/cleanup:** `manager.cleanup` = `cleanupMs`. **Total** `transcribeTotalMs`.
- **Transcribe-internal split** via `VoiceModel.TranscriptionTiming`.
- **Text delivery:** clipboard write + AX insertion measured separately (native probe); **SQLite save** Round3 ~1.8 ms; **app full pipeline** Round3. **Mic + compositor** excluded here; Round3 measures physical framing.
- **RTF** = inferenceMs / (audioSeconds*1000); lower faster. **Not clamped.**
- **p50/p95:** sorted; p95 = `ceil(0.95*n)-1`. **Cold vs warm.** **n** reported.
- **This round:** app-code eval `n=60`, `n=75`, `n=72`. **Physical-mic end-to-end p50/p95 not measured this round; Round3 `n=168` + `n=6`.**
- **Not extrapolated** to other hardware/OS.

## Conditions

Warm model (prepared once) + cold variant; no network; no other apps; fresh app identity; no private audio; no streaming; no language hint; no vocab; **no Refine** during transcription measurement; **Release** build verified; **mic physical path** separate. Core ML cache not reset between runs (documented).

## Native validation

Per `docs/NATIVE-UI-VALIDATION.md`. **Automated:** full domain suite + native window suites (Xcode; LaunchServices in this sandbox cannot launch the test runner; `Scripts/test-domain.py` used); Release + Debug builds. **Native, verified this round:** Release app launch + idle resource sample (then restored DB backup); **AX `AXSelectedText` insertion into TextEdit** native probe. **Not claimed (need physical user + hardware + a11y):** physical key chords incl modifier-only; Accessibility grant for Rasc; global trigger across apps; focus across Spaces/fullscreen/Stage Manager/multi-monitor; **VoiceOver**; **Full Keyboard Access**; **Bluetooth**; **sleep/wake** on active capture; **microphone permission** grant + **Sparkle** continuity; **app-switching mid-recording** insertion target; **CLI verbatim output equals Release app output** (tested Debug; Release build verified, output not diffed); **Core ML cache** on fresh machine; **energy**. **Home multi-selection native click** not claimed.

## Reproduce

```sh
# 1. resolve packages once (xcodebuild build)
# 2. stage model (docs/VOICE-CAPTURE.md): python3 Scripts/stage-voice-model.py ... or use installed
# 3. build Debug app
xcodebuild -project Rasc.xcodeproj -scheme Rasc -configuration Debug \
  -derivedDataPath .derivedData/Rasc CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= build

# 4. corpus (download FLEURS test parquet; venv with pyarrow; ffmpeg)
python3 Experiments/VoiceCapture/Round4/scripts/prep_fleurs.py \
  --parquet en_us_test.parquet --language en_us --count 30 --out .../corpus/fleurs-en
# merge; python3 .../scripts/perturb.py ...

# 5. run actual app pipeline (DEBUG; model installed; no note DB writes)
RASC_EVAL_COMMIT=$(git rev-parse HEAD) RASC_EVAL_MACHINE="..." \
  Rasc.app/Contents/MacOS/Rasc --run-voice-evals \
  --corpus .../manifest.json --output .../results/run --repetitions 1

# 6. score
python3 Experiments/VoiceCapture/Round4/scripts/score.py results.jsonl --out score.json --group-by language
```

No private audio. No network. No cloud. No model changes. **Rasc does not change model/architecture to improve benchmarks.**
