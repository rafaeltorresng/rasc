# Rasc Voice Capture · production-shaped study

[Final 0.3.1 hardening pass and signed validation](FINAL-PASS.md)

**Recommended default: Fluid Speech Pro, verbatim, Core ML. Go for personal evaluation. Production remains a No-Go.** This round builds on [Round 1](../README.md) and [Round 2](../Round2/README.md) at Rasc main `250f1c1c82534bc69daad056fced69c083d298d7`. The shipping target, dependencies, entitlements, feeds, and user database stay separate.

[Open the signed study app](<Study/Build/Rasc Voice Capture.app>) · [Personal test protocol](PERSONAL-TEST.md) · [Performance and validation](VALIDATION.md) · [Production integration and gates](INTEGRATION.md) · [Reproduce this round](REPRODUCE.md)

## Recognition recommendation

The new fixed holdout gives Fluid a consistent directional lead. Fluid leads on English meeting speech and the held human-read mixed set. The new Portuguese conversational set also favors it, while Round 2’s smaller holdout favored Ultra. Both are valuable comparators. Use Apple as the native control, especially when testing setup and short-thought ergonomics. The clip-resampled intervals below include parity for the two portable engines. The result supports a default for this study and a specific production candidate, with open reliability gates.

| Held-out audio | Clips | Fluid Speech Pro | Parakeet Ultra | Apple SpeechTranscriber |
|---|---:|---:|---:|---:|
| Brazilian Portuguese conversation (Tarsila NURC-SP) | 64 | **21.82%** | 22.85% | 25.55% |
| English meeting conversation (AMI IHM) | 64 | **13.00%** | 16.14% | 18.87% |
| Read Portuguese–English switching (CS-FLEURS) | 40 | **8.89%** | 10.05% | 24.23% |

Entries are pooled WER; accents are retained and punctuation is ignored. The new Tarsila row ranges are disjoint from both prior sets. Session and speaker IDs are preserved where available. The mixed set is read by one real speaker, so it demonstrates language switching under a known acoustic condition. Spontaneous bilingual thought capture still needs a representative group of speakers. Bootstrap intervals for Fluid minus Ultra WER are −3.51 to +1.54 points in PT, −9.33 to +1.13 in EN, and −2.91 to +0.64 in mixed. These resample clips and do not account for all speaker/session correlation. All three completed 168 attempts. Fluid returned four empty PT clips, Ultra none and Apple two. The short, naturally fragmentary speech is a meaningful part of this result. [Held-out summary](results/held-summary.json) · [Per-clip counts and durations](results/held-clip-metrics.csv) · [Input IDs and hashes](results/held-inputs.json) · [Tarsila paper](https://www.isca-archive.org/interspeech_2026/leal26_interspeech.html) · [AMI](https://groups.inf.ed.ac.uk/ami/corpus/) · [CS-FLEURS paper](https://www.isca-archive.org/interspeech_2025/yan25c_interspeech.html)

The main comparison uses pinned verbatim model packs, the same 16 kHz audio, no language hints supplied to portable engines, and English or Portuguese as the corresponding Apple locale. Core ML receives trailing zeros for valid frames shorter than one second, matching the app. A preliminary probe hit the pack’s one-second minimum on 27 clips. The completed benchmark uses the same short-input adapter as the app. No transcript was rewritten. No ranking was tuned on the holdout. [Scorer](Bench/score-held.py) · [Adapter](Study/Recognition.swift) · [Model lock](../Round2/results/model-lock.json)

### Semantic findings

- **Negation over word error.** AMI clip `en-r3-00629` is annotated as a warning against everyone jumping at once. All three engines rendered something like an affirmative future action, losing the warning. Some clipped turns and overlaps in the meeting set also lead to omissions and present a different challenge from a single person speaking privately. This is direct evidence against default automatic Keep.
- **Technical switching and proper names.** In the Round 2 worker/deploy fixture, both portable engines preserved the English terms and uncertainty, with an extra article. Fixed-PT Apple distorted the terms and damaged the negation. In the new mixed set, both portable engines were more reliable at retaining embedded English words. On the mixed Jakarta warning sample (`por_1835_CC`), all had issues with the technical agency phrase. A name and a correctly kept negative clause can coexist with an error that matters.
- **Numbers and corrections.** On the mixed bridge sample (`por_1883_CC`), both portable engines kept the numerals, month and years. Apple correctly represented the numbers in words but changed a nearby noun. In the earlier short test with an explicit change from 180 to 80, both portable engines preserved the values yet corrupted “timeout.” All three needed correction for “Supabase.” Automatic writing could miss an error that looks fluent on skim. [Round 2 controlled outputs](../Round2/results/synthetic-results.jsonl)
- **Uncertainty and fragments.** All three retained uncertainty in the AMI sample `en-r3-00036`. In `en-r3-01634` all retained the meaning, with varied handling of a filler and one inserted word. The individual clip scores and boundary counts show why plain WER is an incomplete proxy. Timing per meaningful human edit and personal review load are still unmeasured.

Fluid’s NeMo/ONNX cleaning modes would change the evaluation target. Its Core ML verbatim pack and the current TDT batch path provide no app-level beam or language tuning knob. The pinned FluidAudio library has a separate CTC-based vocabulary rescorer that needs another model and can substitute words after recognition. The optional streaming/vocabulary paths have debug calls that can include text or terms. The study uses only the local batch path and no names from notes or contacts. Apple’s earlier fixed small-hint trial was limited and did not reliably fix switching. A future vocabulary evaluation would need independent prompts and explicit opt-in to added terms. [Fluid model variants](https://huggingface.co/FluidVoice-Labs/fluid-speech-pro-coreml) · [Pinned FluidAudio source](https://github.com/altic-dev/FluidAudio/tree/386f7195670b77f2954c7ee143ec63fcb50b6c3b) · [Apple hint probe](../results/apple-fixture-hints.jsonl)

## What changed in the app

The floating surface acknowledges the shortcut immediately and shows **Starting microphone** until the tap sends its first frame. **Listening** uses the input’s RMS, and **Finishing recording** keeps the mic cue visible for the bounded 120 ms tail. Speech can pause naturally. Toggle acts at key-down, and hold ends on key-up. Repeats are debounced without global key monitoring. The study defaults to toggle because it reduces sustained effort and naturally supports long pauses. Both modes remain accessible for comparison.

Review shows an editable body and an explicit original transcript. Automatic Keep shows a small, non-activating **Kept** receipt with **Open** and **Undo**. Only committed text earns copper. Opening review or the kept thought intentionally brings up the study. The isolated database stores normal Kept thoughts and a separate scratch. Written recognition and review edits can be recovered on relaunch. Pending audio is held only in memory. The optional evaluation files require local opt-in and can be removed.

The study follows the Rasc palette, native text and window conventions. It provides system, light and dark appearance and preset themes. The compact capsule uses no idle animation. The meter draws only from live frame energy. [Light review](visual/04-review-light.png) · [Dark listening](visual/07-listening-dark.png) · [Dark receipt](visual/08-kept-dark.png) · [Native interaction recording](visual/capture-review-keep.mp4)

## Current decision

The candidate advances to a personal trial with review-first. The prototype makes ready, listening, partial recovery and durable Keep legible. Release is gated by meaning-changing failures on real speech, cold preparation and cache behavior on more machines, native accessibility and shortcut ergonomics, and microphone grant continuity for Rasc’s actual distribution. [Detailed validation](VALIDATION.md) · [Integration and clear release gates](INTEGRATION.md)
