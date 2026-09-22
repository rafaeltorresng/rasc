# M12B-005C case table

Agent-generated challenge evidence; not maintainer ground truth.

| Case | Class | Language | Source literal | Actual action | Raw disposition | Raw proposal | Counterfactual |
|---|---|---|---|---|---|---|---|
| semantic-money-001 | money | pt | `R$ 99,90` | changed | safeNormalization | `Confirm value R$ 99.90 on the bill` | accept |
| semantic-money-002 | money | pt | `BRL 1.250,00` | changed | ambiguous | `Confirm the value of BRL 1.250.00 on the invoice` | reject |
| semantic-money-003 | money | pt | `R$300` | changed | exactPreservation | `Confirm value R$300 on invoice` | accept |
| semantic-money-004 | money | pt | `US$ 45,50` | changed | semanticCorruption | `Confirm the value of $45.50 on the invoice` | reject |
| semantic-money-005 | money | en | `$99.90` | changed | exactPreservation | `Confirm invoice amount $99.90 tomorrow` | accept |
| semantic-money-006 | money | en | `USD 1,250.00` | changed | exactPreservation | `Confirm invoice amount USD 1,250.00 tomorrow` | accept |
| semantic-money-007 | money | en | `€ 80.00` | changed | exactPreservation | `Confirm invoice amount € 80.00 tomorrow` | accept |
| semantic-money-008 | money | en | `EUR 2,500.50` | changed | exactPreservation | `Confirm invoice amount EUR 2,500.50 tomorrow` | accept |
| semantic-money-009 | money | es | `€ 99,90` | changed | exactPreservation | `Confirmar importe € 99,90 en la factura` | accept |
| semantic-money-010 | money | es | `EUR 1.250,00` | changed | exactPreservation | `Confirmar importe EUR 1.250,00 en la factura` | accept |
| semantic-money-011 | money | es | `USD 45,50` | noChange | exactPreservation | `confirmar importe USD 45,50 en la factura` | accept |
| semantic-money-012 | money | es | `€300` | changed | exactPreservation | `Confirmar importe €300 en la factura` | accept |
| semantic-money-013 | money | mixed | `R$ 99,90` | noChange | exactPreservation | `checkout total R$ 99,90 no billing` | accept |
| semantic-money-014 | money | mixed | `USD 120.00` | changed | exactPreservation | `Checkout total USD 120.00` | accept |
| semantic-money-015 | money | pt | `R$ 1.000,50` | changed | safeNormalization | `Confirm the value of R$ 1,000.50 on the bill` | accept |
| semantic-money-016 | money | en | `BRL 99.90` | changed | exactPreservation | `Confirm invoice amount BRL 99.90 tomorrow` | accept |
| semantic-time-001 | time | pt | `15h` | noChange | exactPreservation | `reunião marcada para 15h amanhã` | accept |
| semantic-time-002 | time | pt | `15h30` | changed | exactPreservation | `Reunião marcada para 15h30 amanhã` | accept |
| semantic-time-003 | time | pt | `09:00` | changed | exactPreservation | `Reunião marcada para 09:00 amanhã` | accept |
| semantic-time-004 | time | pt | `18:45` | changed | exactPreservation | `Reunião marcada para 18:45 amanhã` | accept |
| semantic-time-005 | time | en | `3 PM` | changed | exactPreservation | `Meeting scheduled for 3 PM tomorrow` | accept |
| semantic-time-006 | time | en | `3:30 PM` | changed | exactPreservation | `Meeting scheduled for 3:30 PM tomorrow` | accept |
| semantic-time-007 | time | en | `09:00` | noChange | exactPreservation | `meeting scheduled for 09:00 tomorrow` | accept |
| semantic-time-008 | time | en | `11 AM` | changed | exactPreservation | `Meeting scheduled for 11 AM tomorrow` | accept |
| semantic-time-009 | time | es | `15:00` | noChange | exactPreservation | `reunión prevista para 15:00 mañana` | accept |
| semantic-time-010 | time | es | `15h30` | noChange | exactPreservation | `reunión prevista para 15h30 mañana` | accept |
| semantic-time-011 | time | es | `09:15` | changed | safeNormalization | `Reunion programada para las 9:15 de la mañana` | accept |
| semantic-time-012 | time | es | `6 PM` | noChange | exactPreservation | `Reunion scheduled for 6 PM tomorrow` | accept |
| semantic-time-013 | time | mixed | `15h` | changed | exactPreservation | `Chamada de sincronização às 15h com o backend` | accept |
| semantic-time-014 | time | mixed | `3 PM` | noChange | exactPreservation | `sync call 3 PM com backend` | accept |
| semantic-time-015 | time | pt | `00:00` | changed | exactPreservation | `Reunião marcada para 00:00 amanhã` | accept |
| semantic-time-016 | time | en | `12 AM` | changed | exactPreservation | `Meeting scheduled for 12 AM tomorrow` | accept |
| semantic-percentage-001 | percentage | pt | `50%` | changed | exactPreservation | `La tasa actual quedó en 50% en el panel` | accept |
| semantic-percentage-002 | percentage | pt | `12,5%` | changed | safeNormalization | `La tasa actual se mantuvo en el 12.5% en el panel` | accept |
| semantic-percentage-003 | percentage | pt | `-3%` | noChange | exactPreservation | `taxa atual ficou em -3% no painel` | accept |
| semantic-percentage-004 | percentage | pt | `100 %` | changed | safeNormalization | `La tasa actual se estableció en 100% en el panel` | accept |
| semantic-percentage-005 | percentage | en | `50%` | changed | exactPreservation | `Current dashboard rate is 50% today` | accept |
| semantic-percentage-006 | percentage | en | `12.5%` | noChange | exactPreservation | `current dashboard rate is 12.5% today` | accept |
| semantic-percentage-007 | percentage | en | `-3%` | changed | exactPreservation | `Current dashboard rate is -3% today` | accept |
| semantic-percentage-008 | percentage | en | `100 %` | noChange | exactPreservation | `current dashboard rate is 100 % today` | accept |
| semantic-percentage-009 | percentage | es | `50%` | changed | exactPreservation | `La tasa actual quedó en 50%` | accept |
| semantic-percentage-010 | percentage | es | `12,5 %` | changed | exactPreservation | `La tasa actual quedó en 12,5 %` | accept |
| semantic-percentage-011 | percentage | es | `-3%` | changed | exactPreservation | `La tasa actual quedó en -3%` | accept |
| semantic-percentage-012 | percentage | es | `100%` | changed | exactPreservation | `La tasa actual quedó en 100%` | accept |
| semantic-percentage-013 | percentage | mixed | `99.9%` | changed | exactPreservation | `Rollout metric 99.9% no dashboard` | accept |
| semantic-percentage-014 | percentage | mixed | `0,5%` | noChange | exactPreservation | `rollout metric 0,5% no dashboard` | accept |
| semantic-percentage-015 | percentage | pt | `+5%` | changed | safeNormalization | `La tasa actual se incremento en 5% en el panel` | accept |
| semantic-percentage-016 | percentage | en | `0.5%` | changed | exactPreservation | `The current dashboard rate is 0.5% today` | accept |
| semantic-date-001 | date | pt | `31/12/2026` | changed | exactPreservation | `Prazo registrado como 31/12/2026 no contrato` | accept |
| semantic-date-002 | date | pt | `03/04` | noChange | exactPreservation | `prazo registrado como 03/04 no contrato` | accept |
| semantic-date-003 | date | pt | `2026-10-01` | changed | exactPreservation | `Prazo registrado como 2026-10-01 no contrato` | accept |
| semantic-date-004 | date | pt | `5 de maio de 2026` | changed | exactPreservation | `Prazo registrado como 5 de maio de 2026 no contrato` | accept |
| semantic-date-005 | date | en | `12/31/2026` | changed | exactPreservation | `Contract deadline recorded as 12/31/2026` | accept |
| semantic-date-006 | date | en | `03/04` | changed | exactPreservation | `contract deadline recorded as 03/04` | accept |
| semantic-date-007 | date | en | `2026-10-01` | changed | exactPreservation | `contract deadline recorded as 2026-10-01` | accept |
| semantic-date-008 | date | en | `May 5, 2026` | changed | exactPreservation | `Contract deadline recorded as May 5, 2026` | accept |
| semantic-date-009 | date | es | `31/12/2026` | changed | exactPreservation | `Fechada registrada como 31/12/2026 no contrato` | accept |
| semantic-date-010 | date | es | `03/04` | changed | ambiguous | `Registro fechado em 3/4` | reject |
| semantic-date-011 | date | es | `2026-10-01` | changed | ambiguous | `Registro fechado em 01/10/2026 no contrato` | reject |
| semantic-date-012 | date | es | `5 de mayo de 2026` | noChange | exactPreservation | `fecha registrada como 5 de mayo de 2026 en contrato` | accept |
| semantic-date-013 | date | mixed | `31/12/2026` | changed | ambiguous | `La fecha de lanzamiento es el 31 de diciembre de 2026, sin roadmap` | reject |
| semantic-date-014 | date | mixed | `03/04` | noChange | exactPreservation | `release date 03/04 no roadmap` | accept |
| semantic-date-015 | date | pt | `01/02/2027` | changed | exactPreservation | `Prazo registrado como 01/02/2027 no contrato` | accept |
| semantic-date-016 | date | en | `01/02/2027` | changed | exactPreservation | `Contract deadline recorded as 01/02/2027` | accept |
| semantic-number-001 | number | pt | `1,5` | changed | exactPreservation | `valor medido foi 1,5 no relatório` | accept |
| semantic-number-002 | number | pt | `1.000` | changed | exactPreservation | `Valor medido foi 1.000 no relatório` | accept |
| semantic-number-003 | number | pt | `1.000,50` | changed | exactPreservation | `Valor medido foi 1.000,50 no relatório` | accept |
| semantic-number-004 | number | pt | `2500` | noChange | exactPreservation | `valor medido foi 2500 no relatório` | accept |
| semantic-number-005 | number | en | `1.5` | changed | exactPreservation | `Measured value was 1.5 inches in the report` | accept |
| semantic-number-006 | number | en | `1,000` | noChange | exactPreservation | `measured value was 1,000 in report` | accept |
| semantic-number-007 | number | en | `1,000.50` | changed | safeNormalization | `measured value was 1000.50 in report` | accept |
| semantic-number-008 | number | en | `2500` | noChange | exactPreservation | `measured value was 2500 in report` | accept |
| semantic-number-009 | number | es | `1,5` | changed | ambiguous | `El valor medido fue 1.5 en el informe` | reject |
| semantic-number-010 | number | es | `1.000` | changed | exactPreservation | `El valor medido fue 1.000 en el informe` | accept |
| semantic-number-011 | number | es | `1.000,50` | changed | semanticCorruption | `El valor medido fue 1.000.50 en el informe` | reject |
| semantic-number-012 | number | es | `2500` | changed | exactPreservation | `El valor medido fue 2500 en el informe` | accept |
| semantic-number-013 | number | mixed | `1,5` | changed | exactPreservation | `Factor de latencia 1,5, sin referencia de punto de referencia` | accept |
| semantic-number-014 | number | mixed | `1.000` | changed | exactPreservation | `factor de latencia 1.000 sin referencia de benchmark` | accept |
| semantic-number-015 | number | pt | `10.000.000` | changed | exactPreservation | `Valor medido foi 10.000.000 no relatório` | accept |
| semantic-number-016 | number | en | `10,000,000` | changed | exactPreservation | `Measured value was 10,000,000 in report` | accept |
