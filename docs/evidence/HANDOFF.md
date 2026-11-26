# Consolidated technical handoff for `rasc-web`

**Audience:** the agent building the editorial landing page + Notes article section. **Goal:** only claim what's backed; quote accurate numbers with scope; know what's verified vs open; reproduce. **Date:** 26 Nov 2026. **Rasc source:** `main @ 1cee496` (PRs `#101`–`#105` merged), plus Track 1 onboarding in open PR `#106` and Track 2 everyday efficiency on `perf/everyday-efficiency` (`0.1.16 build 22`); **published artifact:** `v0.1.15 build 21` (**not re-verified**).

## 1. Consolidated Quality & Efficiency Updates

- **PRs `#101`–`#105` (Merged to `main`):** Modifier-only global trigger (`#98`), Home multi-selection & transactional batch ops (`#99`), Standalone Voice Capture & Dictate with `alsoCopiesToClipboard = true` & `standaloneKeepsHistory = true` defaults (`#100`), Round 4 Voice evals & `HANDOFF.md` (`#104`), Unified shortcuts + tabbed Settings (`#105`).
- **PR `#106` (Track 1 — First Experience `#80`):** Interactive, adaptive onboarding covering live Scratchpad capture, `Esc` park -> Resume -> `Keep` (`⇧⌘K`), Voice vs Dictate separation, non-blocking model download, contextual Mic/AX permissions, and Settings `Welcome Guide…` replay (`docs/audits/2026-11-26-first-experience-onboarding.md`).
- **Track 2 — Everyday Efficiency (`perf/everyday-efficiency`):** Multi-sample & long-running Release evaluation + 5 grounded resource optimizations (`docs/performance/EVERYDAY-EFFICIENCY.md`, machine-readable web dataset at [docs/evidence/efficiency-web-data.json](efficiency-web-data.json)).

**No product-scope changes** (no folders/tags/agents/sync/cloud/telemetry; no model change; no architecture change for benchmarks). **No automated tests weakened.**

## 2. Product invariants (unchanged)

Capture instant + no AI; local-first SQLite; **no silent off-device**; external AI opt-in only (none added); **Refine explicit/stateless/conservative/reversible; original never destroyed before accept; isolated per note; no shared context; Capture/Keep/retrieval independent of Refine.** **No auto-Keep in shipping.** **No cloud.** **No telemetry.** See `AGENTS.md`, `docs/CURRENT-PRODUCT.md`, `docs/DATA-AND-PRIVACY.md`.

## 3. Voice Capture: actual quality + speed

### Model identity / provenance (exact)

- **Fluid Speech Pro**; `FluidAudio` `.fluidParakeetPro`; **0.63B**; NeMo/Parakeet-TDT-family **Core ML** pack; **revision `3b9d38a93d606f84011e5a0a669b7ea146375a22`**; **652,304,885 bytes**; per-file **SHA-256 + size** `VoiceModelManifest.json`; components `Encoder/Decoder/JointDecision/Preprocessor.mlmodelc` + `parakeet_vocab.json`(8192); **`AsrModels.loadLocalOnly`**; **no fine-tuning**; **open weights CC BY 4.0**; origin **HF `FluidVoice-Labs/fluid-speech-pro-coreml`** once via sandboxed XPC; **no network inference**; **Core ML CPU + Neural Engine**; **no streaming; no language hint; no vocab rescoring; verbatim; batch `AsrManager`; 16 kHz mono; 1 s pad; 120 ms tail; ≥0.07 s gate; no silence auto-stop.**
- **FluidAudio commit `386f7195670b77f2954c7ee143ec63fcb50b6c3b`.** App targets **macOS 14+**; Voice **macOS 26 + Apple silicon**; **Refine Foundation Models macOS 26 + Apple Intelligence**; `SystemLanguageModel.availability==available` re-verified. App **0.1.16 build 22**; **Xcode 26.2 / Swift 6 / macOS 26.5.1**.
- **No Apple cloud fallback. No Rasc re-training. Not comparing models.**

### Methodology (reproducible)

`Experiments/VoiceCapture/Round4/PROTOCOL.md`. **Hardware** Mac15,6 M3 Pro 11c 18 GB macOS 26.5.1. **Conditions** warm+cold; no network; no other load; no private audio; verbatim; no Refine; no hint; no streaming; Core ML cache not reset. **Corpus** **real human FLEURS** `test` en_us+pt_br **30+30** deterministic seed 20261126 2–18 s CC-BY-4.0 (raw preserved); **controlled perturbations** on EN+PT subset; **non-speech**; **Round3 comparable** AMI/CS-FLEURS/Tarsila; **Round1 synthetic TTS** not accuracy. **Scoring** pooled WER (NFC+casefold+dash/quote+punct-strip), CER, punct-sensitive WER, empty/non-speech/errors; **not** mixed metrics. **Latency** `ContinuousClock` app boundary + `VoiceModel.TranscriptionTiming`; p50/p95; n; cold/warm; **no extrapolation.** **Scripts** `prep_fleurs.py`, `perturb.py`, `score.py`, `VoiceEvalCommandLine.swift`. **Raw** `results/`. **No forced ranking.**

### Accuracy (verbatim; this round + comparable)

**Round4 FLEURS real human, actual app code, M3 Pro, warm (n=60):**
- pooled **WER 5.354%**, norm CER **2.054%** (raw CER **3.025%**), punct-sensitive WER **8.884%**, **no empty**; **EN 6.122% / PT-BR 4.581%** (punct-sensitive: EN 11.020% / PT-BR 6.695%).
- Perturbations vs `6.383%` subset base: **pauses/silence 5.674%** (−0.709 pts); **+15 dB SNR pink-filtered noise 8.511%** (+2.128 pts); **speaking-rate ± 7.447%** (+1.064 pts); **non-speech rejected**. (failed mis-scaled noise probe disclosed.)
- **Round3 comparable (not re-run): conversational EN meeting 13.00 / PT-BR conv 21.82 / read PT-EN mixed 8.89.** **Spontaneous multi-speaker code-switch not measured.**
- **Languages:** EN + PT-BR strong; **no hint**; **not claiming** other languages. **Proper names/numbers/technical** mostly retained but **not perfect**; **negation loss can occur**; **`<unk>`** can appear; **punctuation not always restored**; **not claiming ready-to-send.**
- **Semantic fidelity not independently human-adjudicated. Editing effort not measured.** **Verbatim ≠ Refine.**

### Latency (M3 Pro; not other hardware)

**Round4 actual app code, warm, n=60:** inference **p50 55.75 ms / p95 107.85 ms**; transcribe-total **p50 69.90 ms / p95 126.34 ms** (includes `audioPrepare` **12.89 ms p50**); **RTF p50 0.005 / p95 0.008**; init **0.03 ms**; cleanup **0.05 ms**; model-load/ready **0.01 ms**; **external WAV disk read `audioLoad` 41.36 ms p50 (not in total).** **Cold** `model.prepare()` after `release()`: **11.34 s** (`11,339.71 ms`) initial run (`fleurs-60`) vs **107.73 ms** warm-OS-cache follow-up (`perturbed-75`); **Round3 cold ~18–19.5 s worst; not re-measured Release.** **Round3 app end-to-end (comparable n=6 warm, excl mic/compositor/human): Finish→text ~188 ms, DB ~1.8 ms, Start→Keep ~1.59 s.** **Standalone delivery:** clipboard ~ms; AX insertion in unit tests + pending live desktop matrix; SQLite ~1.8 ms (Round3). **Physical-mic app-level p50/p95 not measured in Round4.** **Not claiming ms across hardware.**

### Standalone #100 complete behavior (verified scope)

- Scratchpad(default)/Clipboard/Insert; no focus steal; non-activating capsule; no Scratchpad in 2 standalone; **AX target mem + app-switch follows frontmost-at-finish fallback mem; no keystrokes; no activate; AX trust + fallback; `.noFocusedTextField`/`.insertionFailed`/`.noTargetApplication`/`.noAccessibilityPermission`; transient `.copied/.inserted/.copiedFallback` + VoiceOver; `.copiedFallback` kept; synchronous delivery + `flushForTermination` awaits standalone-history write.** **history off.** **No audio persisted; memory only; no network; sandbox.** **Recover `.persistence`; retry; cancel resets (#98).** **Not verified:** physical app-switch insertion; every app's AX; AS grant; VoiceOver; focus Spaces.

### Modifier #98 complete behavior

Clean key-up isolated; chord/diacritic/pointer/other-modifier/hold safe; reset; preserve chord; local+global; AX. **Not verified physical/a11y.**

### Multi-selection #99 complete behavior

As §1. **No claim native click; not perf-measured.**

## 4. Application performance & everyday efficiency (Updated — Release Measurements)

**Primary structured dataset for `rasc-web`:** [docs/evidence/efficiency-web-data.json](efficiency-web-data.json) (`schema_version: 1`, chart-ready `workday_timeseries`, `workday_phase_bars`, `operation_latencies_ms`, and `before_vs_after` deltas). Full prose report in [docs/performance/EVERYDAY-EFFICIENCY.md](../performance/EVERYDAY-EFFICIENCY.md) and summary in [docs/performance/APP-PERFORMANCE.md](../performance/APP-PERFORMANCE.md).

Key verified figures (Release `-O`, `Mac15,6` M3 Pro 18 GiB, macOS `26.5.1`, App Sandbox enabled, no user DBs):
- **Distinction on disk:** Release `.app` bundle **`40.5 MiB`** (`42,326,236` bytes); optional speech model **`652,304,885` bytes (`622.09 MiB`)** downloaded separately only on Voice opt-in.
- **Launch (`n=5` cold starts):** peaks `67.5%` CPU p50, settles to idle in **`0.51 s` p50** at **`22.44 MiB` `phys_footprint`** (`104.02 MiB` RSS).
- **Standby idle (`90 s` @ 1 Hz):**
  - Voice Off: **`22.44 MiB` `phys_footprint`** p50 (`104.09 MiB` RSS), **`0.0045%`** CPU, `0.011 pkg_wkup/s`, `0.01 mW` XNU CPU task power, `0` Rasc leaks.
  - Voice On (model prepared): **`47.59 MiB` `phys_footprint`** p50 (`117.11 MiB` RSS, `11.81 MiB` steady / `598.44 MiB` peak `neural_footprint`), **`0.0045%`** CPU, **`0.000 pkg_wkup/s`**, `0.08 mW` XNU CPU task power, `0` Rasc leaks.
  - Single-modifier `Option` idle (`45 s`): **`0.0014%`** CPU (`0.136 int_wkup/s`, down from `0.547%` / `10.89 int_wkup/s`).
- **8-phase workday endurance (`~4 min`, 225 notes, 35 FLEURS Voice clips, 6 Refine calls, sleep/wake, pressure, + 60 s cooldown):** peak `phys_footprint` **`136.38 MiB`** (down `−53.8%` from `294.99 MiB`), cumulative CPU `17.24 s` (`−74.3%`), XNU CPU energy `38.40 J` (`−81.4%`), settled cooldown **`92.44 MiB`** (`−51.2%`), Home open `24.47 ms p50` (`24.5×` faster), Home search `17.06 ms p50` (`9.6×` faster).
- **What still cannot be claimed:** full-SoC wall power / battery hours (`sudo powermetrics` unavailable; macOS unsupported in `xctrace Power Profiler`), 8 GiB / Intel / older macOS measurements, or competitor resource superiority.

## 5. Refine

`docs/CURRENT-PRODUCT`, `docs/REFINE-RELIABILITY`(policy), `docs/REFINE-V2`(historical), `docs/M3B-FOUNDATION-MODELS`(historical+API), `Evals/Refine/FROZEN`, `Evals/Refine/experiments/**`, `docs/performance`. **Apple Foundation Models on-device macOS26; no cloud; explicit; isolated; conservative; protected literals; language; uncertainty; revision; original; Undo; no auto; no streaming; no tools; no shared session; no contextWindowSize.** **Re-run this phase: tests + live smoke + FM available.** **Not** re-run M12B/M12C; **not** transcript+Refine WER; **not** Release latency; **not** "perfect." **Capture/Keep don't depend on Refine.**

## 6. Evidence audit

Full `docs/audits/2026-11-26-evidence-audit.md`. **Current vs previous vs comparable vs needs-reproduction** explicit. **Prior docs historical; generated outputs not current; previous-version audits; published vs source; Round1 synthetic; Round2; Round3 study≠shipping; Round4 app-code + Release idle; not app-level full.** **Not re-run wholesale.**

## 7. Competitive

`Experiments/Competitive/COMPETITIVE-EVALUATION.md`. **Sourced landscape; NOT a head-to-head.** Wispr Flow, Superwhisper, Aqua Voice, Typeless, Monologue(mono-1), Handy, VoiceInk, FluidVoice, Apple Dictation. **Key honest findings:** Rasc **verbatim**; competitors often **formatted**; **FluidVoice shares FluidAudio + Fluid Speech Pro**; **Monologue measured WildSpeech-Bench WER 7.22% + estimated edits (vendor, AI-editor, not users)**; **VoiceArena ZER/AMEND ≠ WER**; **Codictate adapter vs UI timing**; **Apple no WER**; **Wispr cloud**; **Superwhisper offline + own vocab**; **Handy MIT offline + clipboard restore known issue**; **VoiceInk GPL + FluidAudio + "99%" claim unmeasured**; **FluidVoice GPL + analytics + private FluidIntelligence**; **Rasc no analytics**. **No paired run; no forced ranking; where competitors win listed.** **Not claiming Rasc best.**

## 8. Claims we can make publicly (evidence)

(Strict; **scope + hardware + version**.)

1. **Local-first, no cloud, no telemetry, no account; recognition on-device; no audio persisted; sandbox; only one-time verified model download (separate XPC); no network inference.**
2. **Opt-in Voice Capture (`Fluid Speech Pro`):** verbatim; separate **`622.09 MiB` (`652,304,885 B`)** model; **`~40.5 MiB`** `.app`; **`22.4 MiB`** idle `phys_footprint` (`Voice Off`) / **`47.6 MiB`** (`Voice On`) with **`0.0045%` CPU** and **`~0` package idle wakeups** on M3 Pro macOS `26.5.1`; peak **`136.4 MiB`** across compressed workday workload (scope in `efficiency-web-data.json`).
3. **Verbatim WER 5.35% FLEURS EN+PT-BR pooled / EN 6.12% / PT 4.58% (punct-sensitive 8.88%; this hardware, this source version, read speech); comparable conversational Round3 13.0/21.8/8.9; not claiming vs competitors.**
4. **~56 ms inference p50 / ~70 ms transcribe p50 warm on M3 Pro (Round4, RTF p50 0.005); Round3 ~188 ms app finish→text.** (not other hardware; not physical-mic p95 Round4; cold model prepare `11.34 s` initial vs `108 ms` warm-OS-cache)
5. **Capture→Keep ~1.59 s warm scripted; SQLite ~1.8 ms; no auto-Keep.** (Round3; scope)
6. **Refine explicit on-device; no cloud; original safe; not perfect.** (scope)
7. **#98 modifier-only reliable unit-tested; chord-safe; preserves chord; AX.** (physical not claimed)
8. **#99 multi-select + batch; single-transaction discard + Undo; Markdown export incl images.** (native not claimed)
9. **#100 Scratchpad/Clipboard/Insert; AX insertion + clipboard fallback; focus; no network; optional local history off.** (verified in unit tests and builds; live TCC/external-app/VoiceOver checks pending)
10. **Reproducible scripts + raw results + provenance.** **Open source MIT.**

## 9. Claims we cannot yet substantiate

Anything in `docs/audits/2026-11-26-evidence-audit.md` §7. Specifically: **beat X**; **99%/perfect/no mistakes**; **ready-to-send**; **WER-compatible competitor numbers**; **mono-1/Wispr/etc as ours**; **spontaneous multi-speaker code-switch**; **semantic proof**; **editing-effort**; **energy**; **no leaks**; **other hardware**; **Intel Voice**; **macOS14 Voice**; **memory-constrained**; **native a11y/focus/Spaces/VoiceOver**; **physical keys**; **AS grant**; **app-switch insertion**; **mic+Sparkle continuity**; **Core ML cache**; **Release cold p95**; **signed/notarized current artifact**; **production**; **Refine perfect/Release latency/combined**; **no telemetry in competitors**; **no network in competitors**.

## 10. Real audio + transcription examples suitable for publication

`Experiments/VoiceCapture/Round4/examples/` (`examples.json` + WAVs). **Google FLEURS CC-BY-4.0; attribute.** Real human read speech. Reference vs Rasc verbatim; honest cases: clean; punctuation-only; "powers/powders"; `<unk>`; proper-name (`Sacks→Sachs`, `Lakkha Singh→Laki Hassing`, `chhappan bhog bhajan→Chapan de rogue Barrajan`). **No private audio.** Round3 has human meeting/conversation + mixed + semantic examples (`results/held-*`, per-clip). **Not screenshots of private.**

**Publication-safe audio excerpts:** FLEURS examples (CC-BY-4.0). **Not** synthetic TTS presented as real. **Round1 synthetic** labelled. 

## 11. Screenshots & demonstrations

- **This phase:** no new screenshots; Debug/Release builds, `Scripts/test-domain.py`, and Round 4 `--run-voice-evals` verified (`docs/audits/2026-11-26-phase1/NATIVE-VALIDATION.md`). **Prior native** `docs/audits/2026-11-13-visual/**`, `docs/validation/**`, Round3 `visual/**` + `capture-review-keep.mp4`, `docs/images/scratchpad.png`. **Round3 study app screenshots NOT shipping Rasc.** **Not re-verified; not focus/a11y proof.**
- **rasc-web agent:** use **current** shipping screenshots only with scope; **don't** reuse study-app as shipping; **don't** claim native-verified a11y. **Physical screenshots not produced this round.**

## 12. Limitations

See `Experiments/VoiceCapture/Round4/RESULTS.md` §Limitations, `docs/audits/2026-11-26-evidence-audit.md`, `Experiments/Competitive`. **Not prove better than others; not prove no mistakes; not prove energy; not prove other hardware; not prove native a11y; not prove production signed; no spontaneous code-switch; no human edit measurement; no cloud; no model change.**

## 13. Reproducibility

```sh
xcodebuild ... Debug build
# stage model docs/VOICE-CAPTURE.md
# FLEURS test parquet + ffmpeg + pyarrow
python3 .../prep_fleurs.py ... ; .../perturb.py ; 
Rasc.app/.../Rasc --run-voice-evals --corpus ... --output ...   # DEBUG; no note DB
python3 .../score.py ...
# tests: python3 Scripts/test-domain.py ; xcodebuild ... test ; Scripts/test-native.sh
# Release: xcodebuild -configuration Release ...
```
`run.json` records commit/machine/model/config. **No private data. `Evals/README` clearance.** **`docs/audits`, `docs/RELEASE` provenance.**
