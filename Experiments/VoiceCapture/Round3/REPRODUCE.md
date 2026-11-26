# Reproduce the signed study and tests

Use a fresh scratch directory and follow [Round 2’s dependency and asset staging commands](../Round2/REPRODUCE.md#build-the-signed-apps-and-prepare-fixtures) through initialization of the Swift build directory. This pins Rasc commit `250f1c1c82534bc69daad056fced69c083d298d7`, Swift 6.2 tooling, GRDB and KeyboardShortcuts, the FluidAudio fork at `386f7195670b77f2954c7ee143ec63fcb50b6c3b`, and the exact Core ML pack revisions. Round 3 uses the same package template and resolved transitive dependencies. Use a separate output for the regular app and the public-corpus benchmark.

```sh
lab="$PWD/Experiments/VoiceCapture"
round="$lab/Round3"
mkdir -p "$work/smoke" "$work/bench-fixtures"
cp "$work/synthetic/en-clip.wav" "$work/synthetic/pt-clip.wav" "$work/smoke/"

"$round/Study/build.sh" "$work/main" "$work/study-build" \
  "$work/Rasc Voice Capture.app" "$work/models" "$work/smoke"
binary="$work/Rasc Voice Capture.app/Contents/MacOS/VoiceStudy"
codesign --verify --deep --strict "$work/Rasc Voice Capture.app"
"$binary" --prepare en-US
"$binary" --prepare pt-BR
"$binary" --validate
open "$work/Rasc Voice Capture.app"
```

Opening the regular study uses its isolated container. The CLI validation creates temporary databases and touches no personal Rasc records. Apple preparation may download system-managed Speech assets. The portable packs arrive through the build step, which uses pinned hashes from the Round 2 downloader and signs the final assets into the final app. Keep diagnostic stdout local when testing human recordings.

## Extended held-out comparison

```sh
python3 "$round/Bench/stage-held.py" "$work/held" "$work/held-inputs.json"
cp "$work/held/"*.wav "$work/smoke/"*.wav "$work/bench-fixtures/"
"$round/Study/build.sh" "$work/main" "$work/study-build" \
  "$work/Voice Profile.app" "$work/models" "$work/bench-fixtures"
bench="$work/Voice Profile.app/Contents/MacOS/VoiceStudy"
"$bench" --prepare en-US
"$bench" --prepare pt-BR
python3 "$round/Bench/run-held.py" "$bench" "$work/held/manifest.json" "$work/raw-results"
python3 "$round/Bench/score-held.py" "$work/held" "$work/raw-results" "$work/scores"
mkdir -p "$work/alternate"
python3 "$round/Bench/check-fidelity.py" "$bench" "$work/held" \
  "$work/raw-results/fluid.jsonl" "$work/alternate" > "$work/alternate/parity.json"
```

`run-held.py` must finish all 168 cases per engine. For CPU WER, use the same scorer with the alternate CPU JSONL as `fluid.jsonl` and the Apple/Ultra controls copied from the original raw results. No public recordings or output text are included in this repository. Source inputs include NURC-SP terms (CC BY-NC-ND 4.0), AMI (CC BY 4.0) and the human-read CS-FLEURS subset (CC BY-NC 4.0). Research copies remain separate and private. Do not include the benchmark bundle in the personal test or distribute it. [Dataset hashes and indices](results/held-inputs.json) · [Tarsila](https://huggingface.co/datasets/nilc-nlp/TARSILA-ASR) · [AMI dataset](https://huggingface.co/datasets/edinburghcstr/ami) · [CS-FLEURS dataset](https://huggingface.co/datasets/byan/cs-fleurs)

## Model load and full workflow

Run these on a quiet machine, without other Core ML benchmarks running concurrently. Leave Core ML caches under OS control. Record model path, OS build, first or repeated process, and whether setup was performed. Initial parts can be fetched and verified with `/usr/bin/time -l python3 "$lab/Round2/stage-coreml.py" fluid-pro "$work/fresh-assets"`. The cache directory’s size can include other pack variants under the same identifier.

```sh
"$round/Bench/run-load.sh" "$bench" "$work/load"
"$binary" --profile fluid neural 1 0 en-clip.wav
"$binary" --lifecycle fluid 75 pt-clip.wav
"$binary" --workflow fluid auto 6 en-clip.wav
"$binary" --workflow ultra auto 6 en-clip.wav
"$binary" --workflow apple en-US 6 en-clip.wav
```

The in-app physical-input metadata harness is `--mic-probe` via LaunchServices. It requires a grant for that exact bundle identity and never copies audio from the input buffers. To repeat the already-authorized Round 1 reference, run [the Round 1 microphone probe](../README.md#reproduce) without `--request`. A pending permission is reported explicitly.

```sh
open -g -W -n -a "$work/Rasc Voice Capture.app" \
  --stdout "$work/device-microphone.jsonl" --args --mic-probe
```

The offline check should be run only when briefly disconnecting the named Wi‑Fi interface is expected. It restores Wi‑Fi before exit, checks macOS network state before and after inference, and uses its own independent control endpoint. Prepare the app’s Apple locales first. No speech is sent to the control.

```sh
"$round/Bench/offline.sh" "$binary" en0 "$work/disconnected-network.txt"
```

## Native screenshots and recording

`--visual` captures the signed app’s own native view tree using two appearances and window widths and a disposable database. It prints the sandbox-temporary output directory. The continuous sequence is encoded from the frames. These are actual view renders with a synthetic input, not composited recordings of other apps.

```sh
"$binary" --visual > "$work/visual-output.txt"
folder="$(sed -n 's/^Visual output //p' "$work/visual-output.txt")"
ffmpeg -framerate 12 -i "$folder/frames/frame-%04d.png" \
  -vf "scale=1104:-2" -c:v libx264 -crf 18 -pix_fmt yuv420p \
  -movflags +faststart "$work/capture-review-keep.mp4"
```

For distribution, the [Round 2 Sparkle fixture and instructions](../Round2/REPRODUCE.md#repeat-the-sparkle-permission-test) reproduce the genuine isolated update. A Developer ID comparison needs a suitable locally available signing identity and a release-authorized test. The production feed is outside both fixtures.
