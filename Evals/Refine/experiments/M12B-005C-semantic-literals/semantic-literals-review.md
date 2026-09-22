# Semantic literals maintainer review

> **Not human validated and not maintainer approved.** This agent-generated challenge does not modify frozen corpus or establish ground truth.

## Review priorities

- Ambiguous numeric dates (`03/04`) default to preservation.
- Decimal/thousands punctuation remains locale-sensitive and is not recommended for production yet.
- Cross-family 12h/24h time conversions are marked ambiguous despite equal clock value.
- Money requires exact currency identity plus equivalent amount.
- Percentages retain `%`; mathematical conversion to a fraction is corruption.

### semantic-money-001 — money / pt

- Input: `confirmar valor R$ 99,90 na fatura`
- Source literal: `R$ 99,90`
- Locale: `pt-BR`
- Semantic value: `{"amount": "99.90", "currency": "BRL"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `R$ 99,90` → **exactPreservation**
  - `R$99,90` → **safeNormalization**
  - `$99.90` → **semanticCorruption**
  - `R$ 99.90` → **safeNormalization**

### semantic-money-002 — money / pt

- Input: `confirmar valor BRL 1.250,00 na fatura`
- Source literal: `BRL 1.250,00`
- Locale: `pt-BR`
- Semantic value: `{"amount": "1250.00", "currency": "BRL"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `BRL 1.250,00` → **exactPreservation**
  - `BRL1.250,00` → **safeNormalization**
  - `$99.90` → **semanticCorruption**
  - `BRL 1.250.00` → **ambiguous**

### semantic-money-003 — money / pt

- Input: `confirmar valor R$300 na fatura`
- Source literal: `R$300`
- Locale: `pt-BR`
- Semantic value: `{"amount": "300", "currency": "BRL"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `R$300` → **exactPreservation**
  - `$99.90` → **semanticCorruption**

### semantic-money-004 — money / pt

- Input: `confirmar valor US$ 45,50 na fatura`
- Source literal: `US$ 45,50`
- Locale: `pt-BR`
- Semantic value: `{"amount": "45.50", "currency": "USD"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `US$ 45,50` → **exactPreservation**
  - `US$45,50` → **safeNormalization**
  - `EUR 99.90` → **semanticCorruption**
  - `US$ 45.50` → **safeNormalization**

### semantic-money-005 — money / en

- Input: `confirm invoice amount $99.90 tomorrow`
- Source literal: `$99.90`
- Locale: `en-US`
- Semantic value: `{"amount": "99.90", "currency": "USD"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `$99.90` → **exactPreservation**
  - `EUR 99.90` → **semanticCorruption**
  - `$99,90` → **safeNormalization**

### semantic-money-006 — money / en

- Input: `confirm invoice amount USD 1,250.00 tomorrow`
- Source literal: `USD 1,250.00`
- Locale: `en-US`
- Semantic value: `{"amount": "1250.00", "currency": "USD"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `USD 1,250.00` → **exactPreservation**
  - `USD1,250.00` → **safeNormalization**
  - `EUR 99.90` → **semanticCorruption**
  - `USD 1.250.00` → **ambiguous**

### semantic-money-007 — money / en

- Input: `confirm invoice amount € 80.00 tomorrow`
- Source literal: `€ 80.00`
- Locale: `en-US`
- Semantic value: `{"amount": "80.00", "currency": "EUR"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `€ 80.00` → **exactPreservation**
  - `€80.00` → **safeNormalization**
  - `USD 99.90` → **semanticCorruption**
  - `€ 80,00` → **safeNormalization**

### semantic-money-008 — money / en

- Input: `confirm invoice amount EUR 2,500.50 tomorrow`
- Source literal: `EUR 2,500.50`
- Locale: `en-US`
- Semantic value: `{"amount": "2500.50", "currency": "EUR"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `EUR 2,500.50` → **exactPreservation**
  - `EUR2,500.50` → **safeNormalization**
  - `USD 99.90` → **semanticCorruption**
  - `EUR 2.500.50` → **ambiguous**

### semantic-money-009 — money / es

- Input: `confirmar importe € 99,90 en la factura`
- Source literal: `€ 99,90`
- Locale: `es-ES`
- Semantic value: `{"amount": "99.90", "currency": "EUR"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `€ 99,90` → **exactPreservation**
  - `€99,90` → **safeNormalization**
  - `USD 99.90` → **semanticCorruption**
  - `€ 99.90` → **safeNormalization**

### semantic-money-010 — money / es

- Input: `confirmar importe EUR 1.250,00 en la factura`
- Source literal: `EUR 1.250,00`
- Locale: `es-ES`
- Semantic value: `{"amount": "1250.00", "currency": "EUR"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `EUR 1.250,00` → **exactPreservation**
  - `EUR1.250,00` → **safeNormalization**
  - `USD 99.90` → **semanticCorruption**
  - `EUR 1.250.00` → **ambiguous**

### semantic-money-011 — money / es

- Input: `confirmar importe USD 45,50 en la factura`
- Source literal: `USD 45,50`
- Locale: `es-ES`
- Semantic value: `{"amount": "45.50", "currency": "USD"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `USD 45,50` → **exactPreservation**
  - `USD45,50` → **safeNormalization**
  - `EUR 99.90` → **semanticCorruption**
  - `USD 45.50` → **safeNormalization**

### semantic-money-012 — money / es

- Input: `confirmar importe €300 en la factura`
- Source literal: `€300`
- Locale: `es-ES`
- Semantic value: `{"amount": "300", "currency": "EUR"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `€300` → **exactPreservation**
  - `USD 99.90` → **semanticCorruption**

### semantic-money-013 — money / mixed

- Input: `checkout total R$ 99,90 no billing`
- Source literal: `R$ 99,90`
- Locale: `pt-BR`
- Semantic value: `{"amount": "99.90", "currency": "BRL"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `R$ 99,90` → **exactPreservation**
  - `R$99,90` → **safeNormalization**
  - `$99.90` → **semanticCorruption**
  - `R$ 99.90` → **safeNormalization**

### semantic-money-014 — money / mixed

- Input: `checkout total USD 120.00 no billing`
- Source literal: `USD 120.00`
- Locale: `pt-BR`
- Semantic value: `{"amount": "120.00", "currency": "USD"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `USD 120.00` → **exactPreservation**
  - `USD120.00` → **safeNormalization**
  - `EUR 99.90` → **semanticCorruption**
  - `USD 120,00` → **safeNormalization**

### semantic-money-015 — money / pt

- Input: `confirmar valor R$ 1.000,50 na fatura`
- Source literal: `R$ 1.000,50`
- Locale: `pt-BR`
- Semantic value: `{"amount": "1000.50", "currency": "BRL"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `R$ 1.000,50` → **exactPreservation**
  - `R$1.000,50` → **safeNormalization**
  - `$99.90` → **semanticCorruption**
  - `R$ 1.000.50` → **ambiguous**

### semantic-money-016 — money / en

- Input: `confirm invoice amount BRL 99.90 tomorrow`
- Source literal: `BRL 99.90`
- Locale: `en-US`
- Semantic value: `{"amount": "99.90", "currency": "BRL"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `BRL 99.90` → **exactPreservation**
  - `BRL99.90` → **safeNormalization**
  - `$99.90` → **semanticCorruption**
  - `BRL 99,90` → **safeNormalization**

### semantic-time-001 — time / pt

- Input: `reunião marcada para 15h amanhã`
- Source literal: `15h`
- Locale: `pt-BR`
- Semantic value: `{"minutes": 900}`
- Ambiguous date: `False`
- Candidate expectations:
  - `15h` → **exactPreservation**
  - `15:00` → **safeNormalization**
  - `17:00` → **semanticCorruption**
  - `3:00 PM` → **ambiguous**

### semantic-time-002 — time / pt

- Input: `reunião marcada para 15h30 amanhã`
- Source literal: `15h30`
- Locale: `pt-BR`
- Semantic value: `{"minutes": 930}`
- Ambiguous date: `False`
- Candidate expectations:
  - `15h30` → **exactPreservation**
  - `15:30` → **safeNormalization**
  - `17:30` → **semanticCorruption**
  - `3:30 PM` → **ambiguous**

### semantic-time-003 — time / pt

- Input: `reunião marcada para 09:00 amanhã`
- Source literal: `09:00`
- Locale: `pt-BR`
- Semantic value: `{"minutes": 540}`
- Ambiguous date: `False`
- Candidate expectations:
  - `09:00` → **exactPreservation**
  - `11:00` → **semanticCorruption**
  - `9:00 AM` → **ambiguous**

### semantic-time-004 — time / pt

- Input: `reunião marcada para 18:45 amanhã`
- Source literal: `18:45`
- Locale: `pt-BR`
- Semantic value: `{"minutes": 1125}`
- Ambiguous date: `False`
- Candidate expectations:
  - `18:45` → **exactPreservation**
  - `20:45` → **semanticCorruption**
  - `6:45 PM` → **ambiguous**

### semantic-time-005 — time / en

- Input: `meeting scheduled for 3 PM tomorrow`
- Source literal: `3 PM`
- Locale: `en-US`
- Semantic value: `{"minutes": 900}`
- Ambiguous date: `False`
- Candidate expectations:
  - `3 PM` → **exactPreservation**
  - `3PM` → **safeNormalization**
  - `17:00` → **semanticCorruption**
  - `3:00 PM` → **safeNormalization**

### semantic-time-006 — time / en

- Input: `meeting scheduled for 3:30 PM tomorrow`
- Source literal: `3:30 PM`
- Locale: `en-US`
- Semantic value: `{"minutes": 930}`
- Ambiguous date: `False`
- Candidate expectations:
  - `3:30 PM` → **exactPreservation**
  - `3:30PM` → **safeNormalization**
  - `17:30` → **semanticCorruption**

### semantic-time-007 — time / en

- Input: `meeting scheduled for 09:00 tomorrow`
- Source literal: `09:00`
- Locale: `en-US`
- Semantic value: `{"minutes": 540}`
- Ambiguous date: `False`
- Candidate expectations:
  - `09:00` → **exactPreservation**
  - `11:00` → **semanticCorruption**
  - `9:00 AM` → **ambiguous**

### semantic-time-008 — time / en

- Input: `meeting scheduled for 11 AM tomorrow`
- Source literal: `11 AM`
- Locale: `en-US`
- Semantic value: `{"minutes": 660}`
- Ambiguous date: `False`
- Candidate expectations:
  - `11 AM` → **exactPreservation**
  - `11AM` → **safeNormalization**
  - `13:00` → **semanticCorruption**
  - `11:00 AM` → **safeNormalization**

### semantic-time-009 — time / es

- Input: `reunión prevista para 15:00 mañana`
- Source literal: `15:00`
- Locale: `es-ES`
- Semantic value: `{"minutes": 900}`
- Ambiguous date: `False`
- Candidate expectations:
  - `15:00` → **exactPreservation**
  - `17:00` → **semanticCorruption**
  - `3:00 PM` → **ambiguous**

### semantic-time-010 — time / es

- Input: `reunión prevista para 15h30 mañana`
- Source literal: `15h30`
- Locale: `es-ES`
- Semantic value: `{"minutes": 930}`
- Ambiguous date: `False`
- Candidate expectations:
  - `15h30` → **exactPreservation**
  - `15:30` → **safeNormalization**
  - `17:30` → **semanticCorruption**
  - `3:30 PM` → **ambiguous**

### semantic-time-011 — time / es

- Input: `reunión prevista para 09:15 mañana`
- Source literal: `09:15`
- Locale: `es-ES`
- Semantic value: `{"minutes": 555}`
- Ambiguous date: `False`
- Candidate expectations:
  - `09:15` → **exactPreservation**
  - `11:15` → **semanticCorruption**
  - `9:15 AM` → **ambiguous**

### semantic-time-012 — time / es

- Input: `reunión prevista para 6 PM mañana`
- Source literal: `6 PM`
- Locale: `es-ES`
- Semantic value: `{"minutes": 1080}`
- Ambiguous date: `False`
- Candidate expectations:
  - `6 PM` → **exactPreservation**
  - `6PM` → **safeNormalization**
  - `20:00` → **semanticCorruption**
  - `6:00 PM` → **safeNormalization**

### semantic-time-013 — time / mixed

- Input: `sync call 15h com backend`
- Source literal: `15h`
- Locale: `pt-BR`
- Semantic value: `{"minutes": 900}`
- Ambiguous date: `False`
- Candidate expectations:
  - `15h` → **exactPreservation**
  - `15:00` → **safeNormalization**
  - `17:00` → **semanticCorruption**
  - `3:00 PM` → **ambiguous**

### semantic-time-014 — time / mixed

- Input: `sync call 3 PM com backend`
- Source literal: `3 PM`
- Locale: `pt-BR`
- Semantic value: `{"minutes": 900}`
- Ambiguous date: `False`
- Candidate expectations:
  - `3 PM` → **exactPreservation**
  - `3PM` → **safeNormalization**
  - `17:00` → **semanticCorruption**
  - `3:00 PM` → **safeNormalization**

### semantic-time-015 — time / pt

- Input: `reunião marcada para 00:00 amanhã`
- Source literal: `00:00`
- Locale: `pt-BR`
- Semantic value: `{"minutes": 0}`
- Ambiguous date: `False`
- Candidate expectations:
  - `00:00` → **exactPreservation**
  - `02:00` → **semanticCorruption**
  - `12:00 AM` → **ambiguous**

### semantic-time-016 — time / en

- Input: `meeting scheduled for 12 AM tomorrow`
- Source literal: `12 AM`
- Locale: `en-US`
- Semantic value: `{"minutes": 0}`
- Ambiguous date: `False`
- Candidate expectations:
  - `12 AM` → **exactPreservation**
  - `12AM` → **safeNormalization**
  - `02:00` → **semanticCorruption**
  - `12:00 AM` → **safeNormalization**

### semantic-percentage-001 — percentage / pt

- Input: `taxa atual ficou em 50% no painel`
- Source literal: `50%`
- Locale: `pt-BR`
- Semantic value: `{"value": "50"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `50%` → **exactPreservation**
  - `50 %` → **safeNormalization**
  - `15%` → **semanticCorruption**
  - `0.5` → **semanticCorruption**

### semantic-percentage-002 — percentage / pt

- Input: `taxa atual ficou em 12,5% no painel`
- Source literal: `12,5%`
- Locale: `pt-BR`
- Semantic value: `{"value": "12.5"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `12,5%` → **exactPreservation**
  - `12,5 %` → **safeNormalization**
  - `15%` → **semanticCorruption**
  - `0.125` → **semanticCorruption**

### semantic-percentage-003 — percentage / pt

- Input: `taxa atual ficou em -3% no painel`
- Source literal: `-3%`
- Locale: `pt-BR`
- Semantic value: `{"value": "-3"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `-3%` → **exactPreservation**
  - `-3 %` → **safeNormalization**
  - `15%` → **semanticCorruption**
  - `-0.03` → **semanticCorruption**

### semantic-percentage-004 — percentage / pt

- Input: `taxa atual ficou em 100 % no painel`
- Source literal: `100 %`
- Locale: `pt-BR`
- Semantic value: `{"value": "100"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `100 %` → **exactPreservation**
  - `100%` → **safeNormalization**
  - `15 %` → **semanticCorruption**
  - `1` → **semanticCorruption**

### semantic-percentage-005 — percentage / en

- Input: `current dashboard rate is 50% today`
- Source literal: `50%`
- Locale: `en-US`
- Semantic value: `{"value": "50"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `50%` → **exactPreservation**
  - `50 %` → **safeNormalization**
  - `15%` → **semanticCorruption**
  - `0.5` → **semanticCorruption**

### semantic-percentage-006 — percentage / en

- Input: `current dashboard rate is 12.5% today`
- Source literal: `12.5%`
- Locale: `en-US`
- Semantic value: `{"value": "12.5"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `12.5%` → **exactPreservation**
  - `12.5 %` → **safeNormalization**
  - `15%` → **semanticCorruption**
  - `0.125` → **semanticCorruption**

### semantic-percentage-007 — percentage / en

- Input: `current dashboard rate is -3% today`
- Source literal: `-3%`
- Locale: `en-US`
- Semantic value: `{"value": "-3"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `-3%` → **exactPreservation**
  - `-3 %` → **safeNormalization**
  - `15%` → **semanticCorruption**
  - `-0.03` → **semanticCorruption**

### semantic-percentage-008 — percentage / en

- Input: `current dashboard rate is 100 % today`
- Source literal: `100 %`
- Locale: `en-US`
- Semantic value: `{"value": "100"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `100 %` → **exactPreservation**
  - `100%` → **safeNormalization**
  - `15 %` → **semanticCorruption**
  - `1` → **semanticCorruption**

### semantic-percentage-009 — percentage / es

- Input: `la tasa actual quedó en 50%`
- Source literal: `50%`
- Locale: `es-ES`
- Semantic value: `{"value": "50"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `50%` → **exactPreservation**
  - `50 %` → **safeNormalization**
  - `15%` → **semanticCorruption**
  - `0.5` → **semanticCorruption**

### semantic-percentage-010 — percentage / es

- Input: `la tasa actual quedó en 12,5 %`
- Source literal: `12,5 %`
- Locale: `es-ES`
- Semantic value: `{"value": "12.5"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `12,5 %` → **exactPreservation**
  - `12,5%` → **safeNormalization**
  - `15 %` → **semanticCorruption**
  - `0.125` → **semanticCorruption**

### semantic-percentage-011 — percentage / es

- Input: `la tasa actual quedó en -3%`
- Source literal: `-3%`
- Locale: `es-ES`
- Semantic value: `{"value": "-3"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `-3%` → **exactPreservation**
  - `-3 %` → **safeNormalization**
  - `15%` → **semanticCorruption**
  - `-0.03` → **semanticCorruption**

### semantic-percentage-012 — percentage / es

- Input: `la tasa actual quedó en 100%`
- Source literal: `100%`
- Locale: `es-ES`
- Semantic value: `{"value": "100"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `100%` → **exactPreservation**
  - `100 %` → **safeNormalization**
  - `15%` → **semanticCorruption**
  - `1` → **semanticCorruption**

### semantic-percentage-013 — percentage / mixed

- Input: `rollout metric 99.9% no dashboard`
- Source literal: `99.9%`
- Locale: `pt-BR`
- Semantic value: `{"value": "99.9"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `99.9%` → **exactPreservation**
  - `99.9 %` → **safeNormalization**
  - `15%` → **semanticCorruption**
  - `0.999` → **semanticCorruption**

### semantic-percentage-014 — percentage / mixed

- Input: `rollout metric 0,5% no dashboard`
- Source literal: `0,5%`
- Locale: `pt-BR`
- Semantic value: `{"value": "0.5"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `0,5%` → **exactPreservation**
  - `0,5 %` → **safeNormalization**
  - `15%` → **semanticCorruption**
  - `0.005` → **semanticCorruption**

### semantic-percentage-015 — percentage / pt

- Input: `taxa atual ficou em +5% no painel`
- Source literal: `+5%`
- Locale: `pt-BR`
- Semantic value: `{"value": "5"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `+5%` → **exactPreservation**
  - `+5 %` → **safeNormalization**
  - `15%` → **semanticCorruption**
  - `0.05` → **semanticCorruption**

### semantic-percentage-016 — percentage / en

- Input: `current dashboard rate is 0.5% today`
- Source literal: `0.5%`
- Locale: `en-US`
- Semantic value: `{"value": "0.5"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `0.5%` → **exactPreservation**
  - `0.5 %` → **safeNormalization**
  - `15%` → **semanticCorruption**
  - `0.005` → **semanticCorruption**

### semantic-date-001 — date / pt

- Input: `prazo registrado como 31/12/2026 no contrato`
- Source literal: `31/12/2026`
- Locale: `pt-BR`
- Semantic value: `{"iso": "2026-12-31"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `31/12/2026` → **exactPreservation**
  - `12/31/2026` → **semanticCorruption**
  - `3 de abril` → **ambiguous**

### semantic-date-002 — date / pt

- Input: `prazo registrado como 03/04 no contrato`
- Source literal: `03/04`
- Locale: `pt-BR`
- Semantic value: `null`
- Ambiguous date: `True`
- Candidate expectations:
  - `03/04` → **exactPreservation**
  - `12/31/2026` → **ambiguous**
  - `3 de abril` → **ambiguous**

### semantic-date-003 — date / pt

- Input: `prazo registrado como 2026-10-01 no contrato`
- Source literal: `2026-10-01`
- Locale: `pt-BR`
- Semantic value: `{"iso": "2026-10-01"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `2026-10-01` → **exactPreservation**
  - `12/31/2026` → **semanticCorruption**
  - `3 de abril` → **ambiguous**

### semantic-date-004 — date / pt

- Input: `prazo registrado como 5 de maio de 2026 no contrato`
- Source literal: `5 de maio de 2026`
- Locale: `pt-BR`
- Semantic value: `{"iso": "2026-05-05"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `5 de maio de 2026` → **exactPreservation**
  - `12/31/2026` → **semanticCorruption**
  - `3 de abril` → **ambiguous**

### semantic-date-005 — date / en

- Input: `contract deadline recorded as 12/31/2026`
- Source literal: `12/31/2026`
- Locale: `en-US`
- Semantic value: `{"iso": "2026-12-31"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `12/31/2026` → **exactPreservation**
  - `31/12/2026` → **semanticCorruption**
  - `April 3` → **ambiguous**

### semantic-date-006 — date / en

- Input: `contract deadline recorded as 03/04`
- Source literal: `03/04`
- Locale: `en-US`
- Semantic value: `null`
- Ambiguous date: `True`
- Candidate expectations:
  - `03/04` → **exactPreservation**
  - `31/12/2026` → **ambiguous**
  - `April 3` → **ambiguous**

### semantic-date-007 — date / en

- Input: `contract deadline recorded as 2026-10-01`
- Source literal: `2026-10-01`
- Locale: `en-US`
- Semantic value: `{"iso": "2026-10-01"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `2026-10-01` → **exactPreservation**
  - `31/12/2026` → **semanticCorruption**
  - `April 3` → **ambiguous**

### semantic-date-008 — date / en

- Input: `contract deadline recorded as May 5, 2026`
- Source literal: `May 5, 2026`
- Locale: `en-US`
- Semantic value: `{"iso": "2026-05-05"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `May 5, 2026` → **exactPreservation**
  - `31/12/2026` → **semanticCorruption**
  - `April 3` → **ambiguous**

### semantic-date-009 — date / es

- Input: `fecha registrada como 31/12/2026 en contrato`
- Source literal: `31/12/2026`
- Locale: `es-ES`
- Semantic value: `{"iso": "2026-12-31"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `31/12/2026` → **exactPreservation**
  - `12/31/2026` → **semanticCorruption**
  - `3 de abril` → **ambiguous**

### semantic-date-010 — date / es

- Input: `fecha registrada como 03/04 en contrato`
- Source literal: `03/04`
- Locale: `es-ES`
- Semantic value: `null`
- Ambiguous date: `True`
- Candidate expectations:
  - `03/04` → **exactPreservation**
  - `12/31/2026` → **ambiguous**
  - `3 de abril` → **ambiguous**

### semantic-date-011 — date / es

- Input: `fecha registrada como 2026-10-01 en contrato`
- Source literal: `2026-10-01`
- Locale: `es-ES`
- Semantic value: `{"iso": "2026-10-01"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `2026-10-01` → **exactPreservation**
  - `12/31/2026` → **semanticCorruption**
  - `3 de abril` → **ambiguous**

### semantic-date-012 — date / es

- Input: `fecha registrada como 5 de mayo de 2026 en contrato`
- Source literal: `5 de mayo de 2026`
- Locale: `es-ES`
- Semantic value: `{"iso": "2026-05-05"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `5 de mayo de 2026` → **exactPreservation**
  - `12/31/2026` → **semanticCorruption**
  - `3 de abril` → **ambiguous**

### semantic-date-013 — date / mixed

- Input: `release date 31/12/2026 no roadmap`
- Source literal: `31/12/2026`
- Locale: `pt-BR`
- Semantic value: `{"iso": "2026-12-31"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `31/12/2026` → **exactPreservation**
  - `12/31/2026` → **semanticCorruption**
  - `3 de abril` → **ambiguous**

### semantic-date-014 — date / mixed

- Input: `release date 03/04 no roadmap`
- Source literal: `03/04`
- Locale: `pt-BR`
- Semantic value: `null`
- Ambiguous date: `True`
- Candidate expectations:
  - `03/04` → **exactPreservation**
  - `12/31/2026` → **ambiguous**
  - `3 de abril` → **ambiguous**

### semantic-date-015 — date / pt

- Input: `prazo registrado como 01/02/2027 no contrato`
- Source literal: `01/02/2027`
- Locale: `pt-BR`
- Semantic value: `{"iso": "2027-02-01"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `01/02/2027` → **exactPreservation**
  - `12/31/2026` → **semanticCorruption**
  - `3 de abril` → **ambiguous**

### semantic-date-016 — date / en

- Input: `contract deadline recorded as 01/02/2027`
- Source literal: `01/02/2027`
- Locale: `en-US`
- Semantic value: `{"iso": "2027-01-02"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `01/02/2027` → **exactPreservation**
  - `31/12/2026` → **semanticCorruption**
  - `April 3` → **ambiguous**

### semantic-number-001 — number / pt

- Input: `valor medido foi 1,5 no relatório`
- Source literal: `1,5`
- Locale: `pt-BR`
- Semantic value: `{"value": "1.5"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `1,5` → **exactPreservation**
  - `1500,0` → **semanticCorruption**
  - `1.5` → **ambiguous**

### semantic-number-002 — number / pt

- Input: `valor medido foi 1.000 no relatório`
- Source literal: `1.000`
- Locale: `pt-BR`
- Semantic value: `{"value": "1000"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `1.000` → **exactPreservation**
  - `1000` → **safeNormalization**
  - `1000000` → **semanticCorruption**
  - `1,000` → **ambiguous**

### semantic-number-003 — number / pt

- Input: `valor medido foi 1.000,50 no relatório`
- Source literal: `1.000,50`
- Locale: `pt-BR`
- Semantic value: `{"value": "1000.50"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `1.000,50` → **exactPreservation**
  - `1000,50` → **safeNormalization**
  - `1000500,00` → **semanticCorruption**
  - `1,000.50` → **semanticCorruption**

### semantic-number-004 — number / pt

- Input: `valor medido foi 2500 no relatório`
- Source literal: `2500`
- Locale: `pt-BR`
- Semantic value: `{"value": "2500"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `2500` → **exactPreservation**
  - `2500000` → **semanticCorruption**

### semantic-number-005 — number / en

- Input: `measured value was 1.5 in report`
- Source literal: `1.5`
- Locale: `en-US`
- Semantic value: `{"value": "1.5"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `1.5` → **exactPreservation**
  - `1500.0` → **semanticCorruption**
  - `1,5` → **ambiguous**

### semantic-number-006 — number / en

- Input: `measured value was 1,000 in report`
- Source literal: `1,000`
- Locale: `en-US`
- Semantic value: `{"value": "1000"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `1,000` → **exactPreservation**
  - `1000` → **safeNormalization**
  - `1000000` → **semanticCorruption**
  - `1.000` → **ambiguous**

### semantic-number-007 — number / en

- Input: `measured value was 1,000.50 in report`
- Source literal: `1,000.50`
- Locale: `en-US`
- Semantic value: `{"value": "1000.50"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `1,000.50` → **exactPreservation**
  - `1000.50` → **safeNormalization**
  - `1000500.00` → **semanticCorruption**
  - `1.000,50` → **semanticCorruption**

### semantic-number-008 — number / en

- Input: `measured value was 2500 in report`
- Source literal: `2500`
- Locale: `en-US`
- Semantic value: `{"value": "2500"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `2500` → **exactPreservation**
  - `2500000` → **semanticCorruption**

### semantic-number-009 — number / es

- Input: `el valor medido fue 1,5 en informe`
- Source literal: `1,5`
- Locale: `es-ES`
- Semantic value: `{"value": "1.5"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `1,5` → **exactPreservation**
  - `1500,0` → **semanticCorruption**
  - `1.5` → **ambiguous**

### semantic-number-010 — number / es

- Input: `el valor medido fue 1.000 en informe`
- Source literal: `1.000`
- Locale: `es-ES`
- Semantic value: `{"value": "1000"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `1.000` → **exactPreservation**
  - `1000` → **safeNormalization**
  - `1000000` → **semanticCorruption**
  - `1,000` → **ambiguous**

### semantic-number-011 — number / es

- Input: `el valor medido fue 1.000,50 en informe`
- Source literal: `1.000,50`
- Locale: `es-ES`
- Semantic value: `{"value": "1000.50"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `1.000,50` → **exactPreservation**
  - `1000,50` → **safeNormalization**
  - `1000500,00` → **semanticCorruption**
  - `1,000.50` → **semanticCorruption**

### semantic-number-012 — number / es

- Input: `el valor medido fue 2500 en informe`
- Source literal: `2500`
- Locale: `es-ES`
- Semantic value: `{"value": "2500"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `2500` → **exactPreservation**
  - `2500000` → **semanticCorruption**

### semantic-number-013 — number / mixed

- Input: `latency factor 1,5 no benchmark`
- Source literal: `1,5`
- Locale: `pt-BR`
- Semantic value: `{"value": "1.5"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `1,5` → **exactPreservation**
  - `1500,0` → **semanticCorruption**
  - `1.5` → **ambiguous**

### semantic-number-014 — number / mixed

- Input: `latency factor 1.000 no benchmark`
- Source literal: `1.000`
- Locale: `pt-BR`
- Semantic value: `{"value": "1000"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `1.000` → **exactPreservation**
  - `1000` → **safeNormalization**
  - `1000000` → **semanticCorruption**
  - `1,000` → **ambiguous**

### semantic-number-015 — number / pt

- Input: `valor medido foi 10.000.000 no relatório`
- Source literal: `10.000.000`
- Locale: `pt-BR`
- Semantic value: `{"value": "10000000"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `10.000.000` → **exactPreservation**
  - `10000000` → **safeNormalization**
  - `10000000000` → **semanticCorruption**
  - `10,000,000` → **ambiguous**

### semantic-number-016 — number / en

- Input: `measured value was 10,000,000 in report`
- Source literal: `10,000,000`
- Locale: `en-US`
- Semantic value: `{"value": "10000000"}`
- Ambiguous date: `False`
- Candidate expectations:
  - `10,000,000` → **exactPreservation**
  - `10000000` → **safeNormalization**
  - `10000000000` → **semanticCorruption**
  - `10.000.000` → **ambiguous**
