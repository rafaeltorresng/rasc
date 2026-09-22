# M12B-007D case table

| caseID | cohort | expected | resolver-v2 | conf | raw out | validator | final | outcome | primary cause | rationale |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `acronym-004` | wrongLanguage | en | `ambiguous` | insufficient | `pt` | skipped | changed | unsafe_wrong_language | **resolverUnresolved** | Independent NaturalLanguage/marker assessment disagrees on output language. |
| `already-good-010` | falseRejection | pt | `pt` | high | `pt` | rejected | noChange | safe | **validatorTooAggressive** | Independent NaturalLanguage/marker assessment disagrees on output language. |
| `incomplete-006` | falseRejection | pt | `pt` | high | `pt` | rejected | noChange | safe | **languageEvaluatorWrong** | Independent NaturalLanguage/marker assessment disagrees on output language. |
| `injection-004` | falseRejection | unknown | `en` | high | `en` | rejected | noChange | safe | **validatorTooAggressive** | Independent NaturalLanguage/marker assessment disagrees on output language. |
| `legacy-selection-unicode-pt-001` | wrongLanguage | pt | `pt` | high | `id` | passed | changed | unsafe_wrong_language | **validatorMissedMismatch** | Independent NaturalLanguage/marker assessment disagrees on output language. |
| `medium-pt-010` | falseRejection | pt | `pt` | high | `pt` | rejected | noChange | safe | **validatorTooAggressive** | Independent NaturalLanguage/marker assessment disagrees on output language. |
| `meeting-dump-003` | wrongLanguage | pt | `en` | high | `en` | passed | changed | unsafe_wrong_language | **resolverWrongHighConfidence** | Resolver chose english but dataset expects pt. |
| `mixed-tech-004` | falseRejection | mixed | `en` | high | `en` | rejected | noChange | safe | **mixedTechnicalMisclassified** | Independent NaturalLanguage/marker assessment disagrees on output language. |
| `mixed-tech-008` | falseRejection | mixed | `en` | high | `en` | rejected | noChange | safe | **mixedTechnicalMisclassified** | Independent NaturalLanguage/marker assessment disagrees on output language. |
| `names-004` | falseRejection | en | `en` | high | `en` | rejected | noChange | safe | **validatorTooAggressive** | Independent NaturalLanguage/marker assessment disagrees on output language. |
| `numbers-002` | falseRejection | en | `en` | high | `en` | rejected | noChange | safe | **validatorTooAggressive** | Independent NaturalLanguage/marker assessment disagrees on output language. |
| `numbers-003` | wrongLanguage | pt | `pt` | high | `en` | passed | changed | unsafe_wrong_language | **validatorMissedMismatch** | Independent NaturalLanguage/marker assessment disagrees on output language. |
| `numbers-004` | falseRejection | en | `en` | high | `en` | rejected | noChange | safe | **validatorTooAggressive** | Independent NaturalLanguage/marker assessment disagrees on output language. |
| `numbers-005` | falseRejection | pt | `pt` | high | `pt` | rejected | noChange | safe | **validatorTooAggressive** | Independent NaturalLanguage/marker assessment disagrees on output language. |
| `selection-extra-001` | wrongLanguage | pt | `pt` | high | `en` | passed | changed | unsafe_wrong_language | **validatorMissedMismatch** | Unauthorized translation reached user-visible changed output. |
| `selection-extra-007` | wrongLanguage | pt | `ambiguous` | insufficient | `es` | skipped | changed | unsafe_wrong_language | **resolverUnresolved** | Independent NaturalLanguage/marker assessment disagrees on output language. |
| `selection-leak-test-007` | falseRejection | en | `en` | high | `en` | rejected | noChange | safe | **languageEvaluatorWrong** | Independent NaturalLanguage/marker assessment disagrees on output language. |
| `short-pt-009` | wrongLanguage | pt | `ambiguous` | insufficient | `en` | skipped | changed | unsafe_wrong_language | **resolverUnresolved** | Independent NaturalLanguage/marker assessment disagrees on output language. |
| `short-pt-012` | wrongLanguage | pt | `ambiguous` | insufficient | `en` | skipped | changed | unsafe_wrong_language | **resolverUnresolved** | Independent NaturalLanguage/marker assessment disagrees on output language. |
| `short-pt-013` | wrongLanguage | pt | `ambiguous` | insufficient | `en` | skipped | changed | unsafe_wrong_language | **resolverUnresolved** | Independent NaturalLanguage/marker assessment disagrees on output language. |
| `telegraphic-pt-001` | wrongLanguage | pt | `ambiguous` | insufficient | `en` | skipped | changed | unsafe_wrong_language | **resolverUnresolved** | Independent NaturalLanguage/marker assessment disagrees on output language. |
| `telegraphic-pt-004` | wrongLanguage | pt | `ambiguous` | insufficient | `en` | skipped | changed | unsafe_wrong_language | **resolverUnresolved** | Independent NaturalLanguage/marker assessment disagrees on output language. |
| `telegraphic-pt-005` | wrongLanguage | pt | `ambiguous` | insufficient | `en` | skipped | changed | unsafe_wrong_language | **resolverUnresolved** | Resolver left language unresolved; generation drift cannot be attributed confide |
| `telegraphic-pt-009` | wrongLanguage | pt | `ambiguous` | insufficient | `en` | skipped | changed | unsafe_wrong_language | **resolverUnresolved** | Independent NaturalLanguage/marker assessment disagrees on output language. |
| `telegraphic-pt-010` | wrongLanguage | pt | `ambiguous` | insufficient | `en` | skipped | changed | unsafe_wrong_language | **resolverUnresolved** | Independent NaturalLanguage/marker assessment disagrees on output language. |
| `uncertainty-pt-001` | falseRejection | pt | `pt` | high | `pt` | rejected | noChange | safe | **validatorTooAggressive** | Independent NaturalLanguage/marker assessment disagrees on output language. |
| `variant-pt-013` | wrongLanguage | pt | `ambiguous` | insufficient | `en` | skipped | changed | unsafe_wrong_language | **resolverUnresolved** | Resolver left language unresolved; generation drift cannot be attributed confide |
| `variant-pt-014` | wrongLanguage | pt | `ambiguous` | insufficient | `en` | skipped | changed | unsafe_wrong_language | **resolverUnresolved** | Legacy resolver used system fallback; generation drift cannot be attributed conf |
| `variant-pt-015` | wrongLanguage | pt | `ambiguous` | insufficient | `en` | skipped | changed | unsafe_wrong_language | **resolverUnresolved** | Independent NaturalLanguage/marker assessment disagrees on output language. |
| `variant-pt-022` | wrongLanguage | pt | `en` | high | `en` | passed | changed | unsafe_wrong_language | **resolverWrongHighConfidence** | Resolver chose english but dataset expects pt. |
| `variant-pt-023` | wrongLanguage | pt | `en` | high | `en` | passed | changed | unsafe_wrong_language | **resolverWrongHighConfidence** | Resolver chose english but dataset expects pt. |
| `variant-pt-024` | wrongLanguage | pt | `en` | high | `en` | passed | changed | unsafe_wrong_language | **resolverWrongHighConfidence** | Resolver chose english but dataset expects pt. |
| `variant-pt-028` | falseRejection | pt | `pt` | high | `pt` | rejected | noChange | safe | **validatorTooAggressive** | Independent NaturalLanguage/marker assessment disagrees on output language. |
