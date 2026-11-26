# Reproduce the November 24 study

Use a scratch directory outside the repository. The build uses macOS 26 and Xcode 26.2, Swift 6.2.3, Python 3.14 for file tools, Python 3.13 for MLX, FFmpeg, and the same built-in voices as Round 1. Keep staged speech and raw public-source transcripts local. NURC-SP clips retain their source terms (CC BY-NC-ND 4.0); the study uses them privately and does not redistribute audio, transcript content or edited copies. LibriSpeech uses CC BY 4.0. The project includes only audio hashes and aggregates for the public speech. The upstream datasets-server can return temporary errors for a fresh stage. An existing private stage is verified against the archived hashes without network access. See the pinned upstream files for terms and attribution. [Tarsila](https://huggingface.co/datasets/nilc-nlp/TARSILA-ASR) · [NURC-SP license and data](https://huggingface.co/datasets/nilc-nlp/CORAA-NURC-SP-Audio-Corpus) · [LibriSpeech](https://www.openslr.org/12)

## Build the signed apps and prepare fixtures

From the Rasc checkout root, in Bash:

```sh
lab="$PWD/Experiments/VoiceCapture"
round="$lab/Round2"
work="$(mktemp -d /tmp/rasc-voice-r2.XXXXXX)"
git worktree add --detach "$work/main" 250f1c1c82534bc69daad056fced69c083d298d7

xcodebuild -resolvePackageDependencies -project "$work/main/Rasc.xcodeproj" \
  -scheme Rasc -clonedSourcePackagesDirPath "$work/packages"
git -C "$work/packages/checkouts/GRDB.swift" rev-parse HEAD
git -C "$work/packages/checkouts/KeyboardShortcuts" rev-parse HEAD
# b83108d10f42680d78f23fe4d4d80fc88dab3212 and 49c3fc04ea827f816df67843bfcc57286b47ff06

fork=386f7195670b77f2954c7ee143ec63fcb50b6c3b
mkdir -p "$work/deps" "$work/study-build/Sources" "$work/results" "$work/assets" "$work/smoke"
curl -fsSL "https://codeload.github.com/altic-dev/FluidAudio/tar.gz/$fork" -o "$work/fluid-audio.tar.gz"
tar -xzf "$work/fluid-audio.tar.gz" -C "$work"
ln -s "$work/FluidAudio-$fork" "$work/deps/FluidAudio"
ln -s "$work/packages/checkouts/GRDB.swift" "$work/deps/GRDB.swift"
ln -s "$work/packages/checkouts/KeyboardShortcuts" "$work/deps/KeyboardShortcuts"
cp "$round/Study/Package.swift.template" "$work/study-build/Package.swift"
cp "$round/Study/StudyPackage.resolved" "$work/study-build/Package.resolved"

for model in fluid-pro ultra nemotron; do
  python3 "$round/stage-coreml.py" "$model" "$work/models"
done
python3 "$lab/make-fixtures.py" "$work/synthetic"
python3 "$round/stage-human.py" "$work/human"
cp "$work/synthetic/"*.wav "$work/human/"*.wav "$work/assets/"
cp "$work/synthetic/en-clip.wav" "$work/smoke/"

"$round/Study/build.sh" "$work/main" "$work/study-build" \
  "$work/Rasc Voice Benchmark.app" "$work/models" "$work/assets"
"$round/Study/build.sh" "$work/main" "$work/study-build" \
  "$work/Rasc Voice Study.app" "$work/models" "$work/smoke"

probe="$work/Rasc Voice Benchmark.app/Contents/MacOS/VoiceStudy"
"$probe" --prepare en-US
"$probe" --prepare pt-BR
"$probe" --validate
```

Only the user-study bundle should be used interactively. It contains a synthetic smoke fixture, not public speech. For another build, use a fresh output path so that regenerated assets cannot be confused with assets from the previous copy. The pinned study build disables app networking, uses local artifacts, and has its own TCC identity and separate container. Direct fixture invocation avoids the live mic and uses a temporary database. macOS can download Speech assets during `--prepare`. [Study code](Study/) · [Exact model pack revisions and hashes](results/model-lock.json)

## Benchmarks and scoring

```sh
python3.13 -m venv "$work/mlx"
"$work/mlx/bin/python" -m pip install -r "$round/results/mlx-requirements.txt"
for model in qwen06 qwen17 granite; do
  "$work/mlx/bin/python" "$round/stage-mlx.py" "$model" "$work/models"
done

python3 "$round/run-bench.py" --study "$probe" --python-mlx "$work/mlx/bin/python" \
  --models "$work/models" --fixtures "$work/assets" --synthetic-manifest "$work/synthetic/manifest.json" \
  --human-manifest "$work/human/manifest.json" --output "$work/results" \
  --split screen apple fluid ultra granite qwen06 qwen17
python3 "$round/run-bench.py" --study "$probe" --python-mlx "$work/mlx/bin/python" \
  --models "$work/models" --fixtures "$work/assets" --synthetic-manifest "$work/synthetic/manifest.json" \
  --human-manifest "$work/human/manifest.json" --output "$work/results" \
  --split held apple fluid ultra granite qwen17
```

For Nemotron, run the Round 1 FluidAudio manifest helper in a fresh scratch directory (v0.18.4, source commit `e0c6103bc87a88d25276cad491c86e757f58c865`). In that disposable copy replace `Probe/Sources/main.swift` with [Round 2 Probe.swift](Nemotron/Probe.swift), then rebuild with `swift build --package-path "$work/nemotron-src/Probe" --scratch-path "$work/nemotron-src/build" -c release`. SwiftPM otherwise resolves an unused text-processing binary which the manifest helper omits. The decode implementation is upstream. Core ML pack uses Latin 560 ms, exact revision and bytes in the model lock. Warm cache policy and compute settings are runtime defaults.

```sh
"$lab/Parakeet/build-without-unused-artifact.sh" "$work/nemotron-src"
cp "$round/Nemotron/Probe.swift" "$work/nemotron-src/Probe/Sources/main.swift"
swift build --package-path "$work/nemotron-src/Probe" --scratch-path "$work/nemotron-src/build" -c release
"$round/Nemotron/run-signed.sh" "$work/nemotron-src/build/release/ParakeetProbe" \
  "$work/models/nemotron" "$work/synthetic" "$work/nemotron" batch auto \
  $(cd "$work/synthetic" && printf '%s\n' *.wav) \
  > "$work/results/nemotron-synthetic.jsonl" 2> "$work/results/nemotron-synthetic.stderr"
"$round/Nemotron/run-signed.sh" "$work/nemotron-src/build/release/ParakeetProbe" \
  "$work/models/nemotron" "$work/synthetic" "$work/nemotron" paced auto en-clip.wav pt-clip.wav mix-worker.wav
```

For full Whisper-v3, use the Round 1 [whisper.cpp v1.9.6 build](../README.md#reproduce). Stage the exact Large-v3 Q5_0 GGML checkpoint described in the model lock, verify its SHA-256, and pass it to `run-whisper.py` instead of Turbo. The report used the fixed-locale outputs and standard greedy Metal configuration. Normalize the output for the combined scorer:

```sh
asset_revision=5359861c739e955e79d9a303bcbc70fb988958b1
asset="$work/ggml-large-v3-q5_0.bin"
curl -fsSL "https://huggingface.co/ggerganov/whisper.cpp/resolve/$asset_revision/ggml-large-v3-q5_0.bin" -o "$asset"
printf '%s  %s\n' d75795ecff3f83b5faa89d1900604ad8c780abd5739fae406de19f23ecd98ad1 "$asset" | shasum -a 256 -c -
python3 "$lab/run-whisper.py" "$work/whisper-build/WhisperProbe" "$asset" "$work/synthetic" "$work/whisper-results"
jq -c '.engine = "whisper-v3"' "$work/whisper-results/whisper-batch.jsonl" > "$work/results/whisper-v3-synthetic.jsonl"
cp "$work/whisper-results/whisper-batch-resources.txt" "$work/results/whisper-v3-synthetic.stderr"

python3 "$round/score-round2.py" "$work/results" "$work/synthetic/manifest.json" \
  "$work/human/manifest.json" "$work/assets" > "$work/summary.json"
python3 "$round/paired-holdout.py" "$work/results" "$work/human/manifest.json" > "$work/paired-holdout.json"
```

For the smaller supplement, stage [supplement.json](supplement.json) as `corpus.json` next to a temporary copy of the Round 1 generator and run it with a separate output directory. Build a signed study fixture with those two WAV resources and run `--benchmark` for Apple pt-BR, Fluid and Ultra. For the Cohere probe, use [speech-swift v0.0.29](https://github.com/soniqo/speech-swift/releases/tag/v0.0.29), stage Cohere with `stage-mlx.py`, and use `speech transcribe … --backend cohere --model-dir …` for the same `pt-clip.wav` in auto and `--language pt`. Use the command’s local help to verify flag spelling on other builds. The matched benchmark contains no Cohere rows. [Original logs](results/synthetic-results.jsonl) · [Cohere output](results/cohere-smoke.txt)

The public dashboard extraction script reads live data. Its snapshot date annotates the archived run. Save a fresh result to a new path to compare ranks later. A regression harness should keep held references and raw human transcripts out of source control.

## Repeat the Sparkle permission test

On the same Mac and an isolated bundle, run `Sparkle/build-pair.sh "$work/main" "$work/update-probe" /path/to/Sparkle-2.9.4/bin`. It creates a disposable feed key. Use the matching Sparkle release tools and Homebrew OpenSSL 3. Keep the key outside the repository. Host only that directory using `python3 -m http.server 18589 --bind 127.0.0.1 --directory "$work/update-probe/feed"` in a separate terminal and stop it after the trial. Verify both bundle requirements and the feed signature.

- Launch the fresh installed fixture using `open -W -n -a "$work/update-probe/install/Rasc Voice Update Probe.app" --args --request` and allow the contextual permission when you are testing the grant path. The code only queries authorization, it does not record.
- Copy the authorized build 1 bundle to a scratch path for the controls. Launch the installed bundle with `--upgrade` through LaunchServices. The probe installs the signed ZIP and relaunches. Read the fixture container’s `Library/Application Support/Rasc Voice Update Probe/events.txt`. A line at launch identifies the bundle version and grant state.
- Test a standalone relocated build 1, then move aside the updated fixture and reinstall the preserved exact build 1 at the original test path. Check its designated requirement and authorization after launch. Use a disposable account for explicit denial, reauthorization, and Developer ID comparisons so existing grants do not mask the result.

The production Rasc feed, signing profile and application are outside this experiment. [Probe](Sparkle/) · [Measured event trace](results/sparkle-events.txt)
