#!/usr/bin/env python3
"""Local maintainer review server for Refine eval adjudication (localhost only)."""

from __future__ import annotations

import json
import os
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
CORPUS_ROOT = Path(os.environ.get("RASC_EVAL_ROOT", ROOT / "Evals/Refine"))
PRIORITY_QUEUE = CORPUS_ROOT / "priority-queue.v1.json"
ADJUDICATIONS_V1 = CORPUS_ROOT / "adjudications.v1.jsonl"
ADJUDICATIONS_V2 = CORPUS_ROOT / "adjudications.v2.jsonl"
M12B001_RESULTS = CORPUS_ROOT / "experiments/M12B-001-language-contract/reports/dev/results.json"
M12B002_DIAG = CORPUS_ROOT / "experiments/M12B-002-language-diagnostics/reports/dev/language-diagnostics.jsonl"
REVIEW_QUEUE = CORPUS_ROOT / "review-queue.jsonl"
CORPUS = CORPUS_ROOT / "corpus.v1.jsonl"
REGRESSION = CORPUS_ROOT / "regression.jsonl"
SPLITS = CORPUS_ROOT / "splits.v1.json"
PORT = int(os.environ.get("REFINE_REVIEW_PORT", "8765"))
SHUFFLE_SEED = "refine-priority-review-v1"


def load_jsonl(path: Path) -> list[dict]:
    if not path.exists():
        return []
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def load_cases() -> dict[str, dict]:
    cases: dict[str, dict] = {}
    for path in (CORPUS, REGRESSION, REVIEW_QUEUE):
        for row in load_jsonl(path):
            cases[row["id"]] = row
    return cases


def load_priority_ids() -> list[str]:
    if not PRIORITY_QUEUE.exists():
        return []
    data = json.loads(PRIORITY_QUEUE.read_text(encoding="utf-8"))
    return data.get("caseIDs", [])


def load_queue_sources() -> dict[str, list[str]]:
    if not PRIORITY_QUEUE.exists():
        return {}
    data = json.loads(PRIORITY_QUEUE.read_text(encoding="utf-8"))
    return data.get("sourcesByCaseID", {})


def load_splits() -> dict[str, str]:
    if not SPLITS.exists():
        return {}
    return json.loads(SPLITS.read_text(encoding="utf-8")).get("assignments", {})


def stable_shuffle(case_ids: list[str], seed: str = SHUFFLE_SEED) -> list[str]:
    def score(case_id: str) -> int:
        value = 5381
        for byte in f"{seed}:{case_id}".encode():
            value = ((value << 5) + value + byte) & 0xFFFFFFFFFFFFFFFF
        return value

    return sorted(case_ids, key=score)


def load_m12b001_context() -> dict[str, dict]:
    ctx: dict[str, dict] = {}
    if M12B001_RESULTS.exists():
        bundle = json.loads(M12B001_RESULTS.read_text(encoding="utf-8"))
        records = {r["caseID"]: r for r in bundle.get("records", []) if r.get("runIndex") == 0}
        for case_id, record in records.items():
            ctx[case_id] = {
                "finalOutput": record.get("output"),
                "finalDecision": record.get("decision"),
            }
    if M12B002_DIAG.exists():
        for line in M12B002_DIAG.read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            row = json.loads(line)
            ctx.setdefault(row["caseID"], {}).update({"languageDiagnostics": row.get("diagnostics")})
    return ctx


def migrate_v1(record: dict) -> dict:
    verdict = record.get("verdict")
    product = None
    benchmark = None
    if verdict == "productFailure":
        product = "productFailure"
    elif verdict == "outputAcceptable":
        product = "outputAcceptable"
    elif verdict == "languageAmbiguous":
        product = "languageAmbiguous"
    elif verdict == "benchmarkExpectationWrong":
        benchmark = "benchmarkExpectationWrong"
    elif verdict == "needsConstraintEdit":
        benchmark = "needsConstraintEdit"
    elif verdict == "defer":
        product = "defer"
    reviewed_at = record.get("reviewedAt")
    return {
        "schemaVersion": 2,
        "caseID": record["caseID"],
        "reviewedAt": reviewed_at,
        "productJudgment": product,
        "productFailureLabels": record.get("productFailureLabels"),
        "productNote": record.get("note"),
        "productReviewedAt": reviewed_at if product else None,
        "benchmarkJudgment": benchmark,
        "benchmarkNote": record.get("note"),
        "constraintCorrection": record.get("constraintCorrection"),
        "benchmarkReviewedAt": reviewed_at if benchmark else None,
        "queueSource": record.get("queueSource"),
        "reviewer": record.get("reviewer", "maintainer"),
    }


def merge_v2(existing: dict, update: dict) -> dict:
    merged = dict(existing)
    merged.update({k: v for k, v in update.items() if v is not None})
    merged["schemaVersion"] = 2
    merged["reviewedAt"] = max(existing.get("reviewedAt", ""), update.get("reviewedAt", ""))
    for key in (
        "productJudgment",
        "productFailureLabels",
        "productNote",
        "productReviewedAt",
        "benchmarkJudgment",
        "benchmarkNote",
        "constraintCorrection",
        "benchmarkReviewedAt",
        "queueSource",
        "reviewer",
    ):
        if update.get(key) is not None:
            merged[key] = update[key]
    return merged


def load_adjudications_v2() -> dict[str, dict]:
    latest: dict[str, dict] = {}
    for row in load_jsonl(ADJUDICATIONS_V2):
        cid = row["caseID"]
        latest[cid] = merge_v2(latest[cid], row) if cid in latest else row
    for row in load_jsonl(ADJUDICATIONS_V1):
        migrated = migrate_v1(row)
        cid = migrated["caseID"]
        latest[cid] = merge_v2(latest[cid], migrated) if cid in latest else migrated
    return latest


def has_refine_output(context: dict) -> bool:
    output = (context.get("finalOutput") or "").strip()
    return bool(output)


def build_stage1(case: dict, context: dict) -> dict | None:
    if not has_refine_output(context):
        return None
    payload = {
        "input": case.get("input", ""),
        "finalOutput": context.get("finalOutput"),
        "finalDecision": context.get("finalDecision"),
    }
    if case.get("selection"):
        payload["selection"] = case["selection"]
    if case.get("surroundingContext"):
        payload["surroundingContext"] = case["surroundingContext"]
    return payload


def build_stage2(case: dict, split: str | None, context: dict, queue_sources: list[str]) -> dict:
    expected = case.get("expected") or {}
    diagnostics = context.get("languageDiagnostics") or {}
    assessment = diagnostics.get("generatedLanguageAssessment") or {}
    return {
        "caseID": case["id"],
        "source": case.get("source"),
        "split": split,
        "categories": case.get("category") or [],
        "tags": case.get("tags") or [],
        "severity": case.get("severity"),
        "expectedLanguage": expected.get("expectedLanguage"),
        "languagePolicy": (case.get("languagePolicy") or {}).get("mode"),
        "preferredAction": expected.get("preferredAction"),
        "allowedActions": expected.get("allowedActions") or [],
        "mustPreserveTokens": expected.get("mustPreserveTokens") or [],
        "maxExpansionRatio": expected.get("maxExpansionRatio"),
        "semanticNotes": expected.get("semanticNotes"),
        "m12b001Output": context.get("finalOutput"),
        "m12b001Decision": context.get("finalDecision"),
        "resolvedLabel": diagnostics.get("resolvedLabel"),
        "resolvedLocale": diagnostics.get("resolvedLocale"),
        "resolverConfidence": diagnostics.get("resolverConfidence"),
        "resolverReason": diagnostics.get("resolverReason"),
        "independentAssessmentLabel": assessment.get("label"),
        "independentAssessmentConfidence": assessment.get("confidence"),
        "validatorRejected": diagnostics.get("postValidatorRejected"),
        "finalDecision": diagnostics.get("finalDecision") or context.get("finalDecision"),
        "rootCause": diagnostics.get("rootCause"),
        "rootCauseExplanation": diagnostics.get("rootCauseExplanation"),
        "queueSources": sorted(queue_sources),
    }


def review_status(has_output: bool, adjudication: dict | None) -> dict:
    if not adjudication:
        return {
            "productReviewed": False,
            "benchmarkReviewed": False,
            "fullyReviewed": False,
            "deferred": False,
            "productNotApplicable": not has_output,
        }
    product_reviewed = bool(adjudication.get("productReviewedAt"))
    benchmark_reviewed = bool(adjudication.get("benchmarkReviewedAt"))
    deferred = adjudication.get("productJudgment") == "defer" or adjudication.get(
        "benchmarkJudgment"
    ) == "deferBenchmarkReview"
    fully_reviewed = ((product_reviewed or not has_output) and benchmark_reviewed)
    return {
        "productReviewed": product_reviewed,
        "benchmarkReviewed": benchmark_reviewed,
        "fullyReviewed": fully_reviewed,
        "deferred": deferred,
        "productNotApplicable": not has_output,
    }


def build_review_payload(queue_mode: str = "priority", include_holdout: bool = False) -> dict:
    cases = load_cases()
    splits = load_splits()
    ctx = load_m12b001_context()
    adjudications = load_adjudications_v2()
    queue_sources = load_queue_sources()

    if queue_mode == "review-queue-75":
        ids = [c["id"] for c in load_jsonl(REVIEW_QUEUE)]
        shuffle_seed = "refine-review-queue-75-v1"
    else:
        ids = load_priority_ids()
        shuffle_seed = SHUFFLE_SEED

    if queue_mode == "priority":
        ids = stable_shuffle(ids, shuffle_seed)

    items = []
    for order, case_id in enumerate(ids):
        case = cases.get(case_id)
        if not case:
            continue
        split = case.get("split") or splits.get(case_id)
        if not include_holdout and split == "holdout":
            continue
        context = ctx.get(case_id, {})
        has_output = has_refine_output(context)
        adjudication = adjudications.get(case_id)
        items.append(
            {
                "reviewOrder": order,
                "hasRefineOutput": has_output,
                "stage1": build_stage1(case, context),
                "stage2": build_stage2(case, split, context, queue_sources.get(case_id, [])),
                "reviewStatus": review_status(has_output, adjudication),
                "adjudication": adjudication,
            }
        )

    return {
        "schemaVersion": 2,
        "queueMode": queue_mode,
        "includeHoldout": include_holdout,
        "shuffleSeed": shuffle_seed,
        "items": items,
        "adjudicationCount": len(adjudications),
    }


HTML = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<title>Rasc Refine Maintainer Review</title>
<style>
  body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 0; display: grid; grid-template-columns: 280px 1fr; height: 100vh; }
  aside { border-right: 1px solid #ddd; overflow: auto; padding: 12px; background: #fafafa; }
  main { padding: 20px; overflow: auto; }
  .case-item { cursor: pointer; padding: 6px 8px; border-radius: 6px; margin-bottom: 4px; font-size: 13px; }
  .case-item.active { background: #e8f0fe; }
  .case-item.done { color: #1b5e20; }
  .case-item.partial { color: #9a6700; }
  pre { background: #f5f5f5; padding: 12px; white-space: pre-wrap; }
  fieldset { margin: 16px 0; border: 1px solid #ddd; padding: 16px; border-radius: 8px; }
  legend { font-weight: 600; }
  .meta { color: #555; font-size: 13px; }
  button { margin-right: 8px; margin-top: 8px; }
  .stage-banner { background: #fff8e1; border: 1px solid #f0d98c; padding: 10px 12px; border-radius: 8px; margin-bottom: 16px; }
  .hidden { display: none; }
</style>
</head>
<body>
<aside>
  <h3>Review Queue</h3>
  <div class="meta" id="stats"></div>
  <div id="case-list"></div>
</aside>
<main>
  <div id="content"><p>Select a case.</p></div>
</main>
<script>
let payload = null;
let index = 0;
const productJudgments = ["outputAcceptable","productFailure","languageAmbiguous","defer"];
const benchmarkJudgments = ["benchmarkCorrect","benchmarkExpectationWrong","needsConstraintEdit","deferBenchmarkReview"];
const failureLabels = ["wrongLanguage","inventedInformation","unnecessaryEdit","meaningChanged","excessiveExpansion","protectedTokenMutation","selectionLeak","styleVoiceDamage","other"];
const stage1Revealed = new Set();

async function load() {
  const res = await fetch('/api/payload');
  payload = await res.json();
  const reviewed = payload.items.filter(i => i.reviewStatus.fullyReviewed).length;
  document.getElementById('stats').textContent = `${payload.items.length} cases · ${reviewed} fully reviewed`;
  const list = document.getElementById('case-list');
  list.innerHTML = '';
  payload.items.forEach((item, i) => {
    const div = document.createElement('div');
    const status = item.reviewStatus;
    div.className = 'case-item' + (i === index ? ' active' : '') + (status.fullyReviewed ? ' done' : (status.productReviewed || status.benchmarkReviewed ? ' partial' : ''));
    const label = shouldShowBenchmark(item) ? item.stage2.caseID : `Case ${item.reviewOrder + 1}`;
    div.textContent = label;
    div.onclick = () => { index = i; render(); };
    list.appendChild(div);
  });
  render();
}

function shouldShowBenchmark(item) {
  if (!item.hasRefineOutput) return true;
  if (item.reviewStatus.productReviewed) return true;
  return stage1Revealed.has(item.stage2.caseID);
}

function render() {
  document.querySelectorAll('.case-item').forEach((el, i) => el.classList.toggle('active', i === index));
  const item = payload.items[index];
  if (!item) return;
  const showBenchmark = shouldShowBenchmark(item);
  const content = document.getElementById('content');
  if (!showBenchmark) {
    content.innerHTML = renderStage1(item);
    bindStage1(item);
    return;
  }
  content.innerHTML = renderStage2(item);
  bindStage2(item);
}

function renderStage1(item) {
  const s1 = item.stage1;
  return `
    <div class="stage-banner"><strong>Stage 1 — Blind product judgment.</strong> Benchmark expectations and diagnostics are hidden.</div>
    <h2>Case ${item.reviewOrder + 1}</h2>
    <h3>Input</h3><pre>${escapeHtml(s1.input)}</pre>
    ${s1.selection ? `<h3>Selection</h3><pre>${escapeHtml(s1.selection)}</pre>` : ''}
    ${s1.surroundingContext ? `<h3>Context</h3><pre>${escapeHtml(JSON.stringify(s1.surroundingContext, null, 2))}</pre>` : ''}
    <h3>Final output</h3><pre>${escapeHtml(s1.finalOutput || '—')}</pre>
    <p class="meta">Final action: <strong>${escapeHtml(s1.finalDecision || '—')}</strong></p>
    <fieldset><legend>Product judgment</legend>
      <label>Verdict<br><select id="productJudgment">${productJudgments.map(v => `<option value="${v}">${v}</option>`).join('')}</select></label><br><br>
      <label>Product failure labels<br>${failureLabels.map(l => `<label><input type="checkbox" name="pf" value="${l}"> ${l}</label> `).join('')}</label><br><br>
      <label>Note<br><textarea id="productNote" rows="3" style="width:100%"></textarea></label><br>
      <button id="save-product">Save product judgment</button>
      <button id="reveal-benchmark" type="button">Continue to benchmark review</button>
      <span id="save-status"></span>
    </fieldset>
  `;
}

function renderStage2(item) {
  const s2 = item.stage2;
  const skipBanner = item.hasRefineOutput ? '' : '<div class="stage-banner">No Refine output for this case. Benchmark review only.</div>';
  const revealBanner = item.hasRefineOutput ? '<div class="stage-banner"><strong>Stage 2 — Benchmark / diagnostic review.</strong> Expectations and diagnostics are now visible.</div>' : '';
  return `
    ${skipBanner}${revealBanner}
    <h2>${escapeHtml(s2.caseID)}</h2>
    <p class="meta">source: ${escapeHtml(s2.source || '—')} · split: ${escapeHtml(s2.split || '—')} · severity: ${escapeHtml(s2.severity || '—')}</p>
    <p class="meta">categories: ${(s2.categories||[]).join(', ') || '—'} · tags: ${(s2.tags||[]).join(', ') || '—'}</p>
    <h3>Expectations</h3>
    <ul>
      <li>expected language: ${s2.expectedLanguage || '—'}</li>
      <li>language policy: ${s2.languagePolicy || '—'}</li>
      <li>preferred action: ${s2.preferredAction || '—'}</li>
      <li>allowed actions: ${(s2.allowedActions||[]).join(', ') || '—'}</li>
      <li>must preserve: ${(s2.mustPreserveTokens||[]).join(', ') || '—'}</li>
      <li>max expansion: ${s2.maxExpansionRatio ?? '—'}</li>
      <li>semantic notes: ${s2.semanticNotes || '—'}</li>
    </ul>
    <h3>Run output</h3>
    <ul>
      <li>output: <pre>${escapeHtml(s2.m12b001Output || '—')}</pre></li>
      <li>decision: ${escapeHtml(s2.m12b001Decision || '—')}</li>
    </ul>
    <h3>Diagnostics</h3>
    <ul>
      <li>resolved: ${s2.resolvedLabel || '—'} (${s2.resolvedLocale || '—'}) · confidence: ${s2.resolverConfidence || '—'}</li>
      <li>resolver reason: ${s2.resolverReason || '—'}</li>
      <li>independent assessment: ${s2.independentAssessmentLabel || '—'} (${s2.independentAssessmentConfidence || '—'})</li>
      <li>validator rejected: ${s2.validatorRejected}</li>
      <li>final decision: ${s2.finalDecision || '—'}</li>
      <li>root cause: ${s2.rootCause || '—'}</li>
      <li>explanation: ${s2.rootCauseExplanation || '—'}</li>
      <li>queue sources: ${(s2.queueSources||[]).join(', ') || '—'}</li>
    </ul>
    <fieldset><legend>Benchmark judgment</legend>
      <label>Verdict<br><select id="benchmarkJudgment">${benchmarkJudgments.map(v => `<option value="${v}">${v}</option>`).join('')}</select></label><br><br>
      <label>Note<br><textarea id="benchmarkNote" rows="3" style="width:100%"></textarea></label>
      <h4>Constraint correction (optional)</h4>
      <div style="display:grid;grid-template-columns:1fr 1fr;gap:8px">
        <input id="corrLang" placeholder="expected language" />
        <input id="corrPreferred" placeholder="preferred action" />
        <input id="corrAllowed" placeholder="allowed actions (comma-separated)" />
        <input id="corrTokens" placeholder="must preserve (comma-separated)" />
        <input id="corrMax" placeholder="max expansion ratio" />
        <input id="corrSeverity" placeholder="severity" />
        <input id="corrSemantic" placeholder="semantic notes" style="grid-column:1 / span 2" />
      </div>
      <br><button id="save-benchmark">Save benchmark judgment</button>
      <span id="save-status"></span>
    </fieldset>
    ${item.adjudication ? `<p class="meta">Product: ${item.adjudication.productJudgment || '—'} · Benchmark: ${item.adjudication.benchmarkJudgment || '—'}</p>` : ''}
  `;
}

function bindStage1(item) {
  const adjudication = item.adjudication || {};
  if (adjudication.productJudgment) document.getElementById('productJudgment').value = adjudication.productJudgment;
  if (adjudication.productNote) document.getElementById('productNote').value = adjudication.productNote;
  document.getElementById('reveal-benchmark').onclick = () => {
    stage1Revealed.add(item.stage2.caseID);
    render();
  };
  document.getElementById('save-product').onclick = () => saveProduct(item);
}

function bindStage2(item) {
  const adjudication = item.adjudication || {};
  if (adjudication.benchmarkJudgment) document.getElementById('benchmarkJudgment').value = adjudication.benchmarkJudgment;
  if (adjudication.benchmarkNote) document.getElementById('benchmarkNote').value = adjudication.benchmarkNote;
  document.getElementById('save-benchmark').onclick = () => saveBenchmark(item);
}

async function saveProduct(item) {
  const labels = [...document.querySelectorAll('input[name=pf]:checked')].map(el => el.value);
  const body = {
    caseID: item.stage2.caseID,
    productJudgment: document.getElementById('productJudgment').value,
    productFailureLabels: labels,
    productNote: document.getElementById('productNote').value || null,
    queueSource: payload.queueMode,
  };
  const res = await fetch('/api/adjudicate/product', { method: 'POST', headers: {'Content-Type':'application/json'}, body: JSON.stringify(body) });
  document.getElementById('save-status').textContent = res.ok ? 'Saved.' : 'Failed.';
  if (res.ok) {
    stage1Revealed.add(item.stage2.caseID);
    await load();
  }
}

async function saveBenchmark(item) {
  const body = {
    caseID: item.stage2.caseID,
    benchmarkJudgment: document.getElementById('benchmarkJudgment').value,
    benchmarkNote: document.getElementById('benchmarkNote').value || null,
    queueSource: payload.queueMode,
    constraintCorrection: {
      expectedLanguage: document.getElementById('corrLang').value || null,
      preferredAction: document.getElementById('corrPreferred').value || null,
      allowedActions: document.getElementById('corrAllowed').value ? document.getElementById('corrAllowed').value.split(',').map(s => s.trim()) : null,
      mustPreserveTokens: document.getElementById('corrTokens').value ? document.getElementById('corrTokens').value.split(',').map(s => s.trim()) : null,
      maxExpansionRatio: document.getElementById('corrMax').value ? Number(document.getElementById('corrMax').value) : null,
      semanticNotes: document.getElementById('corrSemantic').value || null,
      severity: document.getElementById('corrSeverity').value || null,
    }
  };
  const res = await fetch('/api/adjudicate/benchmark', { method: 'POST', headers: {'Content-Type':'application/json'}, body: JSON.stringify(body) });
  document.getElementById('save-status').textContent = res.ok ? 'Saved.' : 'Failed.';
  if (res.ok) load();
}

function escapeHtml(s) {
  return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
}

load();
</script>
</body>
</html>"""


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format: str, *args) -> None:  # noqa: A003
        return

    def do_GET(self) -> None:  # noqa: N802
        path = urlparse(self.path).path
        if path in ("/", "/index.html"):
            self._text(HTML, "text/html; charset=utf-8")
        elif path == "/api/payload":
            include_holdout = os.environ.get("REFINE_REVIEW_INCLUDE_HOLDOUT") == "1"
            queue_mode = os.environ.get("REFINE_REVIEW_QUEUE_MODE", "priority")
            self._json(build_review_payload(queue_mode=queue_mode, include_holdout=include_holdout))
        else:
            self.send_error(404)

    def do_POST(self) -> None:  # noqa: N802
        path = urlparse(self.path).path
        if path not in ("/api/adjudicate/product", "/api/adjudicate/benchmark"):
            self.send_error(404)
            return
        length = int(self.headers.get("Content-Length", "0"))
        body = json.loads(self.rfile.read(length).decode("utf-8"))
        now = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
        latest = load_adjudications_v2().get(body["caseID"], {})
        record = {
            "schemaVersion": 2,
            "caseID": body["caseID"],
            "reviewedAt": now,
            "queueSource": body.get("queueSource"),
            "reviewer": "maintainer",
        }
        if path.endswith("/product"):
            record.update(
                {
                    "productJudgment": body.get("productJudgment"),
                    "productFailureLabels": body.get("productFailureLabels") or None,
                    "productNote": body.get("productNote"),
                    "productReviewedAt": now,
                }
            )
        else:
            corr = body.get("constraintCorrection") or {}
            record.update(
                {
                    "benchmarkJudgment": body.get("benchmarkJudgment"),
                    "benchmarkNote": body.get("benchmarkNote"),
                    "constraintCorrection": {k: v for k, v in corr.items() if v not in (None, "", [])} or None,
                    "benchmarkReviewedAt": now,
                }
            )
        merged = merge_v2(latest, record) if latest else record
        with ADJUDICATIONS_V2.open("a", encoding="utf-8") as fh:
            fh.write(json.dumps(merged, sort_keys=True) + "\n")
        self._json({"ok": True})

    def _json(self, data: dict) -> None:
        payload = json.dumps(data).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def _text(self, text: str, content_type: str) -> None:
        payload = text.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)


def main() -> None:
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print(f"Refine review UI: http://127.0.0.1:{PORT}/")
    print(f"Corpus root: {CORPUS_ROOT}")
    print("Press Ctrl+C to stop.")
    server.serve_forever()


if __name__ == "__main__":
    main()
