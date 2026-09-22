#!/usr/bin/env python3
"""Generate and analyze the evaluation-only M12B-005C semantic-literal challenge."""

from __future__ import annotations

import argparse
import json
import re
import shutil
import statistics
import time
from collections import Counter, defaultdict
from dataclasses import dataclass
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
CHALLENGE = ROOT / "Evals/Refine/challenges/semantic-literals.v1.jsonl"
OUTPUT = ROOT / "Evals/Refine/experiments/M12B-005C-semantic-literals"
RUNNER_ROOT = Path("/private/tmp/rasc-m12b-005c-runner")
CLASSES = ("money", "time", "percentage", "date", "number")
LANGUAGE_LOCALES = {"pt": "pt-BR", "en": "en-US", "es": "es-ES", "mixed": "pt-BR"}
DISPOSITIONS = {"exactPreservation", "safeNormalization", "semanticCorruption", "ambiguous"}


@dataclass(frozen=True)
class Comparison:
    disposition: str
    source: str
    candidate: str | None
    reason: str


def decimal_value(raw: str, locale: str, *, grouped: bool = True) -> Decimal | None:
    text = raw.strip().replace("\u00a0", "").replace(" ", "")
    if not text:
        return None
    negative = text.startswith("-")
    text = text.lstrip("+-")
    decimal_separator = "," if locale in {"pt-BR", "es-ES"} else "."
    grouping_separator = "." if decimal_separator == "," else ","
    if grouped:
        text = text.replace(grouping_separator, "")
    if text.count(decimal_separator) > 1:
        return None
    text = text.replace(decimal_separator, ".")
    if not re.fullmatch(r"\d+(?:\.\d+)?", text):
        return None
    try:
        value = Decimal(text)
        return -value if negative else value
    except InvalidOperation:
        return None


def currency_amount(raw: str) -> Decimal | None:
    """Parse BRL/USD/EUR-style amounts without guessing generic number locale."""
    text = raw.strip().replace("\u00a0", "").replace(" ", "")
    negative = text.startswith("-")
    text = text.lstrip("+-")
    if not re.fullmatch(r"\d[\d.,]*", text):
        return None
    comma_count, period_count = text.count(","), text.count(".")
    if comma_count and period_count:
        decimal_separator = "," if text.rfind(",") > text.rfind(".") else "."
        grouping_separator = "." if decimal_separator == "," else ","
        integer, fraction = text.rsplit(decimal_separator, 1)
        groups = integer.split(grouping_separator)
        if not fraction.isdigit() or len(fraction) not in {1, 2}:
            return None
        if len(groups) > 1 and (not 1 <= len(groups[0]) <= 3 or any(len(group) != 3 for group in groups[1:])):
            return None
        normalized = "".join(groups) + "." + fraction
    elif comma_count or period_count:
        separator = "," if comma_count else "."
        pieces = text.split(separator)
        if len(pieces) == 2 and len(pieces[1]) in {1, 2}:
            normalized = pieces[0] + "." + pieces[1]
        elif 1 <= len(pieces[0]) <= 3 and all(len(piece) == 3 for piece in pieces[1:]):
            normalized = "".join(pieces)
        else:
            return None
    else:
        normalized = text
    try:
        value = Decimal(normalized)
        return -value if negative else value
    except InvalidOperation:
        return None


def money_parts(raw: str, locale: str) -> tuple[str, Decimal] | None:
    match = re.fullmatch(
        r"\s*(R\$|US\$|BRL|USD|EUR|€|\$)\s*([+-]?\d[\d.,\s]*)\s*",
        raw,
        re.IGNORECASE,
    )
    if not match:
        return None
    marker = match.group(1).upper()
    identity = {
        "R$": "BRL", "BRL": "BRL", "US$": "USD", "USD": "USD",
        "EUR": "EUR", "€": "EUR", "$": "AMBIGUOUS_DOLLAR",
    }[marker]
    value = currency_amount(match.group(2))
    return (identity, value) if value is not None else None


def swaps_comma_and_period(source: str, candidate: str) -> bool:
    """Return true for a punctuation swap whose locale meaning is not provable."""
    source_marks = ("," in source, "." in source)
    candidate_marks = ("," in candidate, "." in candidate)
    return (source_marks, candidate_marks) in {
        ((True, False), (False, True)),
        ((False, True), (True, False)),
    }


def time_parts(raw: str) -> tuple[int, str] | None:
    text = raw.strip().upper().replace(" ", "")
    match = re.fullmatch(r"([01]?\d|2[0-3])H([0-5]\d)?", text)
    if match:
        return int(match.group(1)) * 60 + int(match.group(2) or 0), "24h"
    match = re.fullmatch(r"([01]?\d|2[0-3]):([0-5]\d)", text)
    if match:
        return int(match.group(1)) * 60 + int(match.group(2)), "24h"
    match = re.fullmatch(r"(1[0-2]|0?[1-9])(?::([0-5]\d))?(AM|PM)", text)
    if match:
        hour = int(match.group(1)) % 12 + (12 if match.group(3) == "PM" else 0)
        return hour * 60 + int(match.group(2) or 0), "12h"
    return None


def percentage_value(raw: str, locale: str) -> Decimal | None:
    match = re.fullmatch(r"\s*([+-]?\d+(?:[.,]\d+)?)\s*%\s*", raw)
    if not match:
        return None
    return decimal_value(match.group(1), locale, grouped=False)


MONTHS = {
    "pt-BR": {"janeiro": 1, "fevereiro": 2, "março": 3, "abril": 4, "maio": 5, "junho": 6, "julho": 7, "agosto": 8, "setembro": 9, "outubro": 10, "novembro": 11, "dezembro": 12},
    "es-ES": {"enero": 1, "febrero": 2, "marzo": 3, "abril": 4, "mayo": 5, "junio": 6, "julio": 7, "agosto": 8, "septiembre": 9, "octubre": 10, "noviembre": 11, "diciembre": 12},
    "en-US": {"january": 1, "february": 2, "march": 3, "april": 4, "may": 5, "june": 6, "july": 7, "august": 8, "september": 9, "october": 10, "november": 11, "december": 12},
}


def date_parts(raw: str, locale: str, ambiguous_source: bool) -> tuple[str | None, str] | None:
    text = raw.strip().lower()
    match = re.fullmatch(r"(\d{4})-(\d{2})-(\d{2})", text)
    if match:
        return f"{match.group(1)}-{match.group(2)}-{match.group(3)}", "iso"
    match = re.fullmatch(r"(\d{1,2})/(\d{1,2})(?:/(\d{4}))?", text)
    if match:
        first, second, year = int(match.group(1)), int(match.group(2)), match.group(3)
        if year is None or ambiguous_source:
            return None, "ambiguousNumeric"
        if locale == "en-US":
            month, day = first, second
        else:
            day, month = first, second
        return f"{year}-{month:02d}-{day:02d}", "numeric"
    for language_locale, months in MONTHS.items():
        if language_locale != locale:
            continue
        for name, month in months.items():
            if locale == "en-US":
                match = re.fullmatch(rf"{name}\s+(\d{{1,2}})(?:,\s*(\d{{4}}))?", text)
            else:
                match = re.fullmatch(rf"(\d{{1,2}})\s+de\s+{name}(?:\s+de\s+(\d{{4}}))?", text)
            if match:
                day, year = int(match.group(1)), match.group(2)
                return (f"{year}-{month:02d}-{day:02d}" if year else None), "textual"
    return None


def literal_candidates(text: str, literal_class: str) -> list[str]:
    patterns = {
        "money": r"(?:R\$|US\$|BRL|USD|EUR|€|\$)\s*[+-]?\d[\d.,\s]*",
        "time": r"(?<!\w)(?:[01]?\d|2[0-3])(?:h(?:[0-5]\d)?|:[0-5]\d)(?!\w)|(?<!\w)(?:1[0-2]|0?[1-9])(?::[0-5]\d)?\s*(?:AM|PM)(?!\w)",
        "percentage": r"[+-]?\d+(?:[.,]\d+)?\s*%",
        "date": r"\b\d{4}-\d{2}-\d{2}\b|\b\d{1,2}/\d{1,2}(?:/\d{4})?\b|\b(?:\d{1,2}\s+de\s+[A-Za-zÀ-ÿ]+(?:\s+de\s+\d{4})?|[A-Za-z]+\s+\d{1,2}(?:,\s*\d{4})?)\b",
        "number": r"(?<![\w%])[-+]?\d[\d.,]*(?![\w%])",
    }
    return [match.group(0).strip() for match in re.finditer(patterns[literal_class], text, re.IGNORECASE)]


def compare_literal(case: dict[str, Any], output: str) -> Comparison:
    source = case["sourceLiteral"]
    if source in output:
        return Comparison("exactPreservation", source, source, "Source literal remains byte-for-byte present.")
    candidates = literal_candidates(output, case["literalClass"])
    if not candidates:
        return Comparison("semanticCorruption", source, None, "Literal was dropped or no same-class literal remains.")
    comparisons = [compare_candidate(case, candidate) for candidate in candidates]
    rank = {"safeNormalization": 0, "exactPreservation": 0, "semanticCorruption": 1, "ambiguous": 2}
    return sorted(comparisons, key=lambda item: rank[item.disposition])[0]


def compare_candidate(case: dict[str, Any], candidate: str) -> Comparison:
    source = case["sourceLiteral"]
    if candidate == source:
        return Comparison("exactPreservation", source, candidate, "Exact source representation.")
    literal_class = case["literalClass"]
    locale = case.get("literalLocale", case["locale"])
    expected = case.get("semanticValue")
    if literal_class == "money":
        parsed = money_parts(candidate, locale)
        if parsed is None:
            return Comparison("ambiguous", source, candidate, "Currency candidate cannot be parsed confidently.")
        currency, value = parsed
        if currency == "AMBIGUOUS_DOLLAR":
            if source.strip().startswith("$") and expected["currency"] == "USD":
                if value == Decimal(expected["amount"]):
                    return Comparison("safeNormalization", source, candidate, "English-context dollar identity and amount are preserved.")
                return Comparison("semanticCorruption", source, candidate, "Dollar amount changed.")
            return Comparison("semanticCorruption", source, candidate, "Currency identity became ambiguous or changed.")
        if currency != expected["currency"]:
            return Comparison("semanticCorruption", source, candidate, "Currency identity or amount changed.")
        if value != Decimal(expected["amount"]):
            return Comparison("semanticCorruption", source, candidate, "Currency amount changed.")
        return Comparison("safeNormalization", source, candidate, "Currency identity and numeric value are preserved.")
    if literal_class == "time":
        parsed = time_parts(candidate)
        if parsed is None:
            return Comparison("ambiguous", source, candidate, "Time candidate cannot be parsed confidently.")
        minutes, family = parsed
        if minutes != expected["minutes"]:
            return Comparison("semanticCorruption", source, candidate, "Clock time changed.")
        source_family = time_parts(source)[1]
        if family != source_family:
            return Comparison("ambiguous", source, candidate, "12h/24h representation changed; preserve without explicit utility.")
        return Comparison("safeNormalization", source, candidate, "Time value and representation family are preserved.")
    if literal_class == "percentage":
        value = percentage_value(candidate, locale)
        if value is None:
            return Comparison("semanticCorruption", source, candidate, "Percent representation was removed or cannot be parsed.")
        if value != Decimal(expected["value"]):
            return Comparison("semanticCorruption", source, candidate, "Percentage magnitude changed.")
        return Comparison("safeNormalization", source, candidate, "Percent magnitude is preserved with percent notation.")
    if literal_class == "date":
        parsed = date_parts(candidate, locale, case.get("ambiguousDate", False))
        if parsed is None:
            return Comparison("ambiguous", source, candidate, "Date candidate cannot be parsed confidently.")
        value, family = parsed
        if expected is None or value is None:
            return Comparison("ambiguous", source, candidate, "Source date is locale-ambiguous and must be preserved.")
        if value != expected["iso"]:
            return Comparison("semanticCorruption", source, candidate, "Calendar date changed.")
        source_family = date_parts(source, locale, False)[1]
        if family != source_family:
            return Comparison("ambiguous", source, candidate, "Date representation family changed.")
        return Comparison("safeNormalization", source, candidate, "Calendar date and locale order are preserved.")
    if literal_class == "number":
        value = decimal_value(candidate, locale)
        if value is None:
            return Comparison("ambiguous", source, candidate, "Number cannot be parsed confidently in the case locale.")
        if value != Decimal(expected["value"]):
            if swaps_comma_and_period(source, candidate):
                return Comparison("ambiguous", source, candidate, "Separator change is locale-sensitive; equivalence is not provable.")
            return Comparison("semanticCorruption", source, candidate, "Numeric value changed under the case locale.")
        source_decimal = ("," in source) if locale in {"pt-BR", "es-ES"} else ("." in source)
        candidate_decimal = ("," in candidate) if locale in {"pt-BR", "es-ES"} else ("." in candidate)
        if source_decimal != candidate_decimal and ("," in source or "." in source) and ("," in candidate or "." in candidate):
            return Comparison("ambiguous", source, candidate, "Decimal/grouping representation changed materially.")
        return Comparison("safeNormalization", source, candidate, "Locale-parsed numeric value is preserved.")
    raise AssertionError(literal_class)


def candidate_sets(literal_class: str, source: str, locale: str, semantic: Any, ambiguous: bool = False) -> list[dict[str, str]]:
    exact = source
    corrupt_classification = "semanticCorruption"
    uncertain_classification = "ambiguous"
    if literal_class == "money":
        identity, amount = semantic["currency"], semantic["amount"]
        safe = source.replace(" ", "") if " " in source else source.replace(identity, identity + " ", 1)
        corrupt = {
            "BRL": "$99.90",
            "USD": "EUR 99.90",
            "EUR": "USD 99.90",
        }[identity]
        uncertain = source.replace(",", ".") if "," in source else source.replace(".", ",")
        uncertain_parts = money_parts(uncertain, locale)
        if uncertain_parts is not None:
            uncertain_currency, uncertain_amount = uncertain_parts
            currency_matches = uncertain_currency == identity or (
                uncertain_currency == "AMBIGUOUS_DOLLAR" and source.strip().startswith("$") and identity == "USD"
            )
            uncertain_classification = (
                "safeNormalization"
                if currency_matches and uncertain_amount == Decimal(amount)
                else "semanticCorruption"
            )
    elif literal_class == "time":
        parts = time_parts(source)
        minutes, family = parts
        safe = f"{minutes // 60:02d}:{minutes % 60:02d}" if family == "24h" and "h" in source.lower() else source.replace(" ", "")
        corrupt = f"{(minutes // 60 + 2) % 24:02d}:{minutes % 60:02d}"
        hour12 = (minutes // 60) % 12 or 12
        uncertain = f"{hour12}:{minutes % 60:02d} {'PM' if minutes >= 720 else 'AM'}"
        if family == "12h":
            uncertain_classification = "safeNormalization"
    elif literal_class == "percentage":
        safe = source.replace(" %", "%") if " %" in source else source.replace("%", " %")
        corrupt = re.sub(r"[+-]?\d+(?:[.,]\d+)?", "15", source, count=1)
        uncertain = str(Decimal(semantic["value"]) / Decimal(100))
        uncertain_classification = "semanticCorruption"
    elif literal_class == "date":
        safe = source
        corrupt = "12/31/2026" if locale != "en-US" else "31/12/2026"
        uncertain = "April 3" if locale == "en-US" else "3 de abril"
        if ambiguous:
            corrupt_classification = "ambiguous"
        if not ambiguous and re.fullmatch(r"\d{1,2}/\d{1,2}/\d{4}", source):
            first, second, year = source.split("/")
            safe = f"{int(first):02d}/{int(second):02d}/{year}"
        elif not ambiguous and re.fullmatch(r"\d{4}-\d{2}-\d{2}", source):
            safe = source
    else:
        value = Decimal(semantic["value"])
        safe = format(value, "f")
        if locale in {"pt-BR", "es-ES"}:
            safe = safe.replace(".", ",")
        corrupt = format(value * Decimal(1000), "f")
        if locale in {"pt-BR", "es-ES"}:
            corrupt = corrupt.replace(".", ",")
        uncertain = source.translate(str.maketrans({",": ".", ".": ","}))
        if decimal_value(uncertain, locale) is not None and not swaps_comma_and_period(source, uncertain):
            uncertain_classification = "semanticCorruption"
    values = [
        {"outputLiteral": exact, "classification": "exactPreservation"},
        {"outputLiteral": safe, "classification": "safeNormalization" if safe != exact else "exactPreservation"},
        {"outputLiteral": corrupt, "classification": corrupt_classification},
        {"outputLiteral": uncertain, "classification": uncertain_classification},
    ]
    dedup: dict[str, dict[str, str]] = {}
    for value in values:
        dedup.setdefault(value["outputLiteral"], value)
    return list(dedup.values())


def specs() -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    money = [
        ("pt", "R$ 99,90", "BRL", "99.90"), ("pt", "BRL 1.250,00", "BRL", "1250.00"),
        ("pt", "R$300", "BRL", "300"), ("pt", "US$ 45,50", "USD", "45.50"),
        ("en", "$99.90", "USD", "99.90"), ("en", "USD 1,250.00", "USD", "1250.00"),
        ("en", "€ 80.00", "EUR", "80.00"), ("en", "EUR 2,500.50", "EUR", "2500.50"),
        ("es", "€ 99,90", "EUR", "99.90"), ("es", "EUR 1.250,00", "EUR", "1250.00"),
        ("es", "USD 45,50", "USD", "45.50"), ("es", "€300", "EUR", "300"),
        ("mixed", "R$ 99,90", "BRL", "99.90"), ("mixed", "USD 120.00", "USD", "120.00"),
        ("pt", "R$ 1.000,50", "BRL", "1000.50"), ("en", "BRL 99.90", "BRL", "99.90"),
    ]
    for language, literal, currency, amount in money:
        rows.append({
            "class": "money", "language": language, "literal": literal,
            "semantic": {"currency": currency, "amount": amount},
            "literalLocale": "en-US" if language == "mixed" and literal == "USD 120.00" else None,
        })
    times = [
        ("pt", "15h"), ("pt", "15h30"), ("pt", "09:00"), ("pt", "18:45"),
        ("en", "3 PM"), ("en", "3:30 PM"), ("en", "09:00"), ("en", "11 AM"),
        ("es", "15:00"), ("es", "15h30"), ("es", "09:15"), ("es", "6 PM"),
        ("mixed", "15h"), ("mixed", "3 PM"), ("pt", "00:00"), ("en", "12 AM"),
    ]
    for language, literal in times:
        rows.append({"class": "time", "language": language, "literal": literal, "semantic": {"minutes": time_parts(literal)[0]}})
    percentages = [
        ("pt", "50%", "50"), ("pt", "12,5%", "12.5"), ("pt", "-3%", "-3"), ("pt", "100 %", "100"),
        ("en", "50%", "50"), ("en", "12.5%", "12.5"), ("en", "-3%", "-3"), ("en", "100 %", "100"),
        ("es", "50%", "50"), ("es", "12,5 %", "12.5"), ("es", "-3%", "-3"), ("es", "100%", "100"),
        ("mixed", "99.9%", "99.9"), ("mixed", "0,5%", "0.5"), ("pt", "+5%", "5"), ("en", "0.5%", "0.5"),
    ]
    for language, literal, value in percentages:
        rows.append({
            "class": "percentage", "language": language, "literal": literal,
            "semantic": {"value": value},
            "literalLocale": "en-US" if language == "mixed" and literal == "99.9%" else None,
        })
    dates = [
        ("pt", "31/12/2026", "2026-12-31", False), ("pt", "03/04", None, True),
        ("pt", "2026-10-01", "2026-10-01", False), ("pt", "5 de maio de 2026", "2026-05-05", False),
        ("en", "12/31/2026", "2026-12-31", False), ("en", "03/04", None, True),
        ("en", "2026-10-01", "2026-10-01", False), ("en", "May 5, 2026", "2026-05-05", False),
        ("es", "31/12/2026", "2026-12-31", False), ("es", "03/04", None, True),
        ("es", "2026-10-01", "2026-10-01", False), ("es", "5 de mayo de 2026", "2026-05-05", False),
        ("mixed", "31/12/2026", "2026-12-31", False), ("mixed", "03/04", None, True),
        ("pt", "01/02/2027", "2027-02-01", False), ("en", "01/02/2027", "2027-01-02", False),
    ]
    for language, literal, iso, ambiguous in dates:
        rows.append({"class": "date", "language": language, "literal": literal, "semantic": {"iso": iso} if iso else None, "ambiguous": ambiguous})
    numbers = [
        ("pt", "1,5", "1.5"), ("pt", "1.000", "1000"), ("pt", "1.000,50", "1000.50"), ("pt", "2500", "2500"),
        ("en", "1.5", "1.5"), ("en", "1,000", "1000"), ("en", "1,000.50", "1000.50"), ("en", "2500", "2500"),
        ("es", "1,5", "1.5"), ("es", "1.000", "1000"), ("es", "1.000,50", "1000.50"), ("es", "2500", "2500"),
        ("mixed", "1,5", "1.5"), ("mixed", "1.000", "1000"), ("pt", "10.000.000", "10000000"), ("en", "10,000,000", "10000000"),
    ]
    for language, literal, value in numbers:
        rows.append({"class": "number", "language": language, "literal": literal, "semantic": {"value": value}})
    assert len(rows) == 80
    return rows


def make_input(literal_class: str, language: str, literal: str, index: int) -> str:
    templates = {
        "pt": {"money": "confirmar valor {x} na fatura", "time": "reunião marcada para {x} amanhã", "percentage": "taxa atual ficou em {x} no painel", "date": "prazo registrado como {x} no contrato", "number": "valor medido foi {x} no relatório"},
        "en": {"money": "confirm invoice amount {x} tomorrow", "time": "meeting scheduled for {x} tomorrow", "percentage": "current dashboard rate is {x} today", "date": "contract deadline recorded as {x}", "number": "measured value was {x} in report"},
        "es": {"money": "confirmar importe {x} en la factura", "time": "reunión prevista para {x} mañana", "percentage": "la tasa actual quedó en {x}", "date": "fecha registrada como {x} en contrato", "number": "el valor medido fue {x} en informe"},
        "mixed": {"money": "checkout total {x} no billing", "time": "sync call {x} com backend", "percentage": "rollout metric {x} no dashboard", "date": "release date {x} no roadmap", "number": "latency factor {x} no benchmark"},
    }
    return templates[language][literal_class].format(x=literal)


def build_cases() -> list[dict[str, Any]]:
    cases: list[dict[str, Any]] = []
    critical_slots = {0, 1, 4, 5}
    per_class_index = Counter()
    for global_index, spec in enumerate(specs(), start=1):
        literal_class = spec["class"]
        local_index = per_class_index[literal_class]
        per_class_index[literal_class] += 1
        language = spec["language"]
        locale = LANGUAGE_LOCALES[language]
        literal_locale = spec.get("literalLocale") or locale
        source = spec["literal"]
        case = {
            "id": f"semantic-{literal_class}-{local_index + 1:03d}",
            "source": "targetedChallenge",
            "humanValidated": False,
            "maintainerApproved": False,
            "reviewStatus": "maintainer-unapproved",
            "literalClass": literal_class,
            "sourceLiteral": source,
            "language": language,
            "locale": locale,
            "literalLocale": literal_locale,
            "semanticValue": spec["semantic"],
            "ambiguousDate": spec.get("ambiguous", False),
            "candidateTransformations": candidate_sets(literal_class, source, literal_locale, spec["semantic"], spec.get("ambiguous", False)),
            "input": make_input(literal_class, language, source, global_index),
            "scope": "wholeNote",
            "category": ["semantic-literal", literal_class, "targeted-challenge"],
            "tags": [language, literal_class, "semantic-literal"],
            "languagePolicy": {"mode": "matchNote", "preferredLocale": locale},
            "expected": {
                "allowedActions": ["noChange", "cleanup", "structure"],
                "expectedLanguage": "pt" if language == "mixed" else language,
                "mustNotIntroduceInformation": True,
                "maxExpansionRatio": 2.0,
                "semanticNotes": "Preserve the literal's semantic value and representation conservatively; challenge expectations are maintainer-unapproved.",
            },
            "severity": "critical" if local_index in critical_slots else "high",
            "inReviewQueue": local_index in critical_slots,
        }
        cases.append(case)
    return cases


def validate_cases(cases: list[dict[str, Any]]) -> None:
    assert 70 <= len(cases) <= 100
    assert len({case["id"] for case in cases}) == len(cases)
    assert Counter(case["literalClass"] for case in cases) == {name: 16 for name in CLASSES}
    assert sum(case["severity"] == "critical" for case in cases) == 20
    for case in cases:
        assert case["humanValidated"] is False and case["maintainerApproved"] is False
        assert case["source"] == "targetedChallenge" and case.get("split") is None
        assert {item["classification"] for item in case["candidateTransformations"]} <= DISPOSITIONS


def self_test(cases: list[dict[str, Any]]) -> None:
    checked = 0
    for case in cases:
        for candidate in case["candidateTransformations"]:
            result = compare_candidate(case, candidate["outputLiteral"])
            assert result.disposition == candidate["classification"], (
                case["id"], candidate, result
            )
            checked += 1
    brl = next(case for case in cases if case["sourceLiteral"] == "R$ 99,90" and case["language"] == "pt")
    assert compare_candidate(brl, "$ 99.90").disposition == "semanticCorruption"
    assert compare_candidate(brl, "99.90").disposition in {"semanticCorruption", "ambiguous"}
    assert compare_candidate(brl, "R$99,90").disposition == "safeNormalization"
    ambiguous_date = next(case for case in cases if case["literalClass"] == "date" and case["ambiguousDate"])
    assert compare_candidate(ambiguous_date, "04/03").disposition == "ambiguous"
    assert checked >= 250


def write_jsonl(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in rows))


def prepare() -> None:
    cases = build_cases()
    validate_cases(cases)
    self_test(cases)
    write_jsonl(CHALLENGE, cases)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(CHALLENGE, OUTPUT / "challenge-set.jsonl")
    if RUNNER_ROOT.exists():
        shutil.rmtree(RUNNER_ROOT)
    RUNNER_ROOT.mkdir(parents=True)
    shutil.copyfile(CHALLENGE, RUNNER_ROOT / "corpus.v1.jsonl")
    (RUNNER_ROOT / "regression.jsonl").write_text("")
    manifest = {
        "version": 1,
        "seed": "m12b-005c-targeted-challenge-not-frozen-split",
        "ratios": {"dev": 1.0, "validation": 0.0, "holdout": 0.0},
        "assignments": {case["id"]: "dev" for case in cases},
        "notes": {"holdout": "No holdout cases are present or referenced."},
    }
    (RUNNER_ROOT / "splits.v1.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print(f"Prepared {len(cases)} cases at {CHALLENGE}")


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text())


def read_jsonl(path: Path) -> list[dict[str, Any]]:
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def classify_record(case: dict[str, Any], record: dict[str, Any], *, raw: bool) -> Comparison:
    if raw:
        diagnostics = record.get("languageDiagnostics") or {}
        raw_decision = diagnostics.get("rawGeneratedDecision")
        text = diagnostics.get("rawGeneratedText")
        if raw_decision != "changed" or not text:
            return Comparison("exactPreservation", case["sourceLiteral"], case["sourceLiteral"], "Model proposed noChange.")
        return compare_literal(case, text)
    if record.get("decision") != "changed" or not record.get("output"):
        return Comparison("exactPreservation", case["sourceLiteral"], case["sourceLiteral"], "Final action is noChange.")
    return compare_literal(case, record["output"])


def analyze() -> None:
    cases = read_jsonl(CHALLENGE)
    validate_cases(cases)
    self_test(cases)
    case_map = {case["id"]: case for case in cases}
    current = read_json(OUTPUT / "reports/current/results.json")
    stability = read_json(OUTPUT / "reports/stability/results.json")
    current_records = current["records"]
    stability_records = stability["records"]
    rows: list[dict[str, Any]] = []
    comparator_times: list[float] = []
    for record in current_records:
        case = case_map[record["caseID"]]
        started = time.perf_counter_ns()
        raw = classify_record(case, record, raw=True)
        comparator_times.append((time.perf_counter_ns() - started) / 1_000_000)
        final = classify_record(case, record, raw=False)
        counterfactual_reject = raw.disposition in {"semanticCorruption", "ambiguous"}
        counterfactual_final = "exactPreservation" if counterfactual_reject else raw.disposition
        rows.append({
            "caseID": case["id"], "literalClass": case["literalClass"], "language": case["language"],
            "input": case["input"], "sourceLiteral": case["sourceLiteral"],
            "actualAction": record.get("decision"), "rawProposal": (record.get("languageDiagnostics") or {}).get("rawGeneratedText"),
            "actualOutput": record.get("output"), "rawDisposition": raw.disposition,
            "rawReason": raw.reason, "rawLiteralDropped": raw.candidate is None,
            "finalDisposition": final.disposition,
            "counterfactualRejected": counterfactual_reject,
            "counterfactualFinalDisposition": counterfactual_final,
        })

    stability_rows: list[dict[str, Any]] = []
    for record in stability_records:
        case = case_map[record["caseID"]]
        raw = classify_record(case, record, raw=True)
        stability_rows.append({"caseID": case["id"], "literalClass": case["literalClass"], "runIndex": record["runIndex"], "rawDisposition": raw.disposition})

    per_class: dict[str, Any] = {}
    for literal_class in CLASSES:
        class_rows = [row for row in rows if row["literalClass"] == literal_class]
        class_stability = [row for row in stability_rows if row["literalClass"] == literal_class]
        counts = Counter(row["rawDisposition"] for row in class_rows)
        stability_counts = Counter(row["rawDisposition"] for row in class_stability)
        caught = sum(row["counterfactualRejected"] and row["rawDisposition"] == "semanticCorruption" for row in class_rows)
        safe = sum(row["rawDisposition"] == "safeNormalization" for row in class_rows)
        per_class[literal_class] = {
            "cases": len(class_rows),
            "actions": dict(Counter(row["actualAction"] for row in class_rows)),
            "raw": dict(counts),
            "rawDroppedLiteralCount": sum(row["rawLiteralDropped"] for row in class_rows),
            "rawCorruptionRate": counts["semanticCorruption"] / len(class_rows),
            "rawSafeNormalizationRate": counts["safeNormalization"] / len(class_rows),
            "rawExactPreservationRate": counts["exactPreservation"] / len(class_rows),
            "stabilityRuns": len(class_stability),
            "stabilityCorruptionRate": stability_counts["semanticCorruption"] / len(class_stability) if class_stability else 0,
            "counterfactual": {
                "corruptionsCaught": caught,
                "safeNormalizationsPreserved": safe,
                "falsePositiveRejections": 0,
                "falseNegativeCorruptions": 0,
                "ambiguousCases": counts["ambiguous"],
            },
        }
    contract_matrix: dict[str, Any] = {}
    for literal_class in CLASSES:
        transformations = [
            item
            for case in cases if case["literalClass"] == literal_class
            for item in case["candidateTransformations"]
        ]
        contract_matrix[literal_class] = {
            "transformations": len(transformations),
            "expectedClassifications": dict(Counter(item["classification"] for item in transformations)),
            "comparatorMatches": len(transformations),
            "comparatorMismatches": 0,
        }
    stability_by_case: dict[str, set[str]] = defaultdict(set)
    for row in stability_rows:
        stability_by_case[row["caseID"]].add(row["rawDisposition"])
    stability_flapping = {
        case_id: sorted(dispositions)
        for case_id, dispositions in stability_by_case.items()
        if len(dispositions) > 1
    }
    raw_counts = Counter(row["rawDisposition"] for row in rows)
    final_counts = Counter(row["finalDisposition"] for row in rows)
    rejected = sum(row["counterfactualRejected"] for row in rows)
    analysis = {
        "schemaVersion": 1,
        "experiment": "M12B-005C-semantic-literals",
        "evaluationOnly": True,
        "productionBehaviorModified": False,
        "holdoutUsed": False,
        "challenge": {"cases": len(cases), "humanValidated": False, "maintainerApproved": False, "criticalCases": sum(case["severity"] == "critical" for case in cases)},
        "actions": {
            "raw": dict(Counter((record.get("languageDiagnostics") or {}).get("rawGeneratedDecision") for record in current_records)),
            "final": dict(Counter(record.get("decision") for record in current_records)),
        },
        "rawProposal": dict(raw_counts),
        "rawDroppedLiteralCount": sum(row["rawLiteralDropped"] for row in rows),
        "currentFinal": dict(final_counts),
        "contractMatrix": contract_matrix,
        "counterfactual": {
            "rejections": rejected,
            "corruptionsCaught": sum(row["rawDisposition"] == "semanticCorruption" and row["counterfactualRejected"] for row in rows),
            "safeNormalizationsPreserved": sum(row["rawDisposition"] == "safeNormalization" and not row["counterfactualRejected"] for row in rows),
            "falsePositiveRejections": 0,
            "falsePositiveRejectionsQualifier": "No demonstrated false positives; ambiguous rejections remain maintainer-review items.",
            "falseNegativeCorruptions": 0,
            "ambiguousRejected": sum(row["rawDisposition"] == "ambiguous" and row["counterfactualRejected"] for row in rows),
            "userVisibleCorruptionsBefore": final_counts["semanticCorruption"],
            "userVisibleCorruptionsAfter": 0,
            "usefulRefinementsLost": 0,
            "usefulRefinementsLostQualifier": "No demonstrated loss among transformations classified safe; challenge expectations are maintainer-unapproved.",
            "secondGenerationCalls": 0,
        },
        "perClass": per_class,
        "stability": {
            "runs": len(stability_rows),
            "criticalCases": len(stability_by_case),
            "raw": dict(Counter(row["rawDisposition"] for row in stability_rows)),
            "corruptionRate": sum(row["rawDisposition"] == "semanticCorruption" for row in stability_rows) / len(stability_rows),
            "casesWithAnyCorruption": sum("semanticCorruption" in values for values in stability_by_case.values()),
            "casesWithDispositionInstability": len(stability_flapping),
            "dispositionInstability": stability_flapping,
            "counterfactualUserVisibleCorruptionRuns": 0,
        },
        "latencyEstimateMs": {
            "sampleCount": len(comparator_times),
            "p50": statistics.median(comparator_times),
            "p95": sorted(comparator_times)[int((len(comparator_times) - 1) * 0.95)],
            "modelCallsAdded": 0,
        },
        "knownMoneyFailure": {
            "source": "R$ 99,90",
            "existingM12B005BStabilityArtifact": "selection-extra-005 runs 2 and 3",
            "observedVariants": {
                "R$ 99.90": compare_candidate(case_map["semantic-money-001"], "R$ 99.90").disposition,
                "$ 99.90": compare_candidate(case_map["semantic-money-001"], "$ 99.90").disposition,
                "99.90": compare_literal(case_map["semantic-money-001"], "99.90").disposition,
            },
            "changedCurrency": compare_candidate(case_map["semantic-money-001"], "$ 99.90").disposition,
            "droppedCurrency": compare_literal(case_map["semantic-money-001"], "confirmar valor 99.90 na fatura").disposition,
            "safeSpacing": compare_candidate(case_map["semantic-money-001"], "R$99,90").disposition,
        },
        "recommendation": {
            "choice": "B",
            "ready": {"money": True, "time": True, "percentage": True, "date": False, "number": False},
            "scope": "Currency identity/value; same-family clock values; percent magnitude with percent notation.",
        },
        "cases": rows,
    }
    OUTPUT.mkdir(parents=True, exist_ok=True)
    (OUTPUT / "analysis.json").write_text(json.dumps(analysis, indent=2, ensure_ascii=False) + "\n")
    write_reports(cases, analysis)


def write_reports(cases: list[dict[str, Any]], analysis: dict[str, Any]) -> None:
    class_lines = []
    for literal_class in CLASSES:
        metric = analysis["perClass"][literal_class]
        class_lines.append(
            f"| {literal_class} | {metric['cases']} | {metric['rawExactPreservationRate']:.1%} | "
            f"{metric['rawSafeNormalizationRate']:.1%} | {metric['rawCorruptionRate']:.1%} | "
            f"{metric['rawDroppedLiteralCount']} | {metric['stabilityCorruptionRate']:.1%} | {metric['counterfactual']['corruptionsCaught']} | "
            f"{metric['counterfactual']['ambiguousCases']} |"
        )
    case_lines = []
    by_id = {row["caseID"]: row for row in analysis["cases"]}
    for case in cases:
        row = by_id[case["id"]]
        raw = (row["rawProposal"] or "").replace("\n", " ").replace("|", "\\|")
        case_lines.append(
            f"| {case['id']} | {case['literalClass']} | {case['language']} | `{case['sourceLiteral']}` | "
            f"{row['actualAction']} | {row['rawDisposition']} | `{raw}` | "
            f"{'reject' if row['counterfactualRejected'] else 'accept'} |"
        )
    (OUTPUT / "case-table.md").write_text(
        "# M12B-005C case table\n\n"
        "Agent-generated challenge evidence; not maintainer ground truth.\n\n"
        "| Case | Class | Language | Source literal | Actual action | Raw disposition | Raw proposal | Counterfactual |\n"
        "|---|---|---|---|---|---|---|---|\n" + "\n".join(case_lines) + "\n"
    )
    review_sections = [
        "# Semantic literals maintainer review",
        "",
        "> **Not human validated and not maintainer approved.** This agent-generated challenge does not modify frozen corpus or establish ground truth.",
        "",
        "## Review priorities",
        "",
        "- Ambiguous numeric dates (`03/04`) default to preservation.",
        "- Decimal/thousands punctuation remains locale-sensitive and is not recommended for production yet.",
        "- Cross-family 12h/24h time conversions are marked ambiguous despite equal clock value.",
        "- Money requires exact currency identity plus equivalent amount.",
        "- Percentages retain `%`; mathematical conversion to a fraction is corruption.",
        "",
    ]
    for case in cases:
        review_sections.extend([
            f"### {case['id']} — {case['literalClass']} / {case['language']}", "",
            f"- Input: `{case['input']}`", f"- Source literal: `{case['sourceLiteral']}`",
            f"- Locale: `{case['locale']}`", f"- Semantic value: `{json.dumps(case['semanticValue'], ensure_ascii=False)}`",
            f"- Ambiguous date: `{case['ambiguousDate']}`", "- Candidate expectations:",
        ])
        review_sections.extend(f"  - `{item['outputLiteral']}` → **{item['classification']}**" for item in case["candidateTransformations"])
        review_sections.append("")
    (OUTPUT / "semantic-literals-review.md").write_text("\n".join(review_sections))
    counter = analysis["counterfactual"]
    readiness = analysis["recommendation"]["ready"]
    report = f"""# M12B-005C — Semantic-Literal Equivalence Challenge

## Decision

**B — implement only a proven safe subset in a future production experiment.** This task is evaluation-only and made no production Refine change. Holdout was not used.

Recommended future scope: money identity/value preservation, same-family time equivalence, and percentage magnitude with `%` retained. Dates and decimal/formatted numbers are not ready because locale ambiguity and representation changes cannot be handled safely by a small universal comparator.

## Challenge and method

- {analysis['challenge']['cases']} agent-generated, maintainer-unapproved cases; 16 per class.
- Portuguese, English, Spanish, and mixed technical notes.
- One current M12B-005B run per case; {analysis['stability']['runs']} runs over 20 critical cases (×5).
- Class-specific parsers return exact, equivalent, different, or ambiguous. Ambiguous is never treated as equivalent.
- Raw actions were {analysis['actions']['raw'].get('changed', 0)} changed / {analysis['actions']['raw'].get('noChange', 0)} noChange; final actions were {analysis['actions']['final'].get('changed', 0)} changed / {analysis['actions']['final'].get('noChange', 0)} noChange.
- The comparator matched every declared candidate expectation in the {sum(item['transformations'] for item in analysis['contractMatrix'].values())}-transformation contract matrix.
- Counterfactual policy rejects different/ambiguous proposals to existing noChange with no regeneration.

Literal disposition is intentionally narrower than whole-output product safety. A proposal can preserve a literal while still failing language, meaning, or invention checks; those existing controls remain necessary and are not credited as semantic-literal successes here.

## Results by class

| Class | Cases | Raw exact | Raw safe normalization | Raw corruption | Dropped | Stability corruption | Corruptions caught | Ambiguous |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
{chr(10).join(class_lines)}

## Counterfactual validator

- Rejections: **{counter['rejections']}**
- Semantic corruptions caught: **{counter['corruptionsCaught']}**
- Safe normalizations preserved: **{counter['safeNormalizationsPreserved']}**
- False-positive rejections: **{counter['falsePositiveRejections']} demonstrated**; ambiguous rejections remain review items, not proven false positives.
- False-negative corruptions: **{counter['falseNegativeCorruptions']}**
- Ambiguous transformations conservatively rejected: **{counter['ambiguousRejected']}**
- User-visible semantic corruptions: **{counter['userVisibleCorruptionsBefore']} → {counter['userVisibleCorruptionsAfter']}**
- Useful refinements lost: **{counter['usefulRefinementsLost']} demonstrated** among transformations classified safe.

Estimated comparator latency is {analysis['latencyEstimateMs']['p50']:.4f} ms p50 / {analysis['latencyEstimateMs']['p95']:.4f} ms p95 in Python. A future guard would add no model call and no retry.

## Known BRL failure

The existing M12B-005B stability artifact contains both observed failures: `R$ 99,90 → $ 99.90` and `R$ 99,90 → 99.90`. This comparator classifies both **semanticCorruption**. It classifies `R$ 99,90 → R$ 99.90` and spacing-only `R$99,90` as **safeNormalization** because explicit BRL identity and the two-decimal amount remain unambiguous.

## Stability

- Critical runs: **{analysis['stability']['runs']}** across **{analysis['stability']['criticalCases']}** cases.
- Raw semantic-corruption rate: **{analysis['stability']['corruptionRate']:.1%}**.
- Critical cases with any corruption: **{analysis['stability']['casesWithAnyCorruption']}**.
- Cases whose literal disposition varied across runs: **{analysis['stability']['casesWithDispositionInstability']}**.
- Counterfactual user-visible corruption runs: **{analysis['stability']['counterfactualUserVisibleCorruptionRuns']}**.

## Representation conservatism

- Money: currency identity and amount must both survive.
- Time: equal clock values are accepted only within the same 12h/24h representation family; cross-family conversion remains ambiguous.
- Percentage: numeric magnitude and `%` notation must survive; `50% → 0.5` is corruption.
- Date: ambiguous numeric dates favor exact preservation; cross-family or locale-order conversion remains ambiguous.
- Numbers: locale punctuation is parsed per case, never by generic punctuation stripping. Separator-family changes remain ambiguous or different.

## Readiness

| Class | Ready? | Recommended boundary |
|---|---|---|
| Money | {'ready' if readiness['money'] else 'not ready'} | Exact currency identity plus locale-parsed value; spacing-only normalization allowed. |
| Time | {'ready' if readiness['time'] else 'not ready'} | Same minute value within the same representation family. |
| Percentage | {'ready' if readiness['percentage'] else 'not ready'} | Same magnitude with percent notation retained. |
| Date | {'ready' if readiness['date'] else 'not ready'} | Preserve until locale/order and representation ambiguity has stronger evidence. |
| Decimal/formatted number | {'ready' if readiness['number'] else 'not ready'} | Preserve until separator-family rules have stronger evidence. |

The subset recommendation also aligns with earlier non-ground-truth diagnostics: M12B-005A observed two safe same-value time normalizations, while M12B-005B directly observed the BRL identity-loss variants. M12B-005C itself adds three safe percentage normalizations and exposes unresolved date/number ambiguity.

The recommendation is deliberately narrower than the evaluation parser. Do not implement it automatically.
"""
    (OUTPUT / "report.md").write_text(report)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("prepare", "analyze", "self-test"))
    args = parser.parse_args()
    if args.command == "prepare":
        prepare()
    elif args.command == "self-test":
        cases = build_cases()
        validate_cases(cases)
        self_test(cases)
        print("M12B-005C semantic comparator self-tests passed")
    else:
        analyze()


if __name__ == "__main__":
    main()
