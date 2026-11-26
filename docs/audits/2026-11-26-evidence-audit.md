# Rasc evidence audit · 26 November 2026

**Baseline source:** `main` + this phase (`d9e88ef` + branches for #98/#99/#100/eval). **Rasc 0.1.16 build 22.** **Machine:** Mac15,6 M3 Pro 18 GB macOS 26.5.1, Xcode 26.2. **Published artifact** docs describe **v0.1.15 build 21**; current source ≠ shipped artifact.

**Purpose:** audit *entire technical history* (docs, PRs, experiments, benchmarks, raw results, ADRs). Classify each finding: **valid current**, **previous version**, **comparable**, **needs reproduction**. Distinguish **isolated model benchmark**, **engineering probe**, **synthetic test**, **end-to-end app measurement**. Honest about gaps.

See also `docs/README.md` (historical vs current), `Evals/README.md`, `Evals/Refine/FROZEN.md`, `Experiments/VoiceCapture/**`, `docs/audits/*`, this phase `docs/performance/APP-PERFORMANCE.md`, `Experiments/VoiceCapture/Round4/*`, `Experiments/Competitive/*`.

## 0. Headline validity

- **Current source truth:** `docs/CURRENT-PRODUCT.md`, `docs/DESIGN-SYSTEM.md`, `docs/BRAND.md`, `docs/DATA-AND-PRIVACY.md`, `docs/NATIVE-UI-VALIDATION.md`, `docs/VOICE-CAPTURE.md`, `docs/REFINE-RELIABILITY.md`(historical header but records policy), `docs/REFINE-V2.md`(historical), **`Rasc/` source + tests**. **Historical `Product.md`, `PRD.md`, `UX-Spec.md`, `ARCHITECTURE.MD`, `HOME-SPEC.MD`, `ONBOARDING-SPEC.md`, `PRODUCT-STATE.md`, `RASC-CONTEXT.md`, `RELEASE_READINESS.md`, `PRIVATE-BETA.md`, `BETA-1`, `PUBLISH-0.1`, `RC-MANUAL-TEST` are NOT proof of current behavior.**
- **Shipped vs source:** docs v0.1.15 build 21 published; source 0.1.16 build 22 + phase branches. **Release artifact not rebuilt/signed/notarized here.**
- **Voice model provenance** unchanged across app versions; **Round3 study app ≠ shipping Rasc**; **Round4 measures actual app code** (DEBUG + Release build); **isolated model benchmarks ≠ app end-to-end**; **Round1 synthetic TTS ≠ real human**; **Round3 real human held-out = comparable**; **VoiceArena/Codictate/OpenASR/Monologue = third-party/vendor, different metrics**.
- **Features added this phase** (#98/#99/#100) have **domain/native-build/test evidence; physical-key + a11y + native-click not claimed.**

## 1. Evidence taxonomy

| Type | Meaning | Where |
|---|---|---|
| **Isolated model benchmark** | model only, no app/mic/UI/DB | OpenASR; Round1; Round4 app-code CLI (actual app code, no mic/DB) |
| **Engineering probe** | targeted mechanism, not product | `Experiments/VoiceCapture/AppleProbe`, `build-probe`, XPC probes, `Experiments/LocalMCP`, `default.profraw`, `build/*`, `Experiments/VoiceCapture/design`, `Vendor` |
| **Synthetic test** | fixtures/TTS/injected audio; deterministic | `RascTests`, `Evals/Refine` synthetic, Round1 `corpus.json`, `make-fixtures.py`, `MicBuffer` injection, VoiceCapture `Fixture`, synthetic images |
| **End-to-end app measurement** | real app + real model + (sometimes) mic + SQLite + delivery | Round3 signed study app + `results/workflow-*`; M13A scale (not full app launch); **Round4 Release idle**; app-code CLI is *not* full-app |
| **Comparable** | same model/scorer/harness/machine; not re-run | Round3 → Round4 citation; FluidVoice shares engine (not measured) |
| **Needs reproduction** | plausible but not current/robustly evidenced | see §6 |

## 2. Technical history inventory (docs + Evals + Experiments + Scripts + PRs)

### 2.1 Core product / architecture docs

| Artifact | Type | Validity |
|---|---|---|
| `docs/CURRENT-PRODUCT.md`, `docs/README.md`, `docs/DATA-AND-PRIVACY.md`, `docs/NATIVE-UI-VALIDATION.md`, `docs/VOICE-CAPTURE.md`, `docs/DESIGN-SYSTEM.md`, `docs/BRAND.md`, `docs/RELEASE*`, `docs/SPARKLE*`, `docs/INSTALL-UNSIGNED.md`, `docs/THIRD_PARTY_NOTICES.md`, `docs/DATA...`, `docs/APP-RELIABILITY.md`, `docs/PUBLISH-0.1`, `docs/LOCAL-MCP-FEASIBILITY.md`, `docs/ONBOARDING-SPEC`, `docs/UX-Spec`, `docs/HOME-SPEC`, `docs/ARCHITECTURE.MD`, `docs/PRD.md`, `docs/Product.md`, `docs/RASC-CONTEXT.md`, `docs/PRODUCT-STATE.md`, `docs/PRIVATE-BETA.md`, `docs/BETA-1`, `RELEASE_READINESS.md`, `docs/THOUGHT-COMPLETION*`, `docs/REFINE-*`, `docs/M3B-FOUNDATION-MODELS.md`, `docs/LOCAL-MCP-FEASIBILITY`, `docs/APP-RELIABILITY` | doc | current (CURRENT-*) / historical |
| `AGENTS.md`, `CONTRIBUTING`, `README`, `SECURITY`, `CODE_OF_CONDUCT` | doc | current |
| `docs/audits/2026-11-03-quality-audit.md` (PT; **Rasc 0.1.3 build 9**; `e3b77fd`) + screenshots | end-to-end/native (manual+auto) | **previous version**; findings on 0.1.3; not current; some principles recur |
| `docs/audits/2026-11-13-visual-language.md` + `docs/audits/2026-11-13-visual/**` (**0.1.5 build 11**; `5786e3d`) | native render / visual | **previous version**; static 2× renders; **not** live focus/VoiceOver/Spaces; current design in DESIGN-SYSTEM; **not re-verified** |
| `docs/audits/2026-11-03/**` screenshots | native render | previous version |
| `docs/validation/**` (export, home-logo, twin-fish, orb, logo-tail) | native render + manual | previous; current brand in BRAND; **not re-run** |
| `docs/plans/**` (M3B/M8/M9A/M12B-003/005B/selection) | design plan | historical; check shipped |
| `docs/PUBLISH-0.1`, `docs/PRIVATE-BETA`, `docs/RELEASE-NOTES-v0.1.*`, `docs/RELEASE-NOTES-v0.1.15` + `docs/RELEASE.md` provenance | release record | artifact-specific; **published v0.1.15**; not proof of current source; notarization not claimed |

### 2.2 Refine evidence (`Evals/Refine`, `docs/REFINE-*`, `docs/M3B`, `Rasc/Eval`, `Scripts/*refine*`)

| Artifact | Type | Date/commit | Validity |
|---|---|---|---|
| `docs/M3B-FOUNDATION-MODELS.md` | design + audit of `FoundationModels` APIs (Xcode 26.2 macOS 26.2 SDK; no cloud; `@Generable`; `exceededContextWindowSize`; no `contextSize`; macOS14 + `#available`) | historical header; M3B | **previous version** as doc; **current code** in `Rasc/AI/`; `SystemLanguageModel.availability == available` **re-verified**; `RefineUncertaintyLossGuardLiveSmokeTests` **re-passed**; `RefineReliabilityTests` **re-passed**; `FoundationModelsProviderContractTests` **re-passed** |
| `docs/REFINE-RELIABILITY.md` (M12A) + `docs/REFINE-V2.md` | measurement system + policy | historical header | policy **current**; **corpus `corpus.v1.jsonl` 322**, splits dev193/val57/hold72, regression6, review75; **frozen `FROZEN.md` v2 `2026-09-20`**; **not re-run wholesale**; baseline metrics in experiment docs + adjudications; **generated `reports/` gitignored, not current** |
| `Evals/Refine/frontier-adjudications.v1.jsonl`, `Evals/Refine/challenges`, `Evals/Refine/experiments/M12B-*`, `M12C-*` | raw + adjudication + analysis.json + reports + production-diff + policies + `experiment.md` | dated commits in docs | **validated production changes** for specific guards (protected literals, money/time/percentage, language resolver, uncertainty, selection, no-change); **comparable**; **not re-run**; **human review not proven** (`review-queue` "not auto-validated"; `frontier-adjudications` need maintainer clearance before public); `M12C-002` **rejected/reverted**; `M12C-001` language preference shipped; `REFINE-RELIABILITY` states automated checks ≠ proof meaning unchanged |
| `Evals/Refine/FROZEN.md` `frontier-adjudications` + corpus | frozen artifact | 2026-09-20 | current input; maintainer confirmation note |
| `Rasc/Eval/RefineReliability/**`, `Scripts/refine-*`, `run-m12*`, `analyze-m12*`, `generate-*`, `compare-baseline-v1-v2`, `refine-adjudicate-apply.sh`, `refine-review*`, `refine-resolver-eval` | harness + scripts | — | **reproducible**; needs Apple Intelligence + opt-in; **not re-run wholesale** |
| `RascTests/Refine*`, `RefineUncertaintyLossGuardLiveSmokeTests` (opt-in `~/.rasc-live-fm-smoke-optin`) | synthetic + live | — | **synthetic pass; live smoke re-passed** |
| `docs/REFINE-RELIABILITY` protected-token + language findings | analysis | — | comparable; not re-measured |

**Milestone IDs** referenced across repo: M3B, M8/M9A, M12A, M12B-001…008, M12C-001/002, M13A, M14, M15A, M16, plus `#48` reliability, `#96/#97`, voice PRs `#95/#96`, export `#95`, etc. **We did not re-run M12B/M12C batteries.** Only Round4 re-checks listed.

### 2.3 Application reliability / performance (`Evals/AppReliability`, `RascTests`, `AppDiagnostics`)

| Artifact | Type | Validity |
|---|---|---|
| `Evals/AppReliability/M13A/performance.json` + `report.md` + `analysis.json` + `issue-register` | **scale benchmark** (temp SQLite, dev, **not shipping**; n=3 counts; not app-launch p50) | **comparable**; **`AppReliabilityScaleTests` re-passed**; **not re-measured Release**; `thresholdsPassed=true` |
| `Evals/AppReliability/M14/{checklist-results,issue-register,acceptance-report}` | native + acceptance (earlier) | **previous**; not re-run; manual RC still needed |
| `RascTests/AppReliabilityLifecycleTests`, `AppReliabilityScaleTests`, `QualitySprintTests`, `PanelControllerTests`, `HomeWindowControllerTests`, `ScratchpadSessionTests`, `NoteRepositoryTests`, `NoteExportTests`, `ThoughtCompletionTests`, `OverlayStateTests`, `Onboarding*`, `PaletteCommand`, `DiscardUndo*`, `Sparkle*`, etc. | synthetic/native | **current; re-passed** (domain suite + native listed; **Xcode test runner can't launch in this sandbox; `Scripts/test-domain.py` used; native window suites in CI**) |
| `Rasc/Platform/AppDiagnostics` (`bootstrapStarted/Ready/Failed`, `durationMs`, no note content; `AppReliability` logs) | instrumentation | current; `OSLog` no content; **not a benchmark by itself** |
| `docs/APP-RELIABILITY.md`, `docs/NATIVE-UI-VALIDATION`, `docs/RC-MANUAL-TEST`, `docs/RELEASE` | doc + manual | current policy; **manual not claimed** |
| `docs/audits/2026-11-03` "18% CPU idle" (0.1.3) | observation | **stale; not current; not re-measured**; **this round idle ~0 + startup spike, 63 MB footprint**; hidden-0 previously |

### 2.4 Voice Capture history (`docs/VOICE-CAPTURE`, `Rasc/Features/VoiceCapture`, `VoiceModelDownloader`, `Scripts/stage-voice-model.py`, `Scripts/build-voice-preview.sh`, `Experiments/VoiceCapture/**`, `RascTests/VoiceCaptureTests`, `VoiceModelManifest.json`, `Vendor/FluidAudio` pinned)

#### Round 1 (`Experiments/VoiceCapture/README.md`, `ASSESSMENT`, `RESEARCH`, `corpus.json`, `make-fixtures.py`, `score.py`, `run-apple`, `run-whisper`, `Parakeet`, `Whisper`, `Persistence`, `results`, `build-probe.sh`, `probe.entitlements`, `AppleProbe.swift`, `design/**`)
- **Synthetic TTS** (`say` Samantha/Luciana + generated noise); **engineering probe.** Apple `SpeechTranscriber` vs `DictationTranscriber` vs Whisper-turbo vs Parakeet v3; WER on synthetic; persistence spike; `nonactivatingPanel`; hold/toggle; **not real human; not current product; not comparable to Round3/4 real human.** **Not re-run.**
- **`Experiments/VoiceCapture/ASSESSMENT.md`, `RESEARCH.md`** historical. **`design/**` UI exploration (concepts, SendTestHotkey) not shipped; not evidence.** Round3 study app in `Round3/Study` separate identity ~1.2 GiB + both models; **not shipping.**

#### Round 2 (`Round2/README`, `MODEL-SURVEY`, `REPRODUCE`, `TEST-PROTOCOL`, results, `Round2/Study`, `Round2/Bench`)
- Model survey; pinned FluidAudio; **Parakeet Ultra comparator**; holdout; **not shipping; comparable (Round3 uses model-lock); not re-run.** Smaller holdout favored Ultra in one slice; Round3 says Fluid consistent directional lead on new holdout. **Both retained.**

#### Round 3 (`Round3/README`, `VALIDATION`, `INTEGRATION`, `FINAL-PASS`, `PERSONAL-TEST`, `REPRODUCE`, `results/**`, `Bench/**`, `Study/**`, `visual/**`) — **current deepest voice evidence; `250f1c1`/0.3.1 study; `main 250f1c1…`; M3 Pro; macOS 26.5.1; Xcode 26.2; signed; NOT shipping app; 168 attempts; `n=64+64+40`**
- **Model lock `Round2/results/model-lock.json`; `VoiceModelManifest`; revision `3b9d38a…`; FluidAudio `386f719…`; `.fluidParakeetPro`; verbatim; CPU+ANE; 16k; pad; 120ms; no streaming/vocab; `AsrManager`.**
- **WER pooled** PT-BR conv **21.82** / EN meeting **13.00** / mixed **8.89**; Ultra 22.85/16.14/10.05; Apple 25.55/18.87/24.23; bootstrap; **4 empty PT Fluid / 2 Apple / 0 Ultra**; **all 168 completed.**
- **Semantic** negation loss; proper names; numbers; uncertainty; self-correction not applied; `Supabase`/`Jakarta`; **not auto-Keep; study auto-Keep ≠ shipping.**
- **Performance** (signed study; not shipping Release; not re-run full matrix): acquisition 23.42s; extract n/a; no `compileModel`; first `MLModel.load` 16.56s; warm 333+140; new proc 333+75; cold first capture 13.85s; post-idle 19.54 vs 209; probe 18.09 vs 201 (**docs/VOICE-CAPTURE** shipping probe on M3Pro!); **CPU-only 3.47s vs 16.85 +157/168 identical +WER ~+0.3–1.5; CPU+GPU ~1GB; CPU+ANE default;** RSS/footprint numbers; 11.3MB after expiry; **`powermetrics` no; Power Profiler no; energy not measured.**
- **Workflow** `n=6` warm Finish→text / DB / total; **SQLite ~1.8ms;** physical mic separate; **focus no-steal verified app-level; VoiceOver/FKA/Spaces/Stage Manager/Bluetooth/sleep on hardware NOT claimed.**
- **Reliability** 14 groups/43 injected; silent/click reject; route/sleep; timeout; cancellation; retry; recover; SQLite reject; offline (Wi-Fi off; no active net; no network entitlement); **physical process loss before transcript can't recover audio; no leak proof.**
- **Release gates** mic continuity across Sparkle (needs stable signing; ad-hoc reverts; TN3127); model delivery; integrated native checks; fidelity/resource targets. **No Developer ID.**
- **Comparable** (same model/scorer/machine); **not re-run Round4; Round4 reproduces app-code path + FLEURS.**

#### Shipping app (`Rasc/Features/VoiceCapture`, `VoiceModel`, `VoiceMicrophone`, `VoiceCaptureView`, `VoiceModelDownloader`, `Rasc/Resources/VoiceModelManifest.json`, `docs/VOICE-CAPTURE`, `RascTests/VoiceCaptureTests`, `Rasc.entitlements`, `VoiceModelDownloader` sandboxed XPC, `Scripts/stage-voice-model`, `build-voice-preview`)
- **`VoiceCapture.shared`**; opt-in; macOS 26 + arm64; KeyboardShortcuts `.voiceCapture` key-down; 180ms debounce; non-activating capsule; `NSPanel`; restores app; local monitor; blocked sheet; `flushForTermination`; `hasUnsavedAudio`; retry/120s expiry; `recover`; `releaseModelWhenSafe`; `DispatchSource` memory pressure; sleep/wake; `scheduleReprepare`; **`VoiceModel` `retention`** + `releaseForMemoryPressure`; `AsrModels.loadLocalOnly`; **`VoiceModelAssets` manifest SHA-256 + size + atomic + prune + `Choose Model Folder…` + `Download` XPC `Range` + host-restricted redirects + size limits + progress + `clearCache` + sandbox `app-sandbox+network.client`;** main app no network; **SQLite `createScratch`;** open scratch; guards; **not auto-Keep;** verbatim; no cloud; `refine` separate. **Recognition diagnostics timing only; no content logs; no telemetry.**
- **model `retention` currently `nil` in app `VoiceModel()`** (always-keep while enabled + explicit release; `retention` unused in production); Round3 study used 60s. **Adaptive lifecycle retained under pressure.** **VoiceCaptureTests serialized; `9300351`.**
- **Scratchpad shortcut interplay** `handleScratchpadShortcut`; `toggleScratchpad` ⌥\; `toggleHome` ⌘⌥\; conflict checks. **No modifier-only before #98.**
- **Previous versions:** older `pending review` migrate; `v9_voice_review`→`v10_voice_review_to_scratch`; `0.1.15` provenance; preview builds; `Rasc Voice Preview.app`. **Not current claims.**

### 2.5 This phase — implemented features + evidence (new)

| Issue | Implementation | Tests | Native | Evidence status |
|---|---|---|---|---|
| **#98** | `ModifierShortcut`, `ModifierTapRecognizer`, `ModifierShortcutStore`, `ModifierShortcutMonitor`, `ModifierShortcutRecorderModel`; flagsChanged global+local; clean-key-up; 400ms; chord/diacritic/pointer/other-modifier guard; 180ms debounce; Esc/cancel reset; preserve KeyboardShortcuts; conflict-free; AX trust + prompt + System Settings; Settings recorder; palette display | `ModifierShortcutTests`; full suite | Release+Debug build; **not physical key/a11y/global** | **domain; native build; physical needs reproduction** |
| **#99** | `selectedNoteIDs`, anchor, mode; ⌘/Shift/⌘A/Esc; batch Copy/Export/Discard/Clear; `delete(ids:)` single txn + `restoreDiscards`; `DiscardUndoRegistration`; `NoteExportController.exportSelectedThoughts`; `NoteExportFiles.writeFolder`; `onExportSelected`; both views; no schema | `HomeSessionTests`, `NoteRepositoryTests`, `NoteExportTests`; full | Release+Debug; **not native click** | **domain+persistence; native needs reproduction** |
| **#100** | `VoiceCaptureOutput`; `VoiceTextInsertion`; Clipboard/Insert/Scratchpad; AX `AXSelectedText`; fallback; no keystrokes; no activate; target mem; app-switch; optional history; no network; sandbox; phases + a11y; AX permission; focus | `VoiceCaptureTests` +new; full | **native AX→TextEdit probe**; Release; **AS grant/physical not** | **domain + native AX; grant/VoiceOver needs reproduction** |
| **eval harness** | `VoiceEvalCommandLine` (DEBUG); `VoiceModel.TranscriptionTiming` | — | app-code CLI + Release idle | **this round Round4** |
| **Round4** | corpus + perturb + score + results + protocol | — | — | **real human FLEURS; verbatim; no competitor** |
| **App perf** | `docs/performance/APP-PERFORMANCE` | `AppReliabilityScaleTests` re-pass | Release idle sample (restored DB) | **partial; energy not** |
| **Competitive** | `Experiments/Competitive/COMPETITIVE-EVALUATION` | — | — | **sourced landscape; no paired run** |

### 2.6 LocalMCP + other experiments + vendor + scripts
`Experiments/LocalMCP` (isolated Swift stdio + Mach/XPC + `paired-check`; `docs/LOCAL-MCP-FEASIBILITY`; **not shipping; no scope change; no semantic search/agent; product invariant no agents**; commit `92853b3`); `Vendor/ThinkingOrbsKit`, `Vendor/Sparkle`, `Vendor`; `VoiceModelDownloader`; `default.profraw`; `build/**`; `.derivedData`; `Scripts/test-domain.py`, `test-native.sh`, `test-domain`, `release`, `sparkle*`, `assets`, `stage-voice-model`, `build-voice-preview`, `analyze-*`, `prepare-*`, `classify-*`, `run-*`, `refine-*`, `compare-baseline`, `generate-*`. **`Scripts` historical research not current claims; `Evals/README`.**

### 2.7 CI / PRs / release provenance
`.github/workflows`: Debug build, `test-domain`, full native, **Release build**; `macos-26`, Xcode 26.2; `concurrency`. **PRs** referenced: #95 Markdown export; #96 voice; #97 icon; #98/#99/#100 this phase; earlier; `#48` reliability. **`docs/RELEASE-NOTES-v0.1.*` + `docs/RELEASE.md`** provenance; **v0.1.15 build 21 published ad-hoc unnotarized DMG; no Developer ID; Sparkle optional; mic continuity gate; no cloud; no telemetry.** **We did not verify a published artifact.**

## 3. Evidence that remains valid for current source (with scope)

1. **Core product invariants** (`AGENTS.md`/`CURRENT-PRODUCT`): capture fast + no AI; local-first SQLite; no silent off-device; no network recognition; **no auto-Keep; no folders/tags/etc; Refine explicit conservative reversible; original never destroyed before accept; isolated per note; no shared context.**
2. **Refine** production behavior + guards + `Evals/Refine` frozen + **re-run tests + live smoke + FM available.** (Not "perfect.")
3. **Voice** shipping behavior + **model provenance** + **Round3 comparable** + **Round4 this phase** + **release gates**. **Not auto-Keep; not streaming; not cloud; not custom vocab.**
4. **Reliability** `AppReliability*` + `NoteRepository` + `DiscardUndo` + `PanelController` + `ScratchpadSession` + `FlushForTermination` + tests **re-passed**; M13A numbers **comparable**; **manual native not claimed.**
5. **Performance M13A** + **Round3** + **Round4 idle** + **M3B** + **`AppDiagnostics`.** Scope hardware.
6. **Privacy** no telemetry/account/sync/cloud; no content logs; secrets Keychain; DB not encrypted by Rasc; no secure erase; XPC download only; sandbox no network recognition; **#98 needs Accessibility (TCC) for global; #100 needs Accessibility for insertion; not network.**
7. **New #98/#99/#100** domain + build; see §2.5.

## 4. Evidence that belongs to previous versions

- **0.1.3 / build9** Nov-3 audit + **0.1.5 / build11** visual; **0.1.15 published** vs source **0.1.16**; **Round1/2** study apps; **Round3 study app not shipping**; **M12C-002 rejected**; **`18% CPU idle`** stale; **`Breathing Orb`** stale; **old shortcuts**; **`docs/PRIVATE-BETA` pricing/access** not current; **older Voice review→scratch migration** is compatibility not current claim; **`frontier-adjudications` need clearance**; **`Evals` generated reports gitignored**; **`build/*` local**; **historical `Sparkle` proofs** not current artifact; **notarization** not claimed.

## 5. Comparable (same model/scorer/machine; not re-measured)

Round3 ↔ Round4; Round3 Fluid↔Ultra↔Apple; CPU↔ANE Round3; Round3 ↔ shipping (model unchanged); **FluidVoice shares FluidAudio + Fluid Speech Pro (not measured)**; **Codictate Parakeet TDT 0.6B v3 ≈ same family (not same CoreML build; different product; not run)**; **OpenASR `fluid_speech`/`nemo_asr` (not run; Linux H200)**; **Apple `SpeechTranscriber` Round3 (not literal Dictation keystroke; not shipping Rasc)**; **M13A across n**; **not** VoiceArena/Monologue (metric-incompatible).

## 6. Needs reproduction / missing evidence

- **Native physical:** modifier key chords incl #98 isolated vs chord + diacritic + Esc/cancel reset; **Accessibility grant**; global across apps; **#100 insertion target app + app-switching**; focus; **Spaces/fullscreen/Stage Manager/multi-monitor**; **VoiceOver**; **Full Keyboard Access**; **Bluetooth**; **sleep/wake** on active capture; **mic permission + Sparkle** stable signing; **#99 native click**; **Voice Capture on macOS 26.2 SDK vs 26.5.1 runtime**; **Release app-code CLI output == Release app output**.
- **Release performance:** startup/Scratchpad/Home/Search p50/p95; **idle voice on/off**; **memory** p50/p95; **CPU**; **energy**; **long-running**; **other hardware**; **lower-memory**; **XPC aux**; **Core ML cache**; **batch multi-select perf**; **Release Voice cold/warm**; **Refine Release**; **not re-measured.**
- **Voice accuracy:** spontaneous multi-speaker **code-switching**; **human adjudication semantic**; **editing effort**; **technical vocab + proper names + numbers** controlled real-human (Round3 notes; Round1 synthetic; not measured Round4); **accents beyond en/pt**; **noise types**; **long-form**; **n small**; **mic physical**; **cold p95 Release**; **not claiming vs competitors.**
- **Competitive:** **no paired run**; Tier-1 feasibility only; **mono-1 not run**; **Wispr/Superwhisper/Aqua/Typeless closed**; **Apple no WER**; **memory/energy** not measured; **cloud/local verification**.
- **Refine:** combined transcript+Refine WER; Release latency; larger/long; per-locale; **not re-run M12B/M12C**; auto **not** in shipping Voice.
- **Product:** `#48`, `#98-100`, manual checklists; **no production signed artifact re-verified.**

## 7. What cannot currently be claimed publicly

- "Fastest", "best", "more accurate than X", "lower energy than X", "99% accuracy", "no mistakes", "ready-to-send", "verified offline in production" without scope.
- **WER comparable across metrics**; ZER vs WER; vendor vs ours.
- **mono-1/Wispr/Superwhisper/Aqua/Typeless numbers** as ours.
- **Spontaneous code-switching solved**; **PT/EN perfect**; **proper names/numbers always**; **punctuation always**.
- **Semantic fidelity proven**; **no meaning loss**; **auto-Keep safe**; **Refine perfect**.
- **No telemetry** (Rasc true; competitors not claimed); **no network** (Rasc recognition true; model download exception; competitors vary).
- **Native a11y/focus/Spaces verified**; **VoiceOver**; **physical keys**; **mic permission continuity**; **Sparkle mic**.
- **Energy/thermal**; **no leaks**; **other hardware**; **Intel Voice**; **macOS14 Voice**; **memory-constrained**.
- **Signed/notarized current artifact**; **production ready**; **Sparkle production**; **MCP agent**; **cloud**.
- **`powermetrics`** measured; **Apple Intelligence guaranteed** (needs available; capture doesn't depend).
- **FluidVoice/Handy/VoiceInk measured**; **no paired.**

## 8. Reproducibility & raw results

- **Frozen Refine** `Evals/Refine/FROZEN.md` + `Scripts/refine-*`. **Round4** `PROTOCOL` + `scripts` + `run.json` + raw `results.jsonl` + `score.json`. **Round3** `REPRODUCE` + `Bench` + `results`. **M13A** `performance.json`. **MCP** `REPRODUCE`. **Voice model** `VoiceModelManifest.json` + `Scripts/stage-voice-model.py`. **CI.** **No private audio; no credentials; no note DB; no screenshots of private; restored container backup.** **`Evals/README` clearance note.**

## 9. Recommended next evidence (not blocking handoff)

1. Paired FluidVoice + Apple + (Whisper) run on Round4 corpus (Tier-1).
2. Physical-key + Accessibility + VoiceOver + app-switch + Spaces native checklist.
3. Release startup + memory + idle p50/p95; `powermetrics` if permitted; long-running.
4. Real-human task corpus (technical/names/numbers/code-switch/self-correction; EN+PT) + human adjudication + edit-time.
5. Cold p95 Release + Core ML cache fresh machine; stable signing + mic continuity; **still no cloud.**
6. Refine+transcript combined + Release latency.
