# Rasc evidence handoff for rasc-web

Rasc is a native macOS scratchpad for unfinished thoughts. Capture, Keep, Home search and Markdown export work with local SQLite. Voice Capture and Dictate use a separate, opt-in speech pack. Refine uses Apple Foundation Models when available and lets the author review a suggested edit before accepting it.

The published artifact in this evidence set is **v0.1.15 build 21**. The **0.1.16 build 22** DMG is retained from source `30c5c14`. **0.1.16 build 25** is the isolated, ad-hoc signed candidate for the feature-freeze test pass. Its build inputs match the consolidating commit, with the source patch and DMG checksums recorded in the release runbook. Source, test harness, DMG and device results carry separate provenance. [Candidate identity](../RELEASE.md#isolated-reliability-candidate-0116-build-25)

## Evidence sources

| Source | What it measures |
|---|---|
| [Efficiency data](efficiency-web-data.json) | Historical sandbox Release workloads, extended study, measured size and build 22 artifact checks |
| [Voice data](voice-competitive-web-data.json) | Historical paired **engine** runs, instrumented software endpoints and the final reliability follow-up |
| [Refine data](refine-web-data.json) | Historical and final runs on the frozen corpus, with separate intent regression results |
| [Screenshot manifest](screenshots/manifest.json) | 38 historical app-view PNGs seeded with synthetic notes and captured from `30c5c14` |
| [Example attribution](examples/ATTRIBUTION.md) | Publication eligibility and attribution for individual audio and text examples |
| [Editorial brief](EDITORIAL-BRIEF.md) | Suggested placement, chart labels and qualifications |

## Historical efficiency

- The active-work stage ran for **8.00 hours of wall time**, with **4.33 hours active** across **15 system sleeps**. The median process physical footprint was **73.70 MiB**. The run completed 32 soak cycles and sampled leaks at intervals.
- The voice-enabled standby captured **8.50 hours of a 24-hour plan** (35.43%, no detected sleep). Its last retained sample was 2026-11-27 at 11:46:05 BRT. Median physical footprint was **33.66 MiB**, ending at **30.94 MiB**. Seven package idle wakeups were counted, with a median of **0/s**. The retained summary measures XNU per-process CPU energy.
- Both stages used an isolated sandboxed Release build from the **PR #107 branch, before PRs #108–#114 and without Sparkle**. The original run manifest recorded the branch context and bundle ID. Treat later short-idle, launch, scale and Sparkle measurements as separate cohorts.
- Logical disk sizes from the earlier artifacts were **40.54 MiB** for the standard Release bundle, **44.50 MiB** for the Sparkle build 22 bundle, **13.14 MiB** for its compressed DMG, and **622.09 MiB** for the separate speech pack. Physical footprint, RSS and neural footprint are process accounting fields with different definitions. The JSON includes the original units and separate columns for these metrics. [Extended study](../../Experiments/Efficiency/results/long_running_20261126/REPORT.md)

## Voice and latency

Fluid Speech Pro, Apple's on-device SpeechTranscriber and MLX Whisper Large V3 Turbo were measured as speech engines on the same M3 Pro. Round 5 historical Fluid Speech Pro WER was **8.925%** on VoiceArena (151 rows), **14.151%** on Round 3 Held (168 rows) and **4.961%** on FLEURS (60 historical rows, 59 unique WAVs). Publish corpus, engine, sample count and hardware with any comparison. The raw-gain long-form comparison has a truncated tail reference and a mismatched stereo-channel comparator. The loudness-matched long set uses stitched read utterances, including related variations of the same source.

The historical **65.55 ms warm median** measures pre-delivered PCM to sanitized transcript. The nearest-rank p95 is **169.34 ms** (`n=15`). The “ready” endpoint checks permission, accessibility trust and session state. The Scratchpad endpoint adds SQLite create/fetch. The Dictate endpoint adds formatting and a write to a unique pasteboard. Real hotkey handling, mic startup, finish padding, window focus, external AX insertion, paste fallback and rendering remain separate physical observations. [Round 5 protocol](../../Experiments/VoiceCapture/Round5/REPORT.md)

The Round 5 trace locates the reported English omission around **20.56–25.76 s on the recording timeline**. It is about five seconds of audio, present in a standalone crop and absent in the corresponding multi-window decoder outputs before merging. Token order can also be corrupted at overlaps. The candidate uses pause-seeking independent windows and a bounded retry. It has a **temporary 120 s limit** after a residual six-word omission in one 300 s gain-stress source and its 48 kHz derivative. The long captures are laboratory stress tests. Spontaneous dictation, physical microphones and target-application delivery need their own validation. [Long-form reliability](../../Experiments/VoiceCapture/Round5/REPORT.md#reliability-follow-up-after-5c4e5ad)

## Refine

Refine runs on-device, on demand and per note. The review UI offers Suggested, Changes and Original. In the paired intent study, 17 of 84 baseline attempts answered or ran the prompt. The final guard and prompt surfaced none in 84 attempts, with one provider failure. Frozen-corpus objective passes were 82/135 before and 79/135 after, with separate denominators for language, literal and changed-output checks. Generated output can still change a detail or decline an edit. Example captions should identify whether the output comes from a historical provider probe or the final guarded path. [Refine study](../../Experiments/Refine/final-2026-11-27/REPORT.md)

## Publishing

Use only material on the example allowlist. Google FLEURS and CS-FLEURS have different terms. VoiceArena and CS-FLEURS belong in aggregate research reporting on the product site. Keep ZER, AMEND, WER, and latency in their respective methodologies. Carry the platform limitations with measurements and keep the user-test RC and the public download distinct.
