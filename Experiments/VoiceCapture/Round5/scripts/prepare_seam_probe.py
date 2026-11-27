#!/usr/bin/env python3
"""Make a disposable pinned FluidAudio checkout with trace and seam-order ablations."""
import io
import subprocess
import sys
import tarfile
from pathlib import Path

PIN = "386f7195670b77f2954c7ee143ec63fcb50b6c3b"
source, output = map(Path, sys.argv[1:])
output.mkdir(parents=True, exist_ok=False)
archive = subprocess.check_output(["git", "-C", str(source), "archive", PIN])
with tarfile.open(fileobj=io.BytesIO(archive)) as files:
    files.extractall(output, filter="data")

chunk = output / "Sources/FluidAudio/ASR/Parakeet/ChunkProcessor.swift"
contents = chunk.read_text()
original = """        if mergedTokens.count > 1 {
            mergedTokens.sort { $0.timestamp < $1.timestamp }
        }
"""
probe = r"""        let environment = ProcessInfo.processInfo.environment
        if environment["RASC_TRACE_CHUNKS"] == "1" {
            for (index, tokens) in (chunkOutputs + [mergedTokens]).enumerated() {
                let result = await manager.processTranscriptionResult(
                    tokenIds: tokens.map { $0.token },
                    timestamps: tokens.map { $0.timestamp },
                    confidences: tokens.map { $0.confidence },
                    tokenDurations: tokens.map { $0.duration },
                    encoderSequenceLength: 0,
                    audioSamples: [],
                    processingTime: 0
                )
                if let data = try? JSONEncoder().encode(result),
                   let json = String(data: data, encoding: .utf8) {
                    print("RASC_CHUNK \(index < chunkOutputs.count ? String(index) : "merged-before-sort") \(json)")
                }
            }
        }
        if environment["RASC_KEEP_TOKEN_ORDER"] == "1" {
            // Local adaptation of FluidAudio #830 for this pinned release.
            for index in mergedTokens.indices.dropFirst() {
                mergedTokens[index].timestamp = max(mergedTokens[index - 1].timestamp, mergedTokens[index].timestamp)
            }
        } else if mergedTokens.count > 1 {
            mergedTokens.sort { $0.timestamp < $1.timestamp }
        }
"""
assert contents.count(original) == 1
chunk.write_text(contents.replace(original, probe))
