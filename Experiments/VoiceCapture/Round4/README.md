# Voice Capture evaluation · Round 4

**Scope.** Rigorous, reproducible measurement of Rasc's *actual* transcription pipeline on the current source, separating verbatim transcription from Refine, isolated model benchmarks from end-to-end application measurements. **No forced favorable results.** Competitive landscape is separate: `Experiments/Competitive/COMPETITIVE-EVALUATION.md`.

- [PROTOCOL.md](PROTOCOL.md) — method, corpus, scoring, hardware, conditions, reproduction.
- [RESULTS.md](RESULTS.md) — measured numbers, per-language, perturbation, latency p50/p95, cold/warm, semantic notes, limitations.
- [corpus/](corpus/) — reproducible corpus manifests; raw audio not committed (public FLEURS CC-BY-4.0; reproducible scripts).
- [results/](results/) — raw JSONL + scored summaries + `run.json` (commit, machine, model, config).
- [scripts/](scripts/) — `prep_fleurs.py`, `perturb.py`, `score.py`, in-app `VoiceEvalCommandLine.swift`.
- [Standalone Voice Capture](#standalone-voice-capture) — #100 end-to-end + native AX probe.

## What Rasc is measured against

Rasc Voice Capture ships **Fluid Speech Pro** (`VoiceModelAssets.revision = 3b9d38a93d606f84011e5a0a669b7ea146375a22`, 652,304,885 bytes, SHA-256-verified `VoiceModelManifest.json`), **FluidAudio** commit `386f7195670b77f2954c7ee143ec63fcb50b6c3b`, `AsrModels.loadLocalOnly(version: .fluidParakeetPro)`, **verbatim**, **Core ML CPU + Neural Engine**, 16 kHz mono, **no language hint**, **no streaming**, **no vocabulary rescoring**, batch `AsrManager`, trailing-zero pad to 1 s, 120 ms finish tail, ≥0.07 s activity gate, no silence auto-stop. No network inference. See `docs/VOICE-CAPTURE.md`, `Rasc/Features/VoiceCapture/VoiceModel.swift`.

**Verbatim transcription is measured separately from Refine.** Refine (Apple Foundation Models, explicit, isolated, conservative, reversible) is a separate optional step; its evidence is `Evals/Refine/`, `docs/REFINE-RELIABILITY.md`, `docs/REFINE-V2.md`. We do **not** mix WER with Refine output.

## Model identity / provenance

- **Name:** Fluid Speech Pro (FluidAudio `.fluidParakeetPro`; 0.63B; NeMo/Parakeet-TDT-family Core ML pack).
- **Revision:** `3b9d38a93d606f84011e5a0a669b7ea146375a22`.
- **Bytes:** 652,304,885 total (`VoiceModelManifest.json`; `VoiceModelAssets.totalManifestBytes()`). Round3 recorded 652,305,531 in its *study* app (different pack); shipping app uses **652,304,885**.
- **SHA-256:** every file verified at install; not re-verified in this run beyond re-reading; manifest checked-in.
- **Components:** `Encoder.mlmodelc`, `Decoder.mlmodelc`, `JointDecision.mlmodelc`, `Preprocessor.mlmodelc`, `parakeet_vocab.json` (8192 tokens).
- **Origin:** downloaded once via sandboxed `VoiceModelDownloader` XPC from Hugging Face `FluidVoice-Labs/fluid-speech-pro-coreml` (host-restricted); verified; installed atomically; no network at inference. Importable locally. **Not fine-tuned by Rasc.** Fluid Speech Pro open weights CC BY 4.0 (per FluidVoice; `docs/THIRD_PARTY_NOTICES.md`).
- **Compute:** `MLComputeUnits` CPU + Neural Engine (Round3); Core ML may specialize per machine; cache misses re-trigger specialization.
- **Apple control:** Round3 measured `Apple SpeechTranscriber` (macOS 26) `Apple SpeechTranscriber`; shipping Rasc uses **only** Fluid Speech Pro. No cloud fallback.
- **Refine model:** Apple Foundation Models (macOS 26 + Apple Intelligence; `SystemLanguageModel.default.availability == .available` re-verified this round). Separate; not part of transcription WER.

## Standalone Voice Capture

Issue #100. Output destinations: **Scratchpad** (default, unchanged), **Clipboard**, **Insert at Cursor**; optional independent **Save standalone transcripts in Rasc** (off by default); focus preserved (non-activating capsule); no Scratchpad in clipboard/insert; **Accessibility** required for direct insertion with **clipboard fallback**; **no synthetic keystrokes**; **no network**; **no audio persisted** (memory only); sandbox/privacy unchanged. See `Rasc/Platform/VoiceTextInsertion.swift`, `Rasc/Platform/VoiceCaptureOutput` in `VoiceCapture.swift`, `RascTests/VoiceCaptureTests.swift`.

**Verification status:** Debug + Release builds and unit/domain tests (`Scripts/test-domain.py`, including injected `VoiceTextInsertion` / `VoiceCapture` tests) pass. Live interactive macOS Accessibility grants, focus/Spaces/fullscreen behavior, physical external-app AX insertion matrix, and VoiceOver remain **pending manual verification** in `docs/audits/2026-11-26-phase1/NATIVE-VALIDATION.md` (and `PROTOCOL.md` §Native).

## Headline (this round, verified)

- **Verbatim WER, real human read speech, actual app code, M3 Pro, warm:** FLEURS-EN-30 + FLEURS-PT-30 pooled **WER 5.354%** (normalized CER **2.054%** / raw CER **3.025%**); **EN 6.122% / PT-BR 4.581%**; punctuation-sensitive **WER 8.884%** (**EN 11.020% / PT-BR 6.695%**); **no empty transcripts**. **Not claiming vs competitors.**
- **Perturbations vs `6.383%` subset base:** **pauses/silence 5.674%** (−0.709 pts); **+15 dB SNR pink-filtered noise 8.511%** (+2.128 pts); **speaking-rate ±25/20% 7.447%** (+1.064 pts); **non-speech (silence/click) rejected**; **Round3 conversational (comparable, same model): EN meeting 13.00 / PT conv 21.82 / mixed PT-EN 8.89.**
- **Latency (warm, app code, M3 Pro, n=60):** inference **p50 55.75 ms / p95 107.85 ms**; transcribe-total **p50 69.90 ms / p95 126.34 ms** (includes `audioPrepare` **12.89 ms p50**); **RTF p50 0.005 / p95 0.008**; model-load/ready **0.01 ms**; initialize **0.03 ms**; cleanup **0.05 ms**. **External WAV disk read `audioLoad` 41.36 ms p50 (not in transcribe-total).** **`model.prepare()` after `release()`:** **11.34 s** (`11,339.71 ms`) on the first run (`fleurs-60`) vs **107.73 ms** warm-OS-cache follow-up (`perturbed-75`); Round3 ~18–19.5 s worst; needs Release reproduction. **No app-level p50/p95 on physical mic + full app in this round; see Round3.**
- **Editing effort / semantic fidelity:** **not independently human-adjudicated**; WER + Round3 semantic findings; **no human edit-time measurement.**

See [RESULTS.md](RESULTS.md).
