# M12B-001 Language Failure Root Causes (retroactive)

Retroactive classification from M12B-001 dev `results.json` without `languageTrace`.
M12B-002 adds full per-run diagnostics for future runs.

## Distribution

| Root cause | Count |
|---|---:|
| evaluator_disagreement | 11 |
| validator_false_negative | 9 |
| low_confidence_unclassifiable | 1 |

## Cases

| Case ID | Expected | Final decision | Root cause | Explanation |
|---|---|---|---|---|
| `already-good-001` | pt | changed | validator_false_negative | Unauthorized translation reached changed output (M12B-001 validator miss). |
| `already-good-006` | pt | changed | evaluator_disagreement | Drift flagged but heuristic classification uncertain without raw trace. |
| `es-003` | es | changed | validator_false_negative | Unauthorized translation reached changed output (M12B-001 validator miss). |
| `es-009` | es | changed | evaluator_disagreement | Drift flagged but heuristic classification uncertain without raw trace. |
| `factual-003` | pt | changed | evaluator_disagreement | Drift flagged but heuristic classification uncertain without raw trace. |
| `medium-pt-001` | pt | changed | validator_false_negative | Unauthorized translation reached changed output (M12B-001 validator miss). |
| `medium-pt-010` | pt | changed | validator_false_negative | Unauthorized translation reached changed output (M12B-001 validator miss). |
| `messy-003` | pt | changed | validator_false_negative | Unauthorized translation reached changed output (M12B-001 validator miss). |
| `question-003` | es | changed | validator_false_negative | Unauthorized translation reached changed output (M12B-001 validator miss). |
| `selection-extra-002` | pt | changed | low_confidence_unclassifiable | Tiny/short input; independent assessment requires review. |
| `variant-es-003` | es | changed | evaluator_disagreement | Drift flagged but heuristic classification uncertain without raw trace. |
| `variant-es-004` | es | changed | evaluator_disagreement | Drift flagged but heuristic classification uncertain without raw trace. |
| `variant-es-007` | es | changed | evaluator_disagreement | Drift flagged but heuristic classification uncertain without raw trace. |
| `variant-es-008` | es | changed | evaluator_disagreement | Drift flagged but heuristic classification uncertain without raw trace. |
| `variant-pt-002` | pt | changed | evaluator_disagreement | Drift flagged but heuristic classification uncertain without raw trace. |
| `variant-pt-004` | pt | changed | validator_false_negative | Unauthorized translation reached changed output (M12B-001 validator miss). |
| `variant-pt-005` | pt | changed | validator_false_negative | Unauthorized translation reached changed output (M12B-001 validator miss). |
| `variant-pt-008` | pt | changed | validator_false_negative | Unauthorized translation reached changed output (M12B-001 validator miss). |
| `variant-pt-012` | pt | changed | evaluator_disagreement | Drift flagged but heuristic classification uncertain without raw trace. |
| `variant-pt-021` | pt | changed | evaluator_disagreement | Drift flagged but heuristic classification uncertain without raw trace. |
| `variant-pt-028` | pt | changed | evaluator_disagreement | Drift flagged but heuristic classification uncertain without raw trace. |
