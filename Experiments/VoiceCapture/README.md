# Voice Capture lab

The signed personal-testing build, expanded holdout, offline test and release gates are in [Round 3](Round3/README.md).

For the November follow-up with expanded ASR benchmarks, a usable native study app and the Sparkle signature experiment, see [Round 2](Round2/README.md).

An isolated Voice Capture study for Rasc. [Decision and design assessment](ASSESSMENT.md) · [Competitive and engine research](RESEARCH.md) · [Raw evidence](results/) · [Synthetic fixture inputs](corpus.json)

The shipping app has no new target, permission, dependency or UI from this study. Probe apps use research bundle IDs and temporary or sandboxed data. The microphone probe reports format, buffer timing and frame counts. It drops every sample without writing or transcribing it.

## What ran

On 2026-11-24, Apple M3 Pro, Mac15,6, 18 GB RAM, macOS 26.5.1 (25F80), Xcode 26.2/SDK 26.2 and Swift 6.2.3. Rasc source baseline is `250f1c1c82534bc69daad056fced69c083d298d7`. The shared scheme built. The first test-runner launch with the default bundle ID failed at LaunchServices. The isolated bundle rerun passed **538 tests across 52 suites**. The domain fallback passed 494 tests and a separate scale suite with three cases. [Environment](results/environment.txt) · [Baseline results](results/rasc-baseline.txt)

- Signed, sandboxed Apple SpeechAnalyzer probe with both native modules, fixed en-US or pt-BR locale, progressive presets, local asset inventory, paced inputs at 100 ms increments and independently collected final segments. Whisper and Parakeet used sandboxed, ad-hoc signed, hardened-runtime binaries with local weights and no microphone permission. Apple used the microphone entitlement and no network-client entitlement. The US English/Brazilian Portuguese capabilities in legacy SFSpeechRecognizer were visible as on-device-ready, while the legacy speech permission was still undetermined. No legacy recognition request was made.
- 23 unique 16 kHz mono synthetic WAV inputs. Twenty speech cases cover English, Brazilian Portuguese and code-switching. Three controls cover digital silence, colored noise and a short click. Samantha and Luciana synthesize most examples at 173 wpm. The separate sentence-switch fixture uses both voices, so it does not test one person's intra-sentence pronunciation. Pauses are 0.45–1.6 seconds. Noise is colored and approximately 13 dB SNR by whole speech clip RMS. Silence and noise fixtures are digitally generated. Boundary stress versions strip the usual 150/200 ms leading/trailing guard and trim below a fixed PCM threshold.
- All four engines received identical files. The Apple streams were clocked at their source sample rate and took about 138 seconds across both locales per engine. Whisper was local Metal, greedy, no cross-fixture context, no VAD. Parakeet was Core ML TDT v3 batch with default processor policy, a fresh decoder state per file and no language hint. Whisper `auto` ran five extra checks outside the main comparison. Reference words, sample hashes and raw outputs are preserved.
- The screen prototypes use Rasc's actual theme and style sources and a simulated state machine. The probe ordered a non-key AppKit panel in front with the original foreground PID unchanged 150 ms later. The panel reported visible and never key at that point. Ordering took 12.9 ms in one trial. This did not measure delivered shortcut → composited frame or full-screen coverage. [Panel output](results/nonactivating-panel.txt)
- The repository test used the actual Rasc data model and an isolated SQLite DB. It verified concurrent replay of one ID, FTS, visibility after commit through a second connection, a preserved active note ID and original contents, blank/collision rejection, induced write failure and retry, and soft discard/restore. With 50 serial inserts, commit p50 was 0.39 ms, p95 0.69 ms, max 0.76 ms. Those are warm local repository timings, independent of end-to-end UI or ASR. [Persistence output](results/persistence.txt)

## Quality and timing

WER is case-folded Unicode word edit distance, with punctuation dropped, accents preserved and no special equivalence rules for numerals, format or spelling. For example, “twenty-third” and “23rd” count differently. English has 9 items, Portuguese 8 and mixed 3. Raw WER is useful for finding errors, while a human scores semantic preservation separately. Results describe this synthetic set.

| Engine | WER EN | WER pt-BR | WER mixed | WER overall | Short Finish p50 / p95 | Nonempty on no-speech |
|---|---:|---:|---:|---:|---:|---:|
| SpeechTranscriber | 13.9% | 5.9% | 21.3% | 12.4% | 86 / 130 ms | 0/3 |
| DictationTranscriber | 22.8% | 52.1% | 77.0% | 42.9% | 54 / 121 ms | 0/3 |
| Whisper large-v3-turbo Q5_0 | 14.6% | 9.2% | 14.8% | 12.7% | 798 / 1,245 ms | 3/3 |
| Parakeet TDT v3 | 12.7% | 13.5% | 18.0% | 13.9% | 45 / 57 ms | 0/3, with one short-input error |

Each short group has 12 speech cases at or below six seconds. For Apple, Finish measures stop of the synthetic feed through final result iterator completion. For the two batch engines it measures read/decode through result with a loaded context, including the first inference in the process. Neither includes final UI or database commit. Percentiles use the nearest-rank method for p95. With a 12-case group, p95 is the highest observation. See [calculated summary](results/summary.json) and [scoring code](score.py).

### Semantic review of representative errors

| Fixture | What matters | Actual observations |
|---|---|---|
| English uncertainty and long pause | Preserve “maybe,” “not entirely sure,” reasons and conditions. | The strongest three retained the central uncertainty and conclusion. Dictation dropped some filler and changed formatting, though the running English example remained readable. |
| “A Lívia … João Siqueira em Fortaleza” | Preserve people, location, date and time. | Speech preserved all these terms. Dictation retained only “A Livia vai encontrar.” Whisper fused the first name and article and heard “e Fortaleza.” Parakeet also heard “e Fortaleza,” changing the role of the place. |
| Portuguese moderate noise | Preserve the current uncertainty. | Speech changed “não tenho certeza” into “não vou ter certeza,” shifting from present uncertainty to a future claim. Dictation and Parakeet used “não temos certeza.” Whisper added an extraneous article but retained first-person uncertainty. |
| Portuguese short negation with tight boundary | Preserve the first word “Não” and the last word. | Speech and Whisper kept both ends on all four short ordinary/tight Portuguese and English fixtures. Parakeet kept the first and last words and added an article inside both Portuguese clips. Dictation lost “Não” on the tight Portuguese clip and “yet” on the tight English clip. Batch replay reproduced both losses. These were file boundaries, not acoustical hardware clipping tests. |
| Mixed worker/deploy sentence | Preserve “race condition,” “worker,” “deploy,” and “não sei.” | Speech output “Race condiam” and “Orquê,” and the negated clause was damaged. Dictation returned only “Precisamos.” Whisper and Parakeet retained the main claim and technical terms here, with a smaller grammatical deviation. |
| Mixed SQLite/fallback/rollback | Preserve the product name and all three technical terms. | Every candidate corrupted at least one. Speech produced “SQ Elite,” “Fabak,” and “Hbaki.” Parakeet and Whisper recognized the surrounding argument but still garbled technical terms. |
| Sentence switching | Preserve the English instruction and the Portuguese hesitation after it. | Whisper and Parakeet retained “Don't retry the job before the time out” with minor formatting while still mishearing a surrounding word. Speech garbled the English phrase. Dictation omitted it. Whisper auto-mode did not improve the tested mixed examples. |
| Numbers, names and URL | Preserve numeric values and names even when punctuation changes. | Speech and Parakeet preserved 2.0.7, 403 and 180 ms. Whisper rendered 403 as 4.03. The proper-name case included “Maya Chen” becoming “Maria Jen” (Dictation), “Mai Ye Chen” (Whisper), or “my Yu Chen” (Parakeet). All four mishandled the spoken URL's path/query. Do not infer a replacement URL from text. |
| No speech | No note. | Both Apple modules returned empty for all three controls. Parakeet returned blank for silence/noise and invalidAudioData for the click-only 270 ms clip. Whisper emitted “Thank you.”, “I'm going to go.” and “E aí” in the fixed-locale test without VAD. Auto mode emitted “Thank you.” on the click. |

A targeted native context check supplied the exact fixture terms as general AnalysisContext strings. All three mixed transcripts and the clean Portuguese control were text-identical to their unhinted results. This probes one contextual API and configuration, rather than every vocabulary adaptation. [Hints run](results/apple-fixture-hints.jsonl)

Warm finish time alone is insufficient for product choice. Model behavior on these voices includes TTS pronunciation and text normalization, and the study cannot rank approaches on real accents or an open-ended variety of thoughts. The Apple result also does not promise stable word-for-word output across OS-managed model updates.

### Startup, microphone, lifecycle and resources

| Probe | Observation and limit |
|---|---|
| Apple analyzer preparation and first partial | Speech first-clip prepare in each locale process took 83 and 126 ms. Full ready measurement including module/format checks was 89 and 134 ms. Later sessions in the same processes became ready in 26–45 ms. Speech first result p50/p95 was 1,124/1,128 ms from the start of the paced feed and all 20 speech inputs had provisional output. Dictation often returned earlier, but its first-result p95 was 6,816 ms across speech clips and it lost content. True cold boot and model eviction were unverified. |
| Mic readiness | 15 native AVAudioEngine runs of the default 48 kHz mono route, independently identified as built-in later in the same session. Requested tap size 512 frames and observed 4,800 frames on all first callbacks. The first probe took 350 ms to a buffer. Subsequent 14 took 187 ms p50, 214 ms p95. Engine.start returned sooner, 81 ms p50 across all trials. This does not establish acoustical word boundaries, physical shortcut latency or runtime hardware-specific format guarantees. |
| Conversion | A separate paced 48 kHz fixture used AVAudioConverter to produce 16 kHz Int16. The same 1.388 s fixture produced 22,100 frames without a drain and all 22,203 expected frames with normal priming and end-of-stream drain. Both returned “Don't deploy yet.” The 103-frame difference is 6.4 ms at 16 kHz, illustrating why the tail must be accounted for. Both were file feeds. Route switching and live shutdown remain unqualified. |
| Apple asset behavior | Both language families appeared installed in runtime inventory. For SpeechTranscriber, per-module status initially reported supported, then installed after an explicit request. It took approximately 1.51 s EN and 1.37 s pt-BR on this provisioned Mac. This demonstrates readiness handling with existing OS files, not a clean download. A supported-but-uninstalled German module failed closed on reaching the batch path. No German model was requested. An ambient asset inventory's installed locales cannot replace module readiness. |
| Apple cancel | Synthetic feed stopped around 500 ms during an ongoing sample. Cancel returned in 0.12 ms. A second run triggered cancel roughly 15 ms after starting finalization and returned total 15.66 ms from stop, including the intentional wait. Both discarded output. A later independent session transcribed successfully. In a third check, the prepare task returned success after cancellation was requested, and joining cleanup took 61 ms. The coordinator must independently recheck session generation even if an awaited preparation returns successfully. Real asset-download cancellation and abandoned user speech recovery remain open. |
| Client CPU and memory | Apple SpeechTranscriber process peak RSS was about 20 MB, with 0.56 s user + 0.17 s sys for the 62.84 s EN suite. Dictation was about 20 MB RSS as well. Apple recognition runs out of process, and those figures miss its system resource use. A parked test process with no active microphone or model used 0.29 ms CPU over 5.32 s and 9.7 MB max RSS. The idle shipping app and speech service residency remain unmeasured. |
| Whisper model and compute | 574,041,195-byte model. A first process loaded in 5.09 s. Later processes loaded in 0.22–0.24 s after OS/Metal caches had a chance to warm. The bundle used Metal on M3 Pro. Max process RSS about 825 MB. EN elapsed 17.98 s including initial load, 0.34 s user + 0.26 s sys excluding GPU work. Five selected clips in auto mode took about 1.53–1.64 s each after load and did not rescue the mixed errors. |
| Parakeet model and compute | 483,105,645-byte staged model. Setup and configure took 18.31 s initially and 20.87 s in a repeat process. Compare that with a short warm batch p95 of 57 ms. The current setup is unsuitable to repeat every time the user speaks. Peak process RSS 500 MB, with 66 MB peak memory footprint reported separately by macOS. CPU measured 2.87 s user + 1.08 s sys over 23.15 s. Default Core ML policy uses CPU/ANE as defined upstream. Neither compute-unit residency nor power was measured. |
| TCC / release proxy | The optimized sandboxed bundle requested microphone access through LaunchServices by explicit command and was granted. Same bundle ID/path/entitlements with a re-signed CFBundleVersion differing in CDHash returned not determined and read no audio. The test restored its original bundle afterward. This is a real fixture transition, with no production signing or Sparkle updates. Explicit Deny/revoke, device busy/disconnect, Bluetooth, actual sleep/lock, real updater and network-disconnected runs are still open. |

Potential targets on this hardware are believable for a prepared native path. A single panel order call is below 100 ms but does not prove on-screen acknowledgment. The repeated mic path meets 300 ms, while the first trial misses it. The native synthetic Finish and the separate local commit leave headroom under one second. The physically measured end-to-end path still needs a cold and warm test as one chain. Batch Parakeet is very fast after load with poor measured setup latency. Avoid retaining a heavy model indefinitely to disguise initialization.

[Raw Apple data](results/speech-paced.jsonl) · [Dictation](results/dictation-paced.jsonl) · [Whisper](results/whisper-batch.jsonl) · [Parakeet](results/parakeet-batch.jsonl) · [Mic timings](results/microphone.jsonl) · [Cancellation](results/apple-cancellation.jsonl) · [Input conversion](results/apple-resample.jsonl) · [Before replacement](results/mic-original-signature.jsonl) · [After replacement](results/mic-updated-signature.jsonl)

### Native design and shortcuts

[Light concepts](design/concepts-light.png) · [Dark concepts](design/concepts-dark.png) · [Light journey](design/journey-light.png) · [Dark journey](design/journey-dark.png)

The lab picker previews setup, preparing language, mic startup, recording, finishing, writing, Kept, optional Open/Undo, cancelled, silence, permission off, unsupported machine, interrupted recording, transcription retry and persistence retry. Native buttons and labels are illustrative. The non-key panel experiment has no mic and does no persistence. The menu-bar concept is a rendering, with no permanent status item. Progress and the duration are simulated. Theme and appearance selectors are lab controls.

KeyboardShortcuts 3.0.1 compiled and reported its test binding registered in the sandboxed lab. Attempts to post the chord synthetically through Core Graphics produced no package callbacks. This is inconclusive for physical input. Manual keyboard testing remains open for tap, hold, repeat, modifier-first release, menu tracking, focus, reserved shortcuts and cancellation. [Pinned source](https://github.com/sindresorhus/KeyboardShortcuts/tree/49c3fc04ea827f816df67843bfcc57286b47ff06) · [Synthetic test trace](results/keyboard-registered-no-callbacks.txt)

Unresolved release-equivalent validation includes natural EN/pt-BR/mixed speech, acoustical boundaries and real input startup from a shortcut, a clean-model download and failure/cancellation mid-download, offline daemon behavior, device switching, Bluetooth, contention and sleep. Native checks still include full VoiceOver, Full Keyboard Access, keyboard layouts, fullscreen display and Spaces/Stage Manager. An actual denied or revoked system permission was not induced. See the [acceptance gates](ASSESSMENT.md#9-proposed-acceptance-gates).

## Reproduce

From the Rasc checkout. Use fresh paths and Xcode 26.2+, FFmpeg, CMake and Python 3.

```sh
lab="$PWD/Experiments/VoiceCapture"
work="$(mktemp -d /tmp/rasc-voice-reproduce.XXXXXX)"
git worktree add --detach "$work/main" 250f1c1c82534bc69daad056fced69c083d298d7

python3 "$lab/make-fixtures.py" "$work/fixtures"
mkdir -p "$work/results"
cp "$work/fixtures/manifest.json" "$work/results/fixture-manifest.json"

"$lab/build-probe.sh" "$work/AppleVoice.app" "$work/fixtures"
apple="$work/AppleVoice.app/Contents/MacOS/VoiceProbe"
"$apple" inventory
# Explicit setup only. The OS may download missing language files.
for engine in speech dictation; do
  for locale in en-US pt-BR; do "$apple" install "$engine" "$locale"; done
done
python3 "$lab/run-apple.py" "$work/AppleVoice.app" "$work/fixtures" "$work/results"

"$apple" cancel speech pt-BR @pt-thinking.wav
"$apple" cancel-final speech en-US @en-uncertain.wav
"$apple" cancel-prepare speech en-US
"$apple" hints speech pt-BR @mix-worker.wav @mix-sql.wav @mix-switch.wav @pt-maybe.wav
"$apple" idle

# Ask only for the isolated bundle's mic permission. No samples are kept.
open -W -n -a "$work/AppleVoice.app" --stdout "$work/results/microphone.jsonl" \
  --stderr "$work/mic-errors.txt" --args mic --request 15
```

The first mic argument without `--request` queries authorization and only runs if already granted. For the two-bundle TCC test, copy the authorized fixture, bump `CFBundleVersion` with PlistBuddy, and re-sign using the same build script's `codesign` flags and entitlements. Verify each `codesign -d -r-` requirement, swap the bundles at the same test path, and launch with `mic 1` without `--request`. Restore the original fixture afterward. Use a disposable test account for repeated grant, deny and revoke scenarios. A permission grant applies to the research bundle. The test does not reset macOS permissions.

To repeat conversion independently, ffmpeg the short EN file to 48 kHz, rebuild the Apple bundle with that file in the fixture folder, and pass its absolute resource path to `resample`. `batch` and `paced` can use names prefixed with `@` for fixture resources, or an accessible absolute file path. Use resample-drain for the second variant with normal priming and end-of-stream signaling. These are file fixtures. A synthetic file in the other probe bundle failed to open with Core Audio error −54, so use resources staged in the same bundle for runs. Hardware drain still needs a live test.

```sh
git clone --depth 1 --branch v1.9.6 https://github.com/ggml-org/whisper.cpp.git "$work/whisper.cpp"
git -C "$work/whisper.cpp" rev-parse HEAD
# Expected 96ec4d9823e9d0211944172da35f9f29134af990 (the tag is annotated).
cmake -S "$lab/Whisper" -B "$work/whisper-build" -DCMAKE_BUILD_TYPE=Release \
  -DWHISPER_SOURCE="$work/whisper.cpp"
cmake --build "$work/whisper-build" --target WhisperProbe -j 5
model="$work/ggml-large-v3-turbo-q5_0.bin"
curl -fL 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin?download=true' -o "$model"
printf '%s  %s\n' 394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2 "$model" |
  shasum -a 256 -c -
python3 "$lab/run-whisper.py" "$work/whisper-build/WhisperProbe" "$model" "$work/fixtures" "$work/results"

python3 "$lab/Parakeet/stage-model.py" "$work/parakeet-model"
swift build --package-path "$lab/Parakeet" --scratch-path "$work/parakeet-build" -c release
"$lab/Parakeet/run-signed.sh" "$work/parakeet-build/release/ParakeetProbe" \
  "$work/parakeet-model" "$work/fixtures" "$work/results"
python3 "$lab/score.py" "$work/results" > "$work/results/summary.json"
```

For the measured Parakeet build, SwiftPM tried to resolve an unrelated NeMo text-processing binary artifact even with traits disabled. The probe was built using the same pinned FluidAudio tag/commit after removing the disabled artifact declaration and conditional manifest reference in a disposable upstream copy. No engine source or configuration changed. The helper below reproduces that manifest path. The normal SwiftPM manifest remains available. Parakeet TDT v3 weights are CC BY 4.0 and attributed to NVIDIA. The Core ML conversion is attributed to FluidInference. FluidAudio is Apache-2.0. Whisper weights and runtime are MIT. The assets themselves are downloaded separately. [FluidAudio license](https://github.com/FluidInference/FluidAudio/blob/v0.18.4/LICENSE) · [Parakeet model card](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3) · [Converted models](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml) · [Whisper model card](https://huggingface.co/openai/whisper-large-v3-turbo)

```sh
"$lab/Parakeet/build-without-unused-artifact.sh" "$work/parakeet-source-build"
"$lab/Parakeet/run-signed.sh" "$work/parakeet-source-build/build/release/ParakeetProbe" \
  "$work/parakeet-model" "$work/fixtures" "$work/results"

# Native, interactive mockups using baseline Rasc palette sources.
"$lab/design/build-design.sh" "$work/main" "$work/VoiceDesign.app" "$work/design-build"
open "$work/VoiceDesign.app"
# The signed renderer can write to its own research container.
"$work/VoiceDesign.app/Contents/MacOS/VoiceDesign" --render @container
# Isolated non-activating-window check.
open -g -W -n -a "$work/VoiceDesign.app" --stdout "$work/focus.txt" --args --focus-smoke

# Shared scheme and persistence probe using its pinned GRDB checkout.
xcodebuild -project "$work/main/Rasc.xcodeproj" -scheme Rasc -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$work/rasc-build" \
  -parallel-testing-enabled NO CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= \
  PRODUCT_BUNDLE_IDENTIFIER=com.rasc.research.voice.baselinetest test
"$lab/Persistence/run.sh" "$work/main" "$work/rasc-build/SourcePackages/checkouts/GRDB.swift"
```

Synthetic rerenders are equivalent only on a machine using the same TTS voices/versions, generator, FFmpeg conversion and OS speech assets. The raw SHA-256 manifest records the exact original run's audio. Apple model binaries and system versions can change independently. Treat these measurements as observations for the stated date and machine.
