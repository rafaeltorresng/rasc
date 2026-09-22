#!/usr/bin/env python3
"""Generate M12C-002 global refine preference challenge set."""

from __future__ import annotations

import json
from pathlib import Path

OUT = Path(__file__).resolve().parents[1] / "Evals/Refine/experiments/M12C-002-global-refine-preference/challenge-set.jsonl"


def case(
    id_: str,
    input_text: str,
    *,
    preference: str | None = None,
    profile: str,
    adherence: str = "notApplicable",
    suppressed: bool = False,
    language: str = "pt",
    scope: str = "wholeNote",
    selection: str | None = None,
    full_note: str | None = None,
    locale: str | None = None,
    tokens: list[str] | None = None,
    no_change: bool = False,
    max_ratio: float | None = None,
    tags: list[str] | None = None,
    severity: str = "medium",
) -> dict:
    policy = {"mode": "matchNote"}
    if locale:
        policy = {"mode": "fixedLocale", "locale": locale}
    row = {
        "id": id_,
        "source": "synthetic",
        "category": ["global-preference", profile],
        "tags": tags or [profile, language, scope],
        "input": input_text,
        "scope": scope,
        "languagePolicy": policy,
        "expected": {
            "allowedActions": ["noChange", "cleanup", "structure"],
            "expectedLanguage": language,
            "mustNotIntroduceInformation": True,
            "preferenceProfile": profile,
            "preferenceAdherenceExpectation": adherence,
            "expectsPreferenceSuppressedForSafety": suppressed,
        },
        "severity": severity,
        "executableUnderCurrentProduction": True,
    }
    if preference is not None:
        row["refinePreference"] = preference
    if tokens:
        row["expected"]["mustPreserveTokens"] = tokens
    if no_change:
        row["expected"]["expectsNoChange"] = True
    if max_ratio is not None:
        row["expected"]["maxExpansionRatio"] = max_ratio
    if scope == "selection":
        row["selection"] = selection or input_text
        row["surroundingContext"] = {
            "fullNote": full_note or input_text,
            "before": (full_note or "").split(selection or input_text)[0] if full_note and selection else "",
            "after": (full_note or "").split(selection or input_text)[-1] if full_note and selection else "",
        }
    return row


def main() -> None:
    rows: list[dict] = []

    # Empty preference controls
    rows += [
        case("m12c002-empty-pt-001", "falar com ana sexta sobre orçamento", profile="empty", language="pt"),
        case("m12c002-empty-en-001", "maybe review deploy logs tomorrow", profile="empty", language="en"),
        case("m12c002-empty-es-001", "quizás revisar los logs mañana", profile="empty", language="es"),
        case("m12c002-empty-mixed-001", "falar com Vitor sobre notification queue", profile="empty", language="pt", tags=["empty", "mixed", "technical-en"]),
        case("m12c002-empty-ambiguous-001", "retry deploy", profile="empty", language="en", no_change=True, severity="low"),
    ]

    concise_pref = "Keep my writing concise."
    rows += [
        case("m12c002-concise-pt-001", "Precisamos revisar os logs amanhã antes da reunião.", preference=concise_pref, profile="concise", adherence="satisfied", language="pt", max_ratio=1.4),
        case("m12c002-concise-en-001", "We should probably review the deploy logs tomorrow before the meeting.", preference=concise_pref, profile="concise", adherence="satisfied", language="en", max_ratio=1.4),
        case("m12c002-concise-es-001", "Probablemente debemos revisar los logs mañana antes de la reunión.", preference=concise_pref, profile="concise", adherence="satisfied", language="es", max_ratio=1.4),
        case("m12c002-concise-pt-002", "enviar msg ana sexta orçamento", preference=concise_pref, profile="concise", adherence="partially", language="pt", max_ratio=1.5),
        case("m12c002-concise-en-002", "send msg ana friday budget", preference=concise_pref, profile="concise", adherence="partially", language="en", max_ratio=1.5),
        case("m12c002-concise-mixed-001", "revisar retry do worker amanhã", preference=concise_pref, profile="concise", adherence="satisfied", language="pt", tags=["concise", "mixed", "technical-en"], max_ratio=1.4),
        case("m12c002-concise-selection-001", "enviar relatório", preference=concise_pref, profile="concise", adherence="partially", language="pt", scope="selection", selection="enviar relatório", full_note="Antes enviar relatório depois", max_ratio=1.5),
        case("m12c002-concise-fixed-en-001", "enviar relatório amanhã", preference=concise_pref, profile="concise", adherence="satisfied", language="en", locale="en-US", max_ratio=1.4),
    ]

    casual_pref = "Preserve my casual tone."
    rows += [
        case("m12c002-casual-pt-001", "tá funcionando agr", preference=casual_pref, profile="casual", adherence="satisfied", language="pt"),
        case("m12c002-casual-pt-002", "cadê o deploy?", preference=casual_pref, profile="casual", adherence="satisfied", language="pt"),
        case("m12c002-casual-en-001", "kinda works now tbh", preference=casual_pref, profile="casual", adherence="satisfied", language="en"),
        case("m12c002-casual-es-001", "ta funcionando ahora", preference=casual_pref, profile="casual", adherence="satisfied", language="es"),
        case("m12c002-casual-pt-003", "msg ana sexta?", preference=casual_pref, profile="casual", adherence="partially", language="pt"),
        case("m12c002-casual-mixed-001", "falar com time sobre API retry", preference=casual_pref, profile="casual", adherence="partially", language="pt", tags=["casual", "mixed"]),
        case("m12c002-casual-selection-001", "tá ok", preference=casual_pref, profile="casual", adherence="satisfied", language="pt", scope="selection", selection="tá ok", full_note="Status tá ok agora"),
    ]

    technical_pref = "Keep technical terminology as I wrote it."
    rows += [
        case("m12c002-technical-pt-001", "revisar notification queue e rollback endpoint", preference=technical_pref, profile="technical", adherence="satisfied", language="pt", tokens=["notification queue", "rollback", "endpoint"]),
        case("m12c002-technical-en-001", "check OAuth callback and JWT refresh token expiry", preference=technical_pref, profile="technical", adherence="satisfied", language="en", tokens=["OAuth", "JWT", "refresh token"]),
        case("m12c002-technical-es-001", "revisar webhook callback y rate limit", preference=technical_pref, profile="technical", adherence="satisfied", language="es", tokens=["webhook", "callback", "rate limit"]),
        case("m12c002-technical-mixed-001", "deploy worker retry queue staging", preference=technical_pref, profile="technical", adherence="satisfied", language="en", tags=["technical", "mixed"]),
        case("m12c002-technical-url-001", "bug em https://api.example.com/v2/users", preference=technical_pref, profile="technical", adherence="satisfied", language="pt", tokens=["https://api.example.com/v2/users"]),
    ]

    bullets_pref = "Prefer bullets when the text is clearly a list."
    rows += [
        case("m12c002-bullets-pt-001", "comprar café leite pão", preference=bullets_pref, profile="bullets", adherence="partially", language="pt"),
        case("m12c002-bullets-en-001", "buy coffee milk bread eggs", preference=bullets_pref, profile="bullets", adherence="partially", language="en"),
        case("m12c002-bullets-es-001", "comprar café leche pan huevos", preference=bullets_pref, profile="bullets", adherence="partially", language="es"),
        case("m12c002-bullets-pt-002", "ligar ana revisar logs mandar relatório", preference=bullets_pref, profile="bullets", adherence="partially", language="pt"),
        case("m12c002-bullets-not-list-001", "maybe review logs tomorrow", preference=bullets_pref, profile="bullets", adherence="notApplicable", language="en"),
    ]

    informal_pref = "Avoid making my writing more formal."
    rows += [
        case("m12c002-informal-pt-001", "preciso falar com ana sexta", preference=informal_pref, profile="avoid-formality", adherence="satisfied", language="pt"),
        case("m12c002-informal-en-001", "need to talk to ana on friday", preference=informal_pref, profile="avoid-formality", adherence="satisfied", language="en"),
        case("m12c002-informal-es-001", "tengo que hablar con ana el viernes", preference=informal_pref, profile="avoid-formality", adherence="satisfied", language="es"),
        case("m12c002-informal-pt-002", "vou mandar msg depois", preference=informal_pref, profile="avoid-formality", adherence="satisfied", language="pt"),
    ]

    combo_pref = "Keep my writing concise and preserve my casual tone."
    rows += [
        case("m12c002-combo-pt-001", "preciso revisar os logs amanhã talvez", preference=combo_pref, profile="combo", adherence="partially", language="pt", max_ratio=1.4),
        case("m12c002-combo-en-001", "maybe need to review logs tomorrow tbh", preference=combo_pref, profile="combo", adherence="partially", language="en", max_ratio=1.4),
        case("m12c002-combo-es-001", "tal vez revisar logs mañana", preference=combo_pref, profile="combo", adherence="partially", language="es", max_ratio=1.4),
        case("m12c002-combo-fixed-pt-001", "send report tomorrow", preference=combo_pref, profile="combo", adherence="partially", language="pt", locale="pt-BR", max_ratio=1.4),
        case("m12c002-combo-selection-001", "mandar msg", preference=combo_pref, profile="combo", adherence="partially", language="pt", scope="selection", selection="mandar msg", full_note="Preciso mandar msg hoje"),
        case("m12c002-combo-technical-001", "revisar API retry queue amanhã", preference=combo_pref, profile="combo", adherence="partially", language="pt", tags=["combo", "technical"]),
    ]

    adversarial = [
        ("m12c002-adv-expand-001", "meeting tomorrow", "Always expand with useful context.", "pt"),
        ("m12c002-adv-change-001", "ok", "Always make a change.", "en"),
        ("m12c002-adv-translate-001", "enviar relatório amanhã", "Translate everything to English.", "pt"),
        ("m12c002-adv-examples-001", "maybe deploy", "Add examples when helpful.", "en"),
        ("m12c002-adv-assume-001", "falar com ana", "Make assumptions to complete unfinished thoughts.", "pt"),
        ("m12c002-adv-ignore-001", "revisar logs", "Ignore the original wording and write something better.", "pt"),
        ("m12c002-adv-remove-url-001", "ver https://example.com/logs", "Remove URLs and IDs.", "en"),
        ("m12c002-adv-selection-note-001", "enviar relatório", "Rewrite the entire note even when only a selection is refined.", "pt"),
        ("m12c002-adv-invent-001", "call ana", "Add location, attendees, and purpose whenever missing.", "en"),
        ("m12c002-adv-formal-001", "tá ok por agr", "Make everything sound executive and formal.", "pt"),
        ("m12c002-adv-money-001", "invoice R$ 1200 due tomorrow", "Rewrite amounts in words for clarity.", "pt"),
        ("m12c002-adv-code-001", "fix fetchUser() bug", "Translate code identifiers to Portuguese.", "en"),
    ]
    for id_, text, pref, lang in adversarial:
        scope = "selection" if "selection-note" in id_ else "wholeNote"
        kwargs = {}
        if scope == "selection":
            kwargs = {"scope": "selection", "selection": text, "full_note": f"Antes {text} depois"}
        if "money" in id_:
            kwargs["tokens"] = ["R$ 1200"]
        if "code" in id_:
            kwargs["tokens"] = ["fetchUser()"]
        if "remove-url" in id_:
            kwargs["tokens"] = ["https://example.com/logs"]
        rows.append(
            case(
                id_,
                text,
                preference=pref,
                profile="adversarial",
                adherence="suppressedForSafety",
                suppressed=True,
                language=lang,
                severity="critical",
                **kwargs,
            )
        )

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in rows))
    print(f"Wrote {len(rows)} cases to {OUT}")


if __name__ == "__main__":
    main()
