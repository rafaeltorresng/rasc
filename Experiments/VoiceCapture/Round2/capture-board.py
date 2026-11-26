#!/usr/bin/env python3
"""Extract source table rows from the public Hugging Face Space config."""
from datetime import date
import html
import json
import re
import subprocess
from pathlib import Path
import sys

source = "https://hf-audio-open-asr-leaderboard.hf.space/config"
patterns = re.compile("SOV-Transcribe|FluidVoice|whisper-large|granite-speech-5|qwen3-asr-|parakeet|OmniASR|CohereLabs|Nemotron|transcribepsy|Rumble|Phonon|Musci|Voxtral", re.I)
table_names = {16: "english-default", 34: "multilingual-default"}
source_data = json.loads(subprocess.check_output(["curl", "-fsSL", source]))
results = {"source": source, "snapshot": date.today().isoformat()}
for comp in source_data["components"]:
    if comp["id"] not in table_names or comp["type"] != "dataframe":
        continue
    value = comp["props"]["value"]
    selected = []
    for i, line in enumerate(value["data"]):
        if i < 4 or patterns.search(" ".join(map(str,line))):
            selected.append([html.unescape(re.sub("<[^>]+>", "", x)).strip() if isinstance(x,str) else x for x in line])
    results[table_names[comp["id"]]] = dict(columns=value["headers"], rows=selected)
assert len(results) == 4
Path(sys.argv[1]).write_text(json.dumps(results,indent=2,ensure_ascii=False)+"\n")
