#!/usr/bin/env bash
set -euo pipefail
probe="${1:?Signed VoiceStudy executable}"
out="${2:?Results directory}"
mkdir -p "$out"
for engine in ultra fluid; do
  for compute in neural gpu cpu all; do
    /usr/bin/time -l "$probe" --profile "$engine" "$compute" 2 1 mix-worker.wav \
      > "$out/$engine-$compute.jsonl" 2> "$out/$engine-$compute.resources"
  done
done
