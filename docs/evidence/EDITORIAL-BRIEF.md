# Editorial and asset brief for rasc-web

Lead with capture, optional editing and getting back to work. Use native Light and Dark screenshots and show Keep in copper. The historical PNGs use synthetic notes. Refer to the manifest for visual provenance and to the final reliability notes for current behavior. [Screenshot manifest](screenshots/manifest.json)

| Section | Assets and evidence | Suggested framing |
|---|---|---|
| Capture | `scratchpad-text-light.png`, `scratchpad-text-dark.png`, efficiency `operation_latencies_ms` | Local scratchpad, no account. Use the named software endpoint if giving a latency. |
| Keep and retrieve | `home-list-light.png`, `home-batch-light.png`, `quick-search-grat-light.png`, efficiency `scale_benchmark_1k_5k` | Home and search in the tested 5,000-note database. Keep measured SQLite search separate from UI timing. |
| Voice and Dictate | `voice-hud-listening-dark.png`, `onboarding-v2-voice-light.png`, voice `paired_corpora` and `final_reliability` | On-device dictation with an opt-in 622.09 MiB pack. Label model latency and word error rate by engine, corpus and machine. The isolated candidate has a temporary 120 s cap. Link the coverage findings if showing 300 s laboratory probes. |
| Listen to examples | `examples/examples.json` and the five listed WAVs | Human reference and raw engine hypothesis. Include the near-match, missing token and proper-name cases beside the clean example. Use only the publication allowlist. |
| Refine | `refine-preview-suggested-light.png`, `refine-preview-changes-dark.png`, `examples/refine_examples.json` | A before/after edit the author can accept or discard. Label historical generated outputs and show limitations alongside objective scores. Use the final intent study for current prompt handling. |
| Energy and memory | Efficiency `before_vs_after`, `long_running_20261126` | Show like-for-like accelerated workday results separately from the earlier long-run trace. Label **8.00 h wall / 4.33 h active** and **8.50 h observed / 24 h planned**. Report physical footprint, RSS, neural footprint and XNU CPU energy separately. |
| Download and trust | Efficiency `storage_distinction`, release docs | Label the compressed DMG, installed bundle and optional model separately. Use the published artifact for the download. Explain ad-hoc signing and use the corresponding checksum and macOS install guidance. |

For the engine chart, group by corpus on one tested Mac. The historical FLEURS set contains one duplicate WAV. Long-form stitched diagnostics deserve a separate coverage chart. Use the nearest-rank latency convention and link to the exact endpoint definitions. Commercial application names belong in a separate landscape section with their own sources and methodologies.

Use the Refine examples as text diffs. Include attribution whenever the original derives from FLEURS, indicate processing or editing, and identify historical outputs that failed the copyediting intent. Avoid republishing restricted transcripts, prompts, hypotheses and clips. [Example allowlist](examples/ATTRIBUTION.md)
