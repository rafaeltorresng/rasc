# Definitive Technical & Evidence Handoff for `rasc-web`

**Audience:** maintainers and agents building `rasc-web` (product landing page, Notes/engineering deep-dives, interactive examples, benchmarks, and visual showcases).
**Date:** 2026-11-27
**Verified Source Commit:** `main @ 30c5c14` (PRs `#101`–`#113` merged; `0.1.16 build 22`, macOS deployment target `14.0`).
**Candidate Artifact Verified:** `build/updater-rc/0.1.16-final-rc/Rasc-0.1.16-updater.dmg` (`0.1.16 build 22`, ad-hoc signed with `Has Library Load Constraints`, unnotarized — Developer ID/notarization remains deferred; `v0.1.15 build 21` remains the latest tagged external DMG artifact).
**Machine-Readable Evidence Datasets (generate charts/tables strictly from these JSONs):**
- Efficiency, `8h` soak, `8.50h` standby, `5k` scale, streaming `mono16k()`, and `0.1.16-final-rc` data: [`docs/evidence/efficiency-web-data.json`](efficiency-web-data.json)
- Paired Voice Competitive & Latency data: [`docs/evidence/voice-competitive-web-data.json`](voice-competitive-web-data.json)
- On-device Refine (`Apple Foundation Models`) evaluation data: [`docs/evidence/refine-web-data.json`](refine-web-data.json)
- Visually audited Light & Dark PNGs (`38` clean synthetic views): [`docs/evidence/screenshots/manifest.json`](screenshots/manifest.json)
- Publishable CC BY 4.0 audio clips, transcripts & synthetic/CC-BY Refine pairs: [`docs/evidence/examples/ATTRIBUTION.md`](examples/ATTRIBUTION.md)

---

## 1. Product Positioning & Non-Negotiable Invariants

Rasc is a native macOS floating scratchpad for unfinished thoughts: **Capture → Refine (optional) → Keep → back to work**.

1. **Local-first & zero account:** Notes live exclusively in local SQLite (`GRDB` WAL + `FTS5`). Opening, editing, searching, backing up, and exporting never require an account, network connection, or AI model.
2. **No silent egress & sandboxed boundary:** Release builds run inside **App Sandbox** with **zero `com.apple.security.network.client`** on the main `Rasc` executable. When the user opts into downloading the speech pack, only an isolated XPC helper (`com.rafaeltorres.rasc.VoiceModelDownloader.xpc`) touches the network, returning verified read-only handles to `Rasc` (which validates byte count + SHA-256 against `VoiceModelManifest.json`). Zero telemetry, analytics, or remote logging exist anywhere in the codebase.
3. **Explicit, stateless, conservative, reversible Refine:** Uses Apple `SystemLanguageModel.default` on-device (macOS 26+ Apple Intelligence). Requests are stateless per note (zero cross-note history). The original thought is never overwritten before user acceptance; three views (`Suggested`, word-level `Changes` diff, `Original`) allow inspection and immediate `Esc` rollback or post-accept Undo.
4. **No scope creep:** No folders, tags, multi-device sync, cloud chat, semantic embeddings, agents, or auto-Keep.

---

## 2. Verified Quantitative Metrics (`Mac15,6` M3 Pro 18 GiB, macOS `26.5.1`)

### 2.1 Application Footprint, Idle Residency & Responsiveness (`efficiency-web-data.json`)

| Metric | Measured Result | Scope / Notes |
|---|---:|---|
| **Standard Release `.app` size** | **`40.54 MiB`** (`42,367,708 B`) | Ad-hoc signed, App Sandbox, zero embedded Sparkle or speech model |
| **Sparkle + LLC RC `.app` / DMG** | **`44.50 MiB`** `.app` (`46,660,045 B`) · **`13.14 MiB`** DMG (`13,782,657 B`) | `0.1.16-final-rc` (`build 22`, `208d426e...`), embeds `Sparkle.framework` + `libswiftCompatibilitySpan.dylib` pinned via LLC |
| **Optional Speech Model Pack** | **`622.09 MiB`** (`652,304,885 B`) | `Fluid Speech Pro` (`3b9d38a9...`); stored outside `.app`, downloaded/imported only on explicit opt-in |
| **Cold launch settle (`n=5`, `n=3` reps)** | **`0.74 s`** p50 · **`24.59 MiB`** `phys_footprint` | Unlocked desktop, standard Release (`0.83 s` / `25.20 MiB` on Sparkle LLC build) |
| **Short standby Voice Off / Voice On (`90 s`)** | **`24.49 MiB`** (`0.0024%` CPU) / **`50.17 MiB`** (`0.0017%` CPU) | **`0.000/s`** pkg idle wakeups, `0.00–0.01 mW` XNU CPU power |
| **8.00h Active Soak (`20261126-191517-full-32h`)** | **`73.70 MiB`** p50 · **`73.77 MiB`** end (`125.99 MiB` max) | `28,801.45 s` wall (`15,594.13 s` active, `15` sleeps, `260` notes, `32` Refine, `7` sleep/wake probes); `0.0295%` p50 CPU, `0.0/s` p50 wakeups, **`0` Rasc leaks** (`288` Apple `LNDaemonApplicationInterface` XPC cycles constant) |
| **8.50h Voice-On Idle Standby (`stage_2`)** | **`33.66 MiB`** p50 (`61.88 -> 30.94 MiB` end, `-1.06 MiB/h`) | `8.50h` of planned `24.0h` captured before host stop at `2026-11-27T11:46:05-0300` (reported honestly without extrapolation); `11.81 MiB` flat `neural_footprint`, **`0.0%` p50 CPU**, **`0.0/s` p50 wakeups**, `1.9586 J` total (`0.06 mW` mean), `0` Rasc leaks |
| **Accelerated Workday Peak & Cooldown** |Peak **`143.16 MiB`** (`−51.5%`) · Cooldown **`63.70 MiB`** (`−66.3%`) | `n=3` medians vs `1cee496` (`294.99` / `189.22 MiB`); CPU time `−70.8%`, XNU CPU energy `−74.7%` (`52.14 J`) |
| **Home UI & `5,000`-Note SQLite Scale (`30c5c14`)** | `home_open` **`4.26 ms`** (`141×`), `search` **`11.56 ms`**, `close` **`5.77 ms`** | At `5,000` notes (`1,000` kept): `fetchMostRecent` **`0.041 ms`**, `search(20)` **`4.48 ms`**, `search(500)` **`6.62 ms`**, `backup` **`6.24 ms`**, WAL truncate **`5.00 ms -> 0 B`** |

### 2.2 Paired On-Device Voice Benchmarks (`voice-competitive-web-data.json`, Release `RascBench`)

All comparators ran locally on the exact same M3 Pro / macOS `26.5.1` audio sets:
- **Rasc `Fluid Speech Pro`** (`AsrModels.loadLocalOnly`, CPU + Neural Engine, verbatim)
- **Apple `SpeechTranscriber`** (macOS 26 built-in on-device `SpeechAnalyzer`)
- **Local `mlx-whisper`** (`mlx-community/whisper-large-v3-turbo` 4-bit MLX, representing local Whisper competitors such as Handy / local Superwhisper / VoiceInk Whisper mode; `~2.41 GiB` peak RAM)

| Corpus | `Rasc Fluid Pro` WER / Latency | `Apple SpeechTranscriber` WER / Latency | `Whisper Large v3 Turbo (MLX)` WER / Latency |
|---|---:|---:|---:|
| **VoiceArena (`n=151`)** | **`8.925%`** (`0` empty, `p50 65.6 ms`, `p95 368.8 ms`, `RTF 0.006`) | `11.456%` (`p50 218.4 ms`) | `11.609%` (`p50 1382.8 ms`) |
| **Round 3 Held (`n=168`, natural/conv/switch)** | **`14.151%`** (`5` empty, `p50 42.15 ms`, vs `+200ms` pad `15.002%`) | `23.466%` (`8` empty, `p50 68.9 ms`) | `20.152%` (`p50 1291.3 ms`) |
| **FLEURS-60 (`30 EN + 30 PT`)** | **`4.961%`** (`EN 5.965%` / `PT 3.949%`, `p50 53.3 ms`) | `8.425%` (`p50 130.9 ms`) | `5.433%` (`p50 1341.1 ms`) |
| **Long-form `-20 dBFS` `30s–300s` (`n=11`)** | **`9.605%`** (`0` empty, `p50 821.3 ms`, `300s 1.43–1.51 s`) | `16.423%` (`p50 1140.7 ms`) | `35.054%` (`p50 9424.1 ms`) |
| **Long-form un-normalized `30s–300s` (`n=17`)** | **`13.720%`** (`0` empty, `p50 828.1 ms`) | `24.275%` (`1` empty) | `52.062%` |

- **Awake End-to-End Voice Latency (`caffeinate -i`, Release):** `coldShortcutToReady 46.94 ms`, `warmShortcutToReady p50 31.04 ms`, `coldFinishToTranscript 380.82 ms`, `warmFinishToTranscript p50 65.55 ms / p95 148.10 ms`, `warmFinishToScratchpad p50 65.95 ms` (`dbSaveAndFetch p50 0.420 ms`), `warmFinishToDictate p50 65.67 ms`, `postIdleFinishToTranscript p50 205.86 ms`.
- **Stage 4 Streaming `VoiceAudio.mono16k()` Fix (`30c5c14`):** `norm_en_us_300s_48k_mono` retains **`4,800,000 / 4,800,000` (`100.0%`)** frames in **`21.66 ms`** using reusable `15 s` `AVAudioConverter` chunks (matching `9.605%` WER with `32.30 MiB` released footprint).

### 2.3 On-Device Refine (`refine-web-data.json`, Live `SystemLanguageModel.default`)

| Dataset | `n` | Objective Pass Rate (vs `M12B-008`) | Latency `p50 / p95` | User-Visible Protected Literal Corruptions | Proposal Failures | User-Visible Language Safe |
|---|---:|---:|---:|---:|---:|---:|
| **Validation** | `57` | **`64.9%`** (vs `54.4%`) | `747 / 1116 ms` | **`0`** (`2` blocked by guard) | `0.0%` | `94.1%` |
| **Holdout** | `72` | **`63.9%`** (vs `54.2%`) | `720 / 1105 ms` | **`0`** (`3` blocked by guard) | `0.0%` | `97.1%` |
| **Regression** | `6` | **`66.7%`** (vs `66.7%`) | `743 / 1258 ms` | **`0`** (`0` blocked) | `0.0%` | `100.0%` |
| **Live PT/Mixed Voice→Refine** | `16` | `11` changed, `4` noChange, `1` caught `providerFailure` | `1048.6 / 1252.8 ms` | `—` | `6.25%` caught safely | Original intact on failure |

---

## 3. Claims & Boundaries (`rasc-web` Guardrails)

### Safe Public Claims
1. Zero account, zero telemetry, zero cloud fallback, App Sandbox without main-app `network.client`.
2. Capture, Keep, Search (`FTS5`), and Export (`Markdown` + `manifest.json`) work instantaneously without AI (`4.26 ms` Home open, `4.48 ms` search at 5k notes).
3. Quiet background footprint (`~24.5 MiB` idle Voice Off, `~33.7–50.2 MiB` idle Voice On with `0.0/s` median package wakeups across 8.5h standby, `~73.7 MiB` p50 across an 8h active soak with `0` Rasc leaks).
4. Verbatim Core ML speech recognition (`Fluid Speech Pro`, opt-in `622 MiB` pack) outperforms built-in macOS `SpeechTranscriber` and local 4-bit `whisper-large-v3-turbo` on tested FLEURS, VoiceArena, Round 3 Held, and 30s–300s corpora on M3 Pro at `~53–66 ms` median short-clip latency (`RTF ~0.005–0.006`).
5. Refine is explicit, reversible, stateless per note, and protects numbers/dates/URLs/emails/identifiers with `0` user-visible literal corruptions across validation and holdout suites.

### Do NOT Claim
- **Never conflate ZER/AMEND (`Wispr Flow`, `Monologue`, etc.) with verbatim WER**, nor claim overall superiority over cloud-formatted products without an editorial/human-edit trial.
- **Never claim `24h` completed standby**: Stage 2 stopped cleanly at **`8.50h` of `24.0h`**.
- **Never claim `0%` errors or "ready-to-send"**: bare ChatGPT-style questions (`ai_prompt`) get answered instead of preserved if fed directly to Refine, proper names/technical identifiers can suffer verbatim ASR errors (`<unk>` or phonetic approximations), and one ~20.5 s clause in unchunked 300s audio was dropped inside upstream FluidAudio multi-chunk merging (`ChunkProcessor.swift`).
- **Never claim notarization or Intel/macOS 14–15 runtime proof**: `0.1.16-final-rc` and `v0.1.15` are ad-hoc signed unnotarized Apple silicon builds verified on `macOS 26.5.1` (`M3 Pro`). Include **Open Anyway** guidance until Developer ID + notarization ships.
- **Never claim full-SoC wall watts or battery hours** (`sudo powermetrics` unavailable; XNU per-process CPU energy only) or physical Bluetooth/Spaces/VoiceOver sign-off (pending manual desktop QA checklist).
