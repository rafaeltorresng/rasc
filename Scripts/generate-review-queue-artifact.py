#!/usr/bin/env python3
"""Generate a human-readable maintainer review artifact for review-queue.jsonl."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REVIEW_PATH = ROOT / "Evals/Refine/review-queue.jsonl"
OUTPUT_PATH = ROOT / "Evals/Refine/review-queue.md"


def fmt_list(values: list[str] | None) -> str:
    if not values:
        return "—"
    return ", ".join(values)


def main() -> None:
    cases = [json.loads(line) for line in REVIEW_PATH.read_text(encoding="utf-8").splitlines() if line.strip()]
    lines: list[str] = [
        "# Refine Eval Review Queue",
        "",
        f"Generated from `{REVIEW_PATH.relative_to(ROOT)}`. {len(cases)} cases queued for maintainer review.",
        "This artifact is read-only; approve or correct cases in the corpus separately.",
        "",
    ]

    for index, case in enumerate(cases, start=1):
        expected = case.get("expected", {})
        selection = case.get("selection")
        context = case.get("surroundingContext") or {}
        lines.extend(
            [
                f"## {index}. `{case['id']}`",
                "",
                f"- **Severity:** {case.get('severity', '—')}",
                f"- **Category / tags:** {fmt_list(case.get('category'))} / {fmt_list(case.get('tags'))}",
                f"- **Scope:** {case.get('scope', 'wholeNote')}",
                "",
                "### Input",
                "```",
                case.get("input", ""),
                "```",
                "",
            ]
        )

        if selection or context:
            lines.append("### Selection / context")
            if selection:
                lines.append(f"- **Selection:** `{selection}`")
            if context.get("before"):
                lines.append(f"- **Before:** `{context['before']}`")
            if context.get("after"):
                lines.append(f"- **After:** `{context['after']}`")
            if context.get("fullNote") and context.get("fullNote") != case.get("input"):
                lines.append("- **Full note:**")
                lines.append("```")
                lines.append(context["fullNote"])
                lines.append("```")
            lines.append("")

        lines.extend(
            [
                "### Expectations",
                f"- **Expected action(s):** preferred `{expected.get('preferredAction', '—')}`; allowed {fmt_list(expected.get('allowedActions'))}",
                f"- **Expected language:** {expected.get('expectedLanguage', '—')}",
                f"- **Must-preserve values:** {fmt_list(expected.get('mustPreserveTokens'))}",
                f"- **Max expansion ratio:** {expected.get('maxExpansionRatio', '—')}",
                f"- **Semantic expectation:** {expected.get('semanticNotes', '—')}",
                "",
            ]
        )

    OUTPUT_PATH.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Wrote {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
