# Editorial & Asset Brief for `rasc-web`

**Target:** `rasc-web` marketing landing page, `/notes` engineering essays, interactive comparison widgets, and open-source download page.
**Data Root:** `docs/evidence/` (generated directly from verified M3 Pro `30c5c14` outputs; zero personal data).

---

## 1. Story Arc & Product Voice

- **Core Thesis:** *"A fast place before the note."* Most tools force premature organization (folders, tags, workspaces, chatbots) or push everything through the cloud. Rasc respects unfinished thoughts: instant invoke (`<5 ms` warm open), zero account, zero telemetry, optional offline AI when you explicitly ask for it, and clean handoff when an idea graduates.
- **Tone:** Calm, utilitarian macOS engineering craft — warm graphite & paper minimalism, empirical honesty (publish error cases and unverified platforms openly rather than cherry-picking "99% accuracy" claims).
- **Visual Direction:** Use Graphite Paper Light & Dark pairs side-by-side (`home-list-{light,dark}.png`, `scratchpad-text-{light,dark}.png`, `refine-preview-changes-{light,dark}.png`). Copper (`#B8602D` / `#D67A45`) must stay strictly scoped to **Keep / Kept** badges and primary Keep interactions.

---

## 2. Section-by-Section Asset Map

| Page / Section | Structured Data (`docs/evidence/...`) | Visual Assets (`docs/evidence/...`) | Key Proof Point to Highlight |
|---|---|---|---|
| **Hero / Above the Fold** | `efficiency-web-data.json` (`states`, `storage_distinction`) | `screenshots/scratchpad-text-dark.png`, `screenshots/scratchpad-text-light.png` | `40.54 MiB` app, `~24.5 MiB` idle, `0.000/s` idle wakeups, opens instantly without AI or internet |
| **Lifecycle & Retrieval (`Keep`, `Home`, `Search`)** | `efficiency-web-data.json` (`operation_latencies_ms`, `scale_benchmark_1k_5k`) | `screenshots/home-list-light.png`, `screenshots/home-cards-dark.png`, `screenshots/home-batch-light.png`, `screenshots/quick-search-grat-light.png`, `screenshots/command-palette-re-dark.png` | `4.26 ms` Home open, `4.48 ms` FTS5 search at `5,000` notes (`0.041 ms` recent fetch), batch export/discard with transactional Undo |
| **Voice & Dictate (Offline Core ML)** | `voice-competitive-web-data.json` (`paired_corpora`, `e2e_awake_latency_ms`, `streaming_resampling_final`) | `screenshots/voice-hud-listening-dark.png`, `screenshots/voice-hud-transcribing-light.png`, `screenshots/onboarding-v2-voice-light.png`, `examples/*.wav`, `examples/examples.json` | Opt-in `622 MiB` pack via isolated XPC; `65.6 ms` warm E2E finish→text; beats local `SpeechTranscriber` and `mlx-whisper` across FLEURS (`4.96%`), VoiceArena (`8.93%`), Round 3 (`14.15%`), and normalized `300s` (`9.61%`) |
| **Honest Audio Corner (Listen Yourself)** | `voice-competitive-web-data.json` (`longform_diagnostic_findings`, `cannot_claim`) | `examples/en_us-000001683.wav` (clean), `examples/en_us-000001664.wav` ("powders"→"powers"), `examples/pt_br-000001678.wav` (`<unk>`), `examples/pt_br-000001891.wav` (proper nouns), `examples/ATTRIBUTION.md` | Publish real CC BY 4.0 FLEURS audio + verbatim transcripts showing both clean recognition and honest proper-noun/`<unk>` limitations |
| **On-Device Refine (`Apple Foundation Models`)** | `refine-web-data.json` (`datasets`, `baseline_reference_m12b_008`) | `screenshots/refine-preview-suggested-light.png`, `screenshots/refine-preview-changes-light.png`, `screenshots/refine-preview-changes-dark.png`, `examples/refine_examples.json` | Explicit, stateless, reversible diff (`Suggested / Changes / Original`); `64.9%` / `63.9%` objective pass vs `54.4%` / `54.2%` M12B-008 baseline; **`0` user-visible protected literal corruptions**; document bare-question & `providerFailure` guardrails |
| **Quiet Background Efficiency (`/notes` Deep-Dive)** | `efficiency-web-data.json` (`before_vs_after`, `replications`, `long_running_20261126`) | `screenshots/settings-general-light.png`, `screenshots/settings-theme-dark.png`, `screenshots/settings-voice-dark.png` | Interactive Before→After workday charts (`−51.5%` peak RAM, `−70.8%` CPU, `−74.7%` XNU energy), `8h` active soak (`73.7 MiB` p50, `0` Rasc leaks) + `8.50h` idle Voice-On (`30.9 MiB` settled, `0.0%` CPU, `0.0/s` p50 wakeups) |
| **Trust, Sandbox & Installation** | `efficiency-web-data.json` (`rc_0_1_16_final_verification`) | `screenshots/onboarding-welcome-light.png`, `screenshots/settings-shortcuts-light.png`, `screenshots/voice-hud-permission-light.png` | MIT open-source, `PRAGMA quick_check` fail-closed DB, zero network entitlement on main app, verified SHA-256 + Ed25519 Sparkle delta updates + honest **Open Anyway** note while ad-hoc signed |

---

## 3. Chart & Interactive Widget Recommendations

1. **Paired Speech Engine Comparison Chart (`voice-competitive-web-data.json`):** Bar chart showing **WER (%) ↓** alongside a **Median Latency (ms) log/linear toggle** for Rasc `Fluid Speech Pro`, `Apple SpeechTranscriber`, and `Whisper Large v3 Turbo (MLX)` across FLEURS (`4.96%` / `53 ms`), VoiceArena (`8.93%` / `66 ms`), Round 3 (`14.15%` / `42 ms`), and Long-Form `30s–300s` `-20 dBFS` (`9.61%` / `821 ms`). Include footnote: *"Same audio clips, warm M3 Pro 18 GiB, verbatim output without LLM rewriting."*
2. **Standby & Workday Efficiency Trajectory (`efficiency-web-data.json`):** Dual chart pairing Before vs After `n=3` workday bars (`294.99 → 143.16 MiB` peak, `600.17 → 4.26 ms` Home open) with `long_running_20261126` 8.0h active soak + 8.50h standby (`73.70 MiB` → `30.94 MiB`, `0.0/s` p50 wakeups, `0` leaks).
3. **Interactive Refine Diff Drawer (`examples/refine_examples.json`):** Let visitors toggle between **Original**, **Changes**, and **Suggested** on real synthetic notes (`syn_pt_meeting`, `syn_pt_uncertainty`, `syn_en_numbers_urls`) and inspect one guarded failure boundary (`syn_mixed_bare_prompt` / `mix-r3-por_1706_CC`).
4. **Audio + Verbatim Player (`examples/*.wav`):** Click-to-play 8–16 s FLEURS CC BY 4.0 clips paired directly with their human reference and unmodified Rasc transcript, plus proper `Conneau et al. (FLEURS, CC BY 4.0)` attribution.
