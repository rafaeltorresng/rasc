# Validator policy — M12B-007E

Applied only when `resolved.enforcesPostValidation` is true (M12B-007B high-confidence resolver target).

## High-confidence independent match

If `NLLanguageRecognizer` dominant hypothesis ≥0.75 maps to the resolved target language:
→ **accept** (do not reject), even when marker detect disagrees.

## High-confidence independent mismatch

If independent assessment is high-confidence and maps to a different romance/English label than resolved:
→ **reject** to `noChange`.

## Low-confidence / requiresReview / medium

Preserve existing marker-based validator behavior.

## Unresolved resolver

Validation not enforced; unchanged from M12B-007B.

## Mixed technical language

Independent NL assessment reflects dominant natural language; English technical tokens inside Portuguese/Spanish output do not alone trigger rejection when NL confidence matches resolved target.
