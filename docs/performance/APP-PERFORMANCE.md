# Application performance evaluation

**Scope.** Rasc app-level resource use on **Release** builds representative of distribution. **Not extrapolated** to hardware/OS not tested. **No user data.** Round4 + prior M13A/Round3. **Energy/thermal not measured** (no `powermetrics`, Power Profiler not permitted) — stated, not inferred.

## Environment (this round + reused)

- Mac15,6 M3 Pro 11 cores 18 GB; macOS 26.5.1 (25F80); Xcode 26.2; Rasc **0.1.16 build 22**; **Release** (ad-hoc signed, unsigned here, **sandboxed**, no updater in local build; distributed artifact sandboxed + no network + Sparkle in updater build).
- **Physical memory footprint** vs **RSS** vs **model on disk** vs **auxiliary processes** distinguished.
- **App size:** Release `.app` **39 MB** (this round). Speech model **separate 652,304,885 bytes (~622 MiB)** under `Application Support/Rasc/VoiceModels/<rev>`. Voice model downloader XPC separate, transient. **No bundled model in standard build** (preview builds bundle it; not measured). No third-party persistent helper.
- **Core ML cache** extra disk possible (Round3 measured 3.6 GB after sweeping configs; not production single-pack; not measured this round).

## This round measured (Release, verified; DB backup + restored)

| State | Physical footprint | RSS | CPU | Notes |
|---|---:|---:|---|---|
| **Idle, no window, 5 s after launch** | **63 MB** (`footprint`) | ~**746 MB** @5 s | startup spike → idle | mmap/file-backed inflate RSS; **footprint ≠ RSS**. Voice model **not loaded** (Voice Capture not triggered). |

**Caveat:** single sample; not p50/p95; not long-running; not with Voice model; not with Home; **restored container backup after.**

## Reused checked-in evidence (not re-run; see validity in evidence audit)

### Startup & app shell (M13A + AppDiagnostics; note: not Release-p50)
`AppReliabilityScaleTests` + M13A `performance.json` (temp SQLite, dev machine, **not shipping guarantee**):

| Note count | bootstrap | recentNoteLoad | search | noteSwitch | autosave |
|---:|---:|---:|---:|---:|---:|
| 10 | 4.35 ms | 0.28 | 1.02 | 0.0 | 0.49 |
| 100 | 4.42 | 0.39 | 1.02 | 0.001 | 0.79 |
| **1000** | **5.91** | **0.58** | **1.67** | **0.0** | **0.58** |

p50/p95 across n=3 counts (not app-launch p50). **`AppDiagnostics.bootstrapStarted/Ready/Failed`** logs `durationMs`. **`AppReliabilityScaleTests` re-run this round: pass.** **Scratchpad opening / Home first-frame / search field latency on Release p50/p95 not independently re-measured.**

### Voice Capture model lifecycle (docs + Round3; not re-run full Release matrix)
- **Model size** 652,304,885 bytes; ~25 MB after load; peak ~59–77 MB; **released** on idle `retention`, memory pressure, sleep, disable, remove; **re-prepared** proactively after constraint; **CPU+ANE** default; CPU-only trade-off **Round3** (load 3.47 s vs 16.85 s; 157/168 identical; WER Δ small; WER ~+0.3–1.5 pts; not re-run); **CPU+GPU ~1 GB**; **not re-measured.**
- **Cold/warm** Round3 (signed study, not Release app): first external acquisition 23.42 s; first `MLModel.load` 16.56 s; warm-disk 333 ms + 140 ms; new signed process 333 ms + 75 ms; cold first capture ~13.85 s; post-idle reload 19.54 s vs 209 ms; probe 18.09 s first vs 201 ms; **needs Release + reproduction.** Round4 cold ~280 ms same-process; **not full-app cold.**
- **Batch 168-clip** Round3: ~681 MB RSS, ~77 MB peak footprint, 6.77 s user + 3.06 s sys; not leak proof; **not re-run.**
- **Round4 app-code eval:** separate process; footprint not separately captured per-clip; **not app UI.**
- **This phase's changes (#98/#99/#100) add negligible memory;** modifier monitor tiny; multi-selection O(selected) set; VoiceTextInsertion transient; no new model. **Not measured numerically.**

### Persistence (GRDB/SQLite; not re-run full perf this round)
- `AppReliabilityScaleTests` re-run pass. `NoteRepository.delete(ids:)` single transaction + atomic restore; `exportSnapshot`; FTS; **no DB reset**; migrations preserve; `AppDatabase`. M13A + tests. **Multi-select doesn't change DB schema.** No new persistence. **Batch discard = one transaction (new); not perf-measured.**

### Search (local FTS; not re-run perf this round)
FTS5 `unicode61(diacritics:.remove)`, prefixes 2/3/4; **no semantic/AI**; limit 500; Quick Search 12; Home `fetchAllNonDeleted` + group; M13A ~1.0→1.67 ms. **Home multi-selection doesn't re-fetch per selected.** **Not re-measured.**

### Refine
Existing `Evals/Refine/` + M13A + re-run smoke (Round4). **Release app Refine latency not re-measured;** on-device Foundation Models separate; no extra memory attributed; **not claimed.**

## Application states

| State | Evidence | Not measured |
|---|---|---|
| **Startup** | M13A bootstrap; `AppDiagnostics`; this-round idle 5 s | Release p50/p95 to first frame; cold disk |
| **Scratchpad open** | PanelController tests; Round3; M13A note-switch | Release p50/p95 |
| **Home** | M13A; HomeSnapshot/Home tests; multi-select tests | Release p50/p95; large-N render |
| **Search** | M13A; FTS tests | Release p50/p95; 500-cap |
| **Persistence** | scale tests; NOTE tests; batch txn | large DB; WAL |
| **Voice Capture** | Round3+4; lifecycle tests | physical mic; energy; lower-memory Mac |
| **Adaptive model lifecycle** | docs + lifecycle stress tests | full Release sleep/pressure on hardware |
| **Memory / CPU / energy / idle** | this-round idle 63 MB; Round3; M13A; **no energy** | long-running; other hardware; idle voice-on vs off p50 |
| **Resource reclamation** | voice release; `releaseAfterCapture`; tests | proof no leak; aux processes after |

## Not measured / cannot claim

- **Energy/Joules/thermal**; `powermetrics` privileges; Power Profiler. **"Idle 0% when hidden"** previously observed (Nov-3 audit, 0.1.3) but **not re-measured;** a prior `18% CPU idle` observation on 0.1.3 is **stale** and not current. **Don't claim.**
- **Other hardware** (M1/M4, 8 GB, Intel for app; Voice needs Apple silicon + macOS 26); **macOS 14** (Voice N/A); **memory-constrained**.
- **Long-running leak-freedom.** **Auxiliary processes** only transient XPC downloader; not measured. **Neural Engine residency** not apportioned.
- **Release p50/p95** broadly; this round Release idle single sample + M13A dev + Round3 signed study.
- **Auto-Keep** not in shipping. **No telemetry** (nothing to measure). **Network** none for recognition; model download measured Round3.

## Honest bottom line

Rasc is a **small native app + separate 622 MiB model**; **local SQLite; no background network; no telemetry; voice model reclaimed under pressure; fast persistence at 1k notes; verbatim voice ~sub-second warm on M3 Pro; Refine on-device separate.** We have **not** proven lower resource use than any competitor, **not** measured energy, **not** proven no leaks, and **not** reproduced cold-start p95 on Release at scale. Existing evidence is strong for *this* hardware + small app; reproduction scripts in repo.
