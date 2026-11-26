# Competitive evaluation: contemporary dictation products vs Rasc

**Date:** 26 November 2026. **Rasc baseline:** current source `d9e88ef` + this phase's issues #98–#100; app 0.1.16 build 22; speech model Fluid Speech Pro revision `3b9d38a93d606f84011e5a0a669b7ea146375a22`, 652,304,885 bytes; FluidAudio commit `386f7195670b77f2954c7ee143ec63fcb50b6c3b`; verbatim, Core ML CPU + Neural Engine, 16 kHz mono, no language hint, no streaming, no vocabulary rescoring.

**Scope.** This is a *landscape and feasibility* study, not a head-to-head benchmark. No competitor was run on Rasc's audio in this round; see [Direct evaluation feasibility](#direct-evaluation-feasibility). Competitor numbers below are **vendor-published or third-party-published**, with source. They are **not** comparable to Rasc's verbatim WER unless the scorer and audio match; several competitors measure *edited output*, not verbatim transcription. See [Not comparable](#not-comparable-metric-incompatibility).

Every claim has a source. "Vendor" = company's own page. "Third-party" = independent benchmark. "Unverified" = not confirmed in this round.

## Executive summary

- **Rasc's recognition core is shared.** FluidVoice (a competitor, GPLv3) uses the same `altic-dev/FluidAudio` library and the same Fluid Speech Pro 0.63B model Rasc pins. Recognition-quality comparison between Rasc and FluidVoice at this round is therefore partly a product-layer comparison, not a model comparison.
- **Rasc is verbatim; most dictation competitors are formatted.** Wispr Flow, Superwhisper, Aqua Voice, Typeless, Monologue, FluidVoice, Handy (optional), VoiceInk (optional) can remove fillers, apply punctuation rules, reformat lists, or apply an LLM style. Rasc ships **no** filler removal or automatic formatting in Voice Capture; its optional **Refine** is a separate, explicit step. On "how many edits before send?" benchmarks (Voice Arena ZER/AMEND), a verbatim model will look worse by construction.
- **Rasc is strictly local-first with no network for recognition.** Wispr Flow and (for some modes) Aqua/Typeless/Monologue use cloud inference; Superwhisper and Handy/VoiceInk/FluidVoice offer local models. Rasc has no cloud path at all. Rasc's app sandbox has no outgoing network entitlement; the only network is the explicit one-time model download in a separate sandboxed XPC helper. Competitors that offer both must be scored on their **local** mode for a fair comparison.
- **Rasc does not yet have a measured editing-effort or end-to-end latency leaderboard.** We measured verbatim WER on real human speech (FLEURS) in this round (see [Voice Capture evaluation](../VoiceCapture/Round4/RESULTS.md)) and on the previous round's held-out conversational sets; we have **not** measured "time to ready-to-send draft" against any competitor on the same audio/hardware. We are not claiming to win on accuracy or speed.
- **Apple Dictation is the strongest free, built-in baseline on a Mac** and is available offline (macOS 26 has on-device speech; Apple Intelligence not strictly required for basic dictation). Apple publishes no comparable WER. Rasc already includes an Apple `SpeechTranscriber` comparison in its Round 3 study app (not in shipping Rasc). See [Apple Dictation](#apple-dictation).
- **Resource efficiency:** Rasc uses one ~622 MiB model, ~63 MB physical footprint idle, no auxiliary network process when not downloading, no telemetry. Competitors with LLM cleanup add a second model; cloud competitors push memory off-device. We have not measured competitors' memory. See [Resource efficiency](#resource-efficiency).

## Products

### Wispr Flow

- **Platforms / version:** macOS, Windows, iOS, Android, web; Monologue page shows comparisons; not version-pinned here. Vendor.
- **Pricing:** Free tier; Pro $8/month; Lifetime; Enterprise. (Superwhisper page notes Wispr comparison.) Vendor.
- **Privacy / offline:** Wispr Flow is a **cloud** dictation product (audio sent for transcription); a "works offline" toggle exists for *Superwhisper*, not Wispr. Vendor pages for Wispr emphasize accuracy, not on-device. Third-party Codictate explicitly classifies Wispr Flow as a **cloud product** ("No disk file: it is a cloud product", memory not observable). (Codictate benchmarks page.) Wispr has "On-device" claims in some marketing; **not verified** here for the exact audio path.
- **Model / architecture:** proprietary; not published. Vendor.
- **Published accuracy:** Third-party **Voice Arena Dictation Bench**: Wispr Flow **79.31% ZER / 0.40% AMEND** (US English, 759 clips, 5 LLM judges, macOS; rank 3). Third-party **Codictate** (Wispr Flow 1.6.8/1.6.774, M4 Max, FLEURS + LibriSpeech): pooled word accuracy ~93.0%; English clean 96.0%; noisy 93.3%. Vendor pricing pages do not publish WER. **Different metrics; not directly comparable to Rasc verbatim WER.**
- **Published latency:** Codictate reports Wispr Flow response time ~**88 ms/s** wait-per-audio-second, median clip ~**401 ms**, p90 ~**653 ms** (English clean); **not comparable** to Codictate's own adapter-boundary timing for local models; Codictate states the two are timed differently. Wispr "streams while you speak." Wispr Flow is measured "over the network."
- **Feature set:** global shortcut, **push-to-talk**, **modifier-only trigger** (`⌥ + space` default in Superwhisper; Wispr has custom shortcuts), **direct insertion + clipboard**, **100+ languages + translation**, **custom vocabulary**, formatting modes, **notes/meetings**, MCP/API. **Auto-Keep / auto-send** is *not* something Rasc offers and, per Rasc's own Round 3 evidence, should not be added. Vendor.
- **Direct evaluation feasibility:** not feasible without a paid account + cloud + same audio; closed-source. Research-only comparison possible via published benchmarks. See below.

### Superwhisper

- **Platforms / version:** macOS, Windows, iOS, Android; `superwhisper.com`. Not version-pinned. Vendor.
- **Pricing:** Free (Whisper models, custom prompt control, 100+ languages, unlimited, clipboard integration, **works offline**, push-to-talk, custom shortcuts); Pro $8/month; Lifetime; Enterprise. Vendor.
- **Privacy / offline:** **"Works offline."** Optional **own AI API keys** + cloud/local AI models for *formatting*; recognition can be local Whisper. Local offline mode + cloud modes coexist. Vendor.
- **Model / architecture:** **Whisper** (Large etc.) for recognition; optional LLM (GPT-5, Claude, Llama, Grok, Gemini, Ministral, custom) for formatting; "Super Mode". Vendor. Recognition model identity in local mode not fully pinned.
- **Published accuracy:** **Voice Arena Dictation Bench:** Superwhisper **59.82% ZER / 1.45% AMEND** (rank 16). **Not verbatim WER; not comparable.** No vendor WER found.
- **Published latency:** none comparable found in this round. Vendor marketing claims "instantly"; **not verified**.
- **Feature set:** predefined + custom **modes** (formatting), **vocabulary**, **push-to-talk**, custom shortcuts, **clipboard auto-paste**, 100+ languages + translation, **per-app activation**, meeting notes, file transcription, **works offline**. Vendor.
- **Direct evaluation feasibility:** recognition is local Whisper; could run its bundled model on the same audio *if* extracted, but the full product is closed-source and formatting requires accounts. Research-only for the product; engine-level comparison possible via Whisper. See below.

### Aqua Voice

- **Platforms / version:** macOS, Windows; `aquavoice.com`. Not version-pinned. Vendor.
- **Pricing:** not confirmed in this round. **Unverified.**
- **Privacy / offline:** marketed as accurate dictation; cloud vs on-device split **not confirmed**. The Voice Arena benchmark page lists "Aqua Voice" without disclosing local vs cloud. **Unverified.**
- **Model / architecture:** proprietary; **"Aqua Voice" model** per Voice Arena; not published.
- **Published accuracy:** **Voice Arena Dictation Bench:** Aqua Voice **80.50% ZER / 0.54% AMEND** (rank 2). **Not verbatim WER.**
- **Published latency:** not comparable figure found. **Unverified.**
- **Feature set:** **command mode**, **context-aware**, **custom vocabulary** (per Voice Arena "Domain" filters and product marketing); **not verified** in detail here.
- **Direct evaluation feasibility:** closed-source; research-only.

### Typeless

- **Platforms / version:** macOS, Windows, iOS; `typeless.app`. Not version-pinned. Vendor.
- **Pricing:** not confirmed in this round. **Unverified.**
- **Privacy / offline:** **not confirmed.** Monologue publishes a "Monologue vs Typeless" comparison but the claims are vendor. **Unverified.**
- **Model / architecture:** proprietary; **not published.**
- **Published accuracy / latency:** no comparable figure found. **Unverified.**
- **Feature set:** voice-to-text in any app; formatting; **not verified** in detail.
- **Direct evaluation feasibility:** closed-source; research-only.

### Monologue (monologue.to)

- **Platforms / version:** macOS, iOS; **Monologue**; `mono-1` in-house dictation model; app version not pinned; model card "Introducing mono-1" 23 Sep 2026. Vendor.
- **Pricing:** Free / Pro $12/mo (Pro yearly $144, Black-Friday first-year $100 shown 2026-11-26); Enterprise API limited. Vendor.
- **Privacy / offline:** Monologue "local-first"; mono-1 **runs on your Mac** in the app; **enterprise API** uses cloud. Recognition in app modeled as local; **offline capability not fully verified**. **Needs reproduction.** Vendor.
- **Model / architecture:** **mono-1**, in-house, ~6 months development; built on/formats on top of recognition; **base recognition model not disclosed**. Vendor. (Distinguish *recognition* from *formatting*; mono-1 is positioned as a dictation model producing finished text.)
- **Published accuracy:** **WildSpeech-Bench** (1,100 English clips: 1,000 synthetic voice-cloned + 100 real prosody; background noise, overlap, loudness, pauses, stuttering): mono-1 **WER 7.22%**, second-lowest; OpenAI GPT-4o Transcribe 6.68%; ~**55% fewer estimated edits** vs previous API pipeline (13.64→6.21 per 100 words, blinded AI editor, **not actual user edits**). Vendor. **WildSpeech-Bench + WER-only + edit-estimate; not comparable to Rasc verbatim FLEURS WER.** Timings "indicative."
- **Published latency:** mono-1 median raw-transcription response **109 ms** (tied); ~**3×** faster median API response vs previous pipeline. **Vendor, API-level, not app end-to-end.**
- **Feature set:** dictation, notes, MCP/API, formatting, self-correction, vocabulary + screen context, "commands". Vendor. Examples in marketing are **"illustrative ... not recorded outputs."**
- **Direct evaluation feasibility:** app is closed-source; **mono-1 API** is "limited approved users." Not feasible without account. Research-only.

### Handy (open source)

- **Platforms / version:** macOS, Windows, Linux; Tauri; **Handy 0.8.1** referenced; `cjpais/Handy`, **MIT**. Vendor (GitHub).
- **Pricing:** **free**. Vendor.
- **Privacy / offline:** **"works completely offline"; "your voice stays on your computer"; no cloud.** Vendor. Requires microphone + accessibility permissions. **No telemetry claimed** (not independently verified).
- **Model / architecture:** **Whisper** (Small/Medium/Turbo/Large) + **Parakeet V3** (CPU, auto language); **Silero VAD**; **Whisper.cpp / ggml**; optional **LLM post-processing**; **custom models**; **dictionary**; **transcription hook**. Vendor. Model sizes listed (~487 MB Small, 1.6 GB Turbo, 1.1 GB Large, 731 MB Parakeet GGUF). **Not the same model as Rasc.**
- **Published accuracy / latency:** no comparable figure in README. **Unverified.**
- **Feature set:** **hold or toggle** recording; **hold-only/toggle-only**; **paste directly**; **clipboard restore** (known issue + Reliable Paste beta); **history**; **CLI flags**; **transcription hook**; **fn/Globe not on third-party keyboards** (documented limitation). Vendor.
- **Direct evaluation feasibility:** **highest among competitors.** Open source + local. Could run its Whisper/Parakeet model on the same audio, or build Handy and use `--toggle-transcription`. We did not in this round. See below.

### VoiceInk (open source)

- **Platforms / version:** macOS 15+; `Beingpax/VoiceInk`, **GPLv3**; not version-pinned; not accepting PRs. Vendor.
- **Pricing:** open source; **paid license** for automatic updates/priority; free trial. Vendor.
- **Privacy / offline:** **"100% offline processing; data never leaves your device."** Vendor. **No account for core.**
- **Model / architecture:** **whisper.cpp**; **FluidAudio Parakeet** (same library as Rasc); **TranscribeCpp**; **SenseVoice Small**; **local GGUF**. Vendor. **Uses `FluidAudio`.**
- **Published accuracy:** README claims **"99% accuracy"**; **not a measured WER; not comparable.**
- **Published latency:** "almost instantly"; **not measured.**
- **Feature set:** modes, **app detection**, **context-aware**, **personal dictionary + replacements**, **global shortcuts incl push-to-talk**, **AI assistant**, **screen context**, **power mode**. Vendor.
- **Direct evaluation feasibility:** open source; could build. Recognition engine overlaps Rasc's FluidAudio + Whisper. **Not run in this round.**

### FluidVoice (open source)

- **Platforms / version:** macOS 15+; **FluidVoice 1.6.13**; `altic-dev/FluidVoice`, **GPLv3**; **Fluid Speech Pro / Mini / Pico** + Parakeet + Qwen3 ASR + Whisper + Apple Speech + Nemotron + Cohere; optional cloud AI. Vendor. (Note: a lookalike `fluidvoice.org` is flagged unaffiliated.)
- **Pricing:** **free + open source**; sponsors; optional cloud keys. Vendor.
- **Privacy / offline:** **local-first; "voice, audio, transcribed text never leave your machine unless you opt in to a cloud AI provider."** Vendor. **But:** optional **anonymous analytics** (daily activity + feature/model usage, default on, disable-able; no voice/text/clipboard/paths) + **Fluid Intelligence private runtime**. Vendor. **Rasc has no analytics.**
- **Model / architecture:** **Fluid Speech Pro** = **0.63B open weights CC BY 4.0**, **same `altic-dev/FluidAudio` library + same 622 MiB model Rasc pins**; optional **Fluid Intelligence** cleanup (Ripple/Splash, private); **Edit 1.1**; **Qwen3**. Vendor. **On the Open ASR Leaderboard, Fluid Speech Pro "ranked first among open models under 1B parameters."** (Vendor citing leaderboard; `fluid_speech` folder exists in `huggingface/open_asr_leaderboard`.) **Not independently re-run by us.**
- **Published accuracy:** no own WER in README; defers to Open ASR Leaderboard. **Vendor-claim + third-party leaderboard reference.**
- **Published latency:** "Fastest"; **not measured** in README. **Unverified.**
- **Feature set:** **Smart Typing (AX direct insertion)**, **clipboard**, **global hotkey**, **push-to-talk**, **modifier shortcuts (left/right)**, **hold-Space-to-mute**, **non-activating overlay**, **menu bar**, **custom dictionary**, **per-app config**, **command mode**, **edit mode**, **file transcription**, **audio history**, **FluidMeet**, **partials**. Vendor. **Feature-rich; Rasc is deliberately smaller.**
- **Direct evaluation feasibility:** **highest.** Same engine + same model + open source. **We should run a paired comparison.** See below. (Rasc and FluidVoice both require Accessibility for typing.)

### Apple Dictation

- **Platforms / version:** macOS built-in; **macOS 26.5.1** here; `com.apple.Dictation`. Not separately versioned. Apple.
- **Pricing:** **free.** Apple.
- **Privacy / offline:** **on-device** option; **offline** for dictation once language assets downloaded; **no audio sent to Apple in on-device mode**; Apple Intelligence not strictly required for basic dictation. **macOS 26 specifics need reproduction on this build.** Apple + Round 3 (Rasc's study app measured `Apple SpeechTranscriber`, not the literal Dictation feature).
- **Model / architecture:** **Apple SpeechTranscriber / SpeechAnalyzer** (macOS 26); `SFSpeechRecognizer`; on-device + server modes. Apple. **`SpeechTranscriber` ≠ literal "Dictation" keystroke feature.**
- **Published accuracy:** Apple publishes no comparable WER. Round 3 (Rasc study app, Apple `SpeechTranscriber`, EN + PT locale, 168 clips): **18.87% EN meeting / 25.55% PT conversation / 24.23% mixed** vs Fluid 13.00/21.82/8.89. **Same harness, comparable.** Third-party Voice Arena: Apple Dictation **34.52% ZER** (rank 19) — **not comparable.**
- **Published latency:** Apple `SpeechTranscriber` in Round 3 ~**224 ms** warm finish-to-text (study app) vs Fluid ~188 ms. **Comparable harness.**
- **Feature set:** system-wide, **offline**, **fn/Globe**, **custom vocabulary** (Apple "Vocabulary"), **automatic punctuation**, **continuous**, **multi-language**. Apple.
- **Direct evaluation feasibility:** **on-device `SpeechTranscriber` can be run on the same audio headlessly** (Round 3 did exactly this in Rasc's study app). The literal Dictation keystroke feature is harder to capture. Rasc already has comparable numbers.

## Not comparable: metric incompatibility

Do **not** mix these. They measure different things:

| Metric | What it counts | Source examples |
|---|---|---|
| **Verbatim WER / CER** (punctuation-insensitive) | word edits vs a verbatim reference; nothing removed | **Rasc** (this round, FLEURS; Round 3); Open ASR Leaderboard; Monologue WildSpeech-Bench WER; Codictate "word accuracy" |
| **WER with punctuation** | punctuation tokens counted | Rasc `werPunctuationSensitivePercent` (this round); note most others strip punctuation |
| **Zero Edit Rate (ZER)** | % clips needing no edit before send; penalizes fillers; consensus of 5 LLM judges | Voice Arena Dictation Bench |
| **AMEND** | edit distance of final sent draft vs raw; scored by an LLM | Voice Arena Dictation Bench |
| **Estimated edits / 100 words** | blinded AI editor count, **not actual user edits** | Monologue mono-1 |
| **"Word accuracy"** | `1 - WER` under a specific normalizer | Codictate |
| **Latency definitions differ** | adapter-boundary vs UI-observed paste vs streaming vs API | Codictate (states two timings differ); Monologue (API); Rasc (app boundary + model inner split) |

**Conclusion:** A verbatim, no-formatting tool like Rasc cannot be ranked on ZER/AMEND without a separate formatting step. Comparing Rasc WER 5.35% (FLEURS) to Wispr ZER 79.31% would be misleading.

## Resource efficiency

Rasc (this round, Release, M3 Pro 18 GB, macOS 26.5.1; verified, restored DB backup):

- **App bundle:** 39 MB (Release, unsigned). Speech model **on disk separate:** 652,304,885 bytes (~622 MiB).
- **Physical footprint idle:** **63 MB** (`footprint`). **RSS ~746 MB** at 5 s incl. file-backed mappings (RSS ≠ footprint). CPU spikes at startup, drops when idle. (Round 3 + M13A give richer numbers.)
- **No telemetry, no account, no cloud, no auxiliary persistent process.** Only a **sandboxed XPC downloader**, used solely for the one-time model download, then invalidated.
- **Voice model memory:** ~25 MB after load → peak ~59–77 MB → released on idle/sleep/memory-pressure/disable; **re-prepared proactively.** (docs + Round 3.) Model on disk 622 MiB separate from app.
- **No competitor memory measured.** Voice Arena classifies Wispr Flow memory as unobservable (cloud). Codictate measures local model RAM (separate product). FluidVoice/FluidAudio shared engine suggests similar model size but **not measured here.**

## Direct evaluation feasibility

**Recommended: methodologically defensible paired evaluation.** Not "number of competitors." Use a fixed corpus + harness + hardware + conditions, verbatim scoring, same normalizer, and report Rasc honestly.

### Tier 1: defensible today, on this Mac, same audio

| Target | Why feasible | Caveat |
|---|---|---|
| **FluidVoice** (GPLv3, macOS) | same FluidAudio + Fluid Speech Pro; file transcription; local; **same engine + model → isolates product layer** | needs macOS 15+, Accessibility; not yet run; formatting (Fluid Intelligence) would change target — test verbatim mode |
| **Apple Dictation / SpeechTranscriber** (macOS) | on-device; `SpeechTranscriber` headless on same WAV; Rasc Round 3 already did | `SpeechTranscriber` ≠ literal Dictation keystroke; Apple no WER |
| **Open ASR Leaderboard `fluid_speech` / `nvidia/parakeet-tdt-0.6b-v3`** (model-level) | public reproducible; same scorer; **not same runtime as Rasc's Core ML build** | Linux NVIDIA H200, not macOS; **model-level not app-level**; not re-run |

### Tier 2: open-source, feasible with effort

| Target | Why | Caveat |
|---|---|---|
| **Handy** (MIT) | offline; Whisper/Parakeet; CLI; paste; can build | **different model** (Whisper/Parakeet-v3 GGUF vs Fluid Speech Pro Core ML); not same engine |
| **VoiceInk** (GPLv3) | offline; FluidAudio + Whisper; Swift macOS | formatting/context changes output; **"99%" claim not measured**; not run |
| **Whisper Large V3 (Turbo)** via whisper.cpp / MLX | open model; Codictate + Open ASR Leaderboard already benchmark it on FLEURS | **not Rasc's model**; engine differs; **model-level only** |

### Tier 3: not feasible without a paid account + cloud

Wispr Flow, Superwhisper (product incl. formatting; local Whisper extractable but product not), Aqua Voice, Typeless, Monologue (mono-1 API limited; app closed). **Research-only.** We will not fabricate results. We cite their **own published** numbers with metric caveats.

### Proposed paired protocol (not executed this round)

1. **Same corpus:** Round4 FLEURS-EN-30 + FLEURS-PT-30 + Round3 held-out (AMI 64 + Tarsila 64 + CS-FLEURS 40) + a small technical/names/numbers set (label synthetic if TTS).
2. **Same hardware:** M3 Pro 18 GB, macOS 26.5.1, fresh app identity, no other load.
3. **Same scorer:** Rasc `scorer`/Round4 `score.py` (punctuation-insensitive WER + punctuation-sensitive + CER), verbatim target; **and** a separate "ready-to-send" human/auto edit metric *labeled as such*.
4. **Same conditions:** warm + cold, no network for local modes, noise/speed/silence variants, EN + PT-BR + code-switch.
5. **Verbatim mode:** disable formatting/LLM cleanup in every competitor; record exact version + config.
6. **Report:** WER + semantic + latency p50/p95 + memory + disk + privacy + setup. **No forced ranking; report where each wins.**

## Where competitors likely outperform Rasc (evidence status)

| Area | Likely | Evidence |
|---|---|---|
| **Ready-to-send output** | Wispr, Superwhisper, Aqua, Typeless, Monologue, FluidVoice, Handy, VoiceInk | They format/remove fillers/self-correct; Rasc verbatim + optional Refine. **Voice Arena ZER** shows formatted products higher; Rasc not measured on ZER. |
| **Code-switching / language coverage** | Wispr (100+ + translate), Superwhisper (100+), FluidVoice (Whisper 99 + 25 + Qwen3 30), Apple | Rasc targets EN + PT-BR well (Round3 PT-EN mixed 8.89%); **not claiming** broader. |
| **Custom vocabulary / proper names** | Superwhisper, VoiceInk, Handy, FluidVoice, Monologue | Rasc **no** custom vocabulary; Round3 notes proper-name errors (e.g. "Supabase", "Jakarta"). |
| **Streaming / partials / live preview** | Wispr, Monologue, FluidVoice, Handy(VAD), Nemotron | Rasc **batch**, no partials. |
| **Latency on long inputs** | streaming products | Rasc batch; RTF ~0.005 on FLEURS short; **not measured long**. |
| **Offline + no analytics + no model sharing** | Rasc vs cloud | **Rasc strength**; FluidVoice also local but adds analytics; Handy/VoiceInk local. |
| **Simplicity / scope** | **Rasc** | Rasc has no modes/folders/tags/LLM; competitors add. |

## Rasc claims supported by checked-in evidence

(Strict; see `docs/audits/`.)

- Voice Capture is **opt-in, on-device, verbatim, no network inference, audio in memory only, no cloud fallback.**
- **Fluid Speech Pro** revision `3b9d38a…`, 652,304,885 bytes, SHA-256-verified, Core ML CPU+ANE, batch, 16 kHz, no hint, no streaming/vocab rescoring.
- **Verbatim WER** on real human speech (this round): FLEURS-EN 30 + PT-BR 30, pooled **5.35%** (EN 6.12 / PT 4.58); Round3 held-out conversational **13.0 EN / 21.8 PT / 8.9 mixed**; **+silence +5.7%**; **−15 dB noise +8.5%**; **speaking-rate ± ~1%**; non-speech rejected; (results in Round4 + Round3).
- **Latency** (this round, app code, M3 Pro, warm): inference p50 ~75 ms, transcribe-total p50 ~91 ms, RTF ~0.006; model prepare warm ~0.02 ms; **cold** app-level + previous rounds (Round3 ~19.5 s cold reload worst; probe 18 s first; 201 ms warm; **needs reproduction on Release**).
- **Standalone Voice Capture (#100):** Clipboard + Insert-at-cursor; AX `AXSelectedText` insertion verified natively (TextEdit, accents); clipboard fallback; no focus steal; no Scratchpad; optional local history off by default; sandbox/privacy unchanged.
- **Modifier-only shortcut (#98):** clean-tap recognizer unit-tested; chord-safe; Accessibility requirement surfaced; local + global. **Global trigger not verified without Accessibility grant in this environment.**
- **Home multi-selection (#99):** domain + persistence tests; **native click verification not claimed.**

## Claims Rasc cannot yet substantiate

- "Better than X" on accuracy/latency/editing-effort vs any competitor (no paired run).
- WER on **spontaneous code-switching** from a representative **multi-speaker** group (CS-FLEURS is read, one speaker per pair in Round3).
- **Semantic fidelity** by independent human adjudication.
- **Editing effort** (real human time/edits).
- **Energy** (Joules/thermal) — `powermetrics` not permitted; Power Profiler unavailable (Round3).
- **Lower-memory Mac** performance; **Intel**; **macOS 14** for Voice Capture (requires macOS 26 + Apple silicon).
- Core ML **cache** determinism across machines/updates (documented risk, Round3).
- Microphone-permission **continuity across Sparkle updates** (release gate; needs stable signing).
- Native **VoiceOver / Full Keyboard Access / Spaces / Stage Manager / multiple monitors / Bluetooth** on physical hardware.
- Competitor **memory / energy / private audio** behavior.

## References (accessed 26 Nov 2026)

- Voice Arena Dictation Bench: https://voicearena.com/dictation-bench (+ methodology PDF linked there; ZER/AMEND; 759 clips; US English; macOS; 14 tools; note filler penalty + Function open-harness footnote).
- Codictate benchmarks: https://codictate.app/benchmarks ("How we measure"; FLEURS/LibriSpeech; M4 Max; timing-difference note; Wispr Flow 1.6.8/1.6.774; Parakeet TDT 0.6B v3; Apache 2.0).
- Open ASR Leaderboard: https://github.com/huggingface/open_asr_leaderboard (datasets FLEURS/MCV/MLS + Earnings/CORAAL; HF Jobs H200; public normalizer; `fluid_speech` + `nemo_asr` folders; citation `srivastav2025openasrleaderboardreproducible`).
- Monologue "Introducing mono-1": https://www.monologue.to/blog/introducing-mono-1 (2026-09-23; WildSpeech-Bench; WER 7.22%; 109 ms; ~55% fewer estimated edits; illustrative examples; enterprise API limited; pricing shown).
- Wispr Flow: https://wisprflow.ai ; Superwhisper: https://superwhisper.com ; Aqua Voice: https://aquavoice.com ; Typeless: https://www.typeless.app (pages fetched; claims as vendor).
- Handy: https://github.com/cjpais/Handy (MIT; 0.8.1 ref; Whisper+Parakeet+Silero; hold/toggle; paste+clipboard restore; transcription hook; CLI; known issues).
- VoiceInk: https://github.com/Beingpax/VoiceInk (GPLv3; whisper.cpp+FluidAudio+TranscribeCpp+SenseVoice; macOS 15+; "99%" claim).
- FluidVoice: https://github.com/altic-dev/FluidVoice + https://altic.dev/fluid (GPLv3; 1.6.13; Fluid Speech Pro 0.63B CC-BY-4.0; FluidAudio; same model; analytics note; `fluidvoice.org` unaffiliated warning).
- Apple Dictation / SpeechTranscriber: Apple platform docs + Rasc Round3 `Apple` rows.
- Rasc Round3: `Experiments/VoiceCapture/Round3/README.md`, `VALIDATION.md`, `results/held-summary.json`.
- Rasc Round4 (this phase): `Experiments/VoiceCapture/Round4/RESULTS.md`.

## Limitations

- Vendor marketing not independently reproduced. "Unverified" means not confirmed this round, not false.
- Web pages can change; accessed date recorded. Pricing/version from public pages; not contractually verified.
- No competitor was installed/run on Rasc's audio in this round; Tier-1 feasibility is an assessment, not a completed benchmark.
- No paid accounts, no cloud keys, no private audio. No claim about enterprise SOC2 etc.
