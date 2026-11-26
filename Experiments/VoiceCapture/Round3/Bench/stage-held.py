#!/usr/bin/env python3
"""Stage a new, fixed holdout outside the repo. Never redistribute speech or references."""
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import subprocess
import sys
from urllib.parse import urlencode

HUB = "https://huggingface.co"
ROWS = "https://datasets-server.huggingface.co/rows"
TARSILA = ("nilc-nlp/TARSILA-ASR", "2785788cf674adc35caf83c297942dab3592a1b8")
AMI = ("edinburghcstr/ami", "46f28f2503e2ec48f8867a84eef356c70476beab")
CS_FLEURS = ("byan/cs-fleurs", "0cdbf166c5517ae4b6eb1c54248522eedec53017")


def fetch(url, target=None):
    cmd = ["curl", "-fsSL", "--retry", "3", "--max-time", "30", url]
    if target is not None:
        subprocess.run([*cmd, "-o", target], check=True)
        return None
    return subprocess.check_output(cmd)


def block(source, config, offset):
    repo, revision = source
    params = urlencode(dict(dataset=repo, config=config, split="test", offset=offset, length=16))
    return json.loads(fetch(f"{ROWS}?{params}"))["rows"]


def metadata():
    for source, config, starts, prefix, locale, corpus in [
        (TARSILA, "default", [800, 1200, 3400, 6600], "pt", "pt-BR", "pt-conversation"),
        (AMI, "ihm", [32, 620, 1620, 2570], "en", "en-US", "en-meeting"),
    ]:
        repo, revision = source
        current = json.loads(fetch(f"{HUB}/api/datasets/{repo}"))
        if current["sha"] != revision:
            raise ValueError(f"Dataset viewer moved to a different revision: {repo}")
        for offset in starts:
            for cell in block(source, config, offset):
                row = cell["row"]
                if source == TARSILA and row["origin"] != "nurcsp":
                    raise ValueError("Unexpected source for this pinned Tarsila block")
                idx = cell["row_idx"]
                clip = dict(id=f"{prefix}-r3-{idx:05d}", dataset=repo, revision=revision,
                            row=idx, locale=locale, scenario=corpus, reference=row["text"])
                if source == AMI:
                    clip["speaker"] = row["speaker_id"]
                    clip["session"] = row["meeting_id"]
                yield clip, row["audio"][0]["src"]

    repo, revision = CS_FLEURS
    root = f"{HUB}/datasets/{repo}/resolve/{revision}/read/test"
    rows = [json.loads(line) for line in fetch(f"{root}/metadata.jsonl").splitlines()]
    portuguese = sorted((row for row in rows if row["language"] == "por-eng"), key=lambda row: row["id"])
    for row in portuguese[3::8][:40]:
        yield dict(id=f"mix-r3-{row['id']}", dataset=repo, revision=revision, row=row["id"],
                   locale="pt-BR", scenario="pt-en-read-switch", reference=row["text"],
                   speaker=row["speaker"]), f"{root}/{row['file_name']}"


def stage(output, manifest_path):
    output.mkdir(parents=True, exist_ok=True)
    manifest = output / "manifest.json"

    def digest(path):
        return hashlib.sha256(path.read_bytes()).hexdigest()

    def acquire(job):
        row, url = job
        wav = output / (row["id"] + ".wav")
        if not wav.exists():
            raw = wav.with_suffix(".source")
            partial = wav.with_suffix(".partial.wav")
            fetch(url, raw)
            subprocess.run(["ffmpeg", "-nostdin", "-y", "-v", "error", "-i", raw, "-ac", "1", "-ar", "16000",
                            "-c:a", "pcm_s16le", "-map_metadata", "-1", partial], check=True)
            partial.replace(wav)
            raw.unlink()
        return {**row, "sha256": digest(wav)}

    if manifest.exists():
        rows = json.loads(manifest.read_text())
        if any(digest(output / (r["id"] + ".wav")) != r["sha256"] for r in rows):
            raise ValueError("A local input changed")
    else:
        jobs = list(metadata())
        if len(jobs) != 168:
            raise ValueError(f"Expected 168 inputs, received {len(jobs)}")
        with ThreadPoolExecutor(max_workers=10) as workers:
            rows = list(workers.map(acquire, jobs))
        manifest.write_text(json.dumps(rows, ensure_ascii=False, indent=2) + "\n")
    archived = [{k: v for k, v in row.items() if k != "reference"} for row in rows]
    if manifest_path.exists() and archived != json.loads(manifest_path.read_text()):
        raise ValueError("Captured inputs do not match the pinned result archive")
    manifest_path.write_text(json.dumps(archived, ensure_ascii=False, indent=2) + "\n")
    print(f"Staged and verified {len(rows)} clips.")


if __name__ == "__main__":
    stage(Path(sys.argv[1]), Path(sys.argv[2]))
