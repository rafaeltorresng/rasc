# PRD V1 — Scratchpad Inteligente para macOS

> Historical specification/milestone reference. For current behavior, launch direction and superseded decisions, start with [CURRENT-PRODUCT](CURRENT-PRODUCT.md) and the [documentation index](README.md).


**Status:** Draft para implementação
**Versão:** V1
**Plataforma:** macOS
**Data:** setembro de 2026
**Nome do produto:** em aberto
**Tese:** *Capture without thinking. Refine without prompting. Keep only what matters.*

---

# 1. Objetivo deste documento

Este PRD traduz a tese conceitual do produto em comportamento concreto.

O objetivo não é especificar toda evolução futura, mas responder com precisão:

* o que a V1 faz;
* o que a V1 não faz;
* quais estados existem;
* como o usuário navega;
* como uma nota nasce, muda e é recuperada;
* como `Refine` deve se comportar;
* quais decisões o produto toma pelo usuário;
* quais decisões continuam sob controle do usuário;
* quais requisitos de qualidade são essenciais;
* quais métricas definirão se a hipótese funciona;
* quais hipóteses devem permanecer abertas até termos uso real.

A V1 deve ser pequena o suficiente para ser compreendida quase integralmente por uma pessoa em poucos minutos.

## Decisão de IA da V1

Foundation Models é o único provider de Refine embarcado na V1. Todo Refine ocorre on-device: não há OpenRouter, BYOK, fallback cloud, backend ou provider externo. Se Foundation Models estiver indisponível, Refine fica indisponível; captura, histórico e busca continuam funcionando normalmente. `RefinementProvider` permanece apenas como fronteira interna limpa, não como infraestrutura para múltiplos providers.

---

# 2. Definição do produto

O produto é um scratchpad nativo para macOS destinado a pensamentos temporários.

A principal interação é:

```text
hotkey
  ↓
write
  ↓
optional Refine
  ↓
close
```

O usuário não precisa inicialmente criar uma “nota”, nomeá-la, salvá-la, categorizá-la ou decidir onde guardá-la.

O sistema salva automaticamente.

O produto deve se comportar mais como uma superfície temporária do sistema operacional do que como um aplicativo que o usuário precisa abrir e administrar.

---

# 3. Problema principal

Durante trabalho focado, usuários frequentemente precisam registrar pequenas informações sem querer interromper a atividade atual.

Ferramentas permanentes introduzem custo desnecessário.

Scratchpads tradicionais reduzem a fricção de captura, mas não necessariamente transformam o conteúdo capturado em algo melhor.

Ferramentas genéricas de IA permitem transformar texto, mas exigem que o usuário:

* escolha uma ferramenta;
* escolha uma transformação;
* formule um prompt;
* revise uma conversa;
* ou saia do contexto atual.

A V1 tenta combinar:

**captura praticamente instantânea**

com

**transformação contextual praticamente sem decisão.**

---

# 4. Job-to-be-done

> Quando surgir algo que preciso escrever durante outra atividade, quero capturá-lo imediatamente e, caso necessário, torná-lo mais claro ou utilizável sem organizar nada nem explicar para uma IA o que quero fazer.

---

# 5. Usuário inicial

O público inicial é composto por usuários de Mac que passam parte relevante do trabalho no teclado e lidam continuamente com informação transitória.

O produto não será comunicado exclusivamente para desenvolvedores, embora desenvolvedores sejam um grupo particularmente adequado para o beta.

Exemplos naturais incluem software engineers, designers, PMs, founders, writers, analysts, researchers e outros knowledge workers.

---

# 6. Não objetivos

A V1 não pretende ser:

**um second brain**
Não haverá backlinks, graph ou knowledge graph.

**um PKM**
Não haverá estrutura de conhecimento permanente sofisticada.

**um task manager**
Refine pode transformar texto em checklist, mas o produto não acompanhará deadlines, status ou projetos.

**um AI assistant geral**
Não haverá agentes, ações no computador ou connectors.

**um editor completo**
Não haverá rich text complexo, páginas ou blocos.

**um workspace**
Não haverá dashboards, equipes ou colaboração.

**um launcher**
Command Palette existirá apenas para poucas funções internas.

---

# 7. Core loop

A experiência fundamental da V1 é:

```text
             ┌───────────┐
             │  Thought  │
             └─────┬─────┘
                   │
                   ▼
             ┌───────────┐
             │  Capture  │
             └─────┬─────┘
                   │
           ┌───────┴───────┐
           │               │
           ▼               ▼
        Use raw          Refine
                           │
                           ▼
                       Use result
                           │
                    ┌──────┴──────┐
                    ▼             ▼
                  Close          Keep
```

A maior parte dos usos deve terminar em `Close`.

`Keep` deve ser exceção, não objetivo obrigatório.

---

# 8. Princípio fundamental de estado

Toda captura é persistida automaticamente.

Portanto:

**fechar não significa perder.**

Isso é importante para permitir que o usuário utilize `Esc` sem medo.

Ao mesmo tempo, fechar não deve fazer a nota parecer “arquivada” ou exigir gerenciamento posterior.

Ela simplesmente passa a fazer parte do histórico.

---

# 9. Entidades principais

A V1 precisa de apenas uma entidade importante:

## Note

Campos conceituais:

| Campo              | Tipo               | Observação                                |
| ------------------ | ------------------ | ----------------------------------------- |
| `id`               | UUID               | identificador                             |
| `content`          | text               | conteúdo atual                            |
| `original_content` | optional           | necessário durante transformação/recovery |
| `created_at`       | timestamp          | criação                                   |
| `updated_at`       | timestamp          | última edição                             |
| `last_opened_at`   | timestamp          | recuperação                               |
| `is_kept`          | boolean            | conteúdo explicitamente preservado        |
| `is_pinned`        | boolean            | provavelmente transitório                 |
| `refine_metadata`  | optional JSON      | informações técnicas mínimas              |
| `title`            | optional text      | automático, caso Keep demande             |
| `deleted_at`       | optional timestamp | soft delete se adotado                    |

Não existem na V1:

`folder_id`

`tags`

`project_id`

`workspace_id`

`owner/team`

`embedding`

`relationships`

---

# 10. Estados conceituais de uma nota

Uma nota pode estar em quatro estados de produto:

| Estado  | Significado                                |
| ------- | ------------------------------------------ |
| Scratch | captura normal                             |
| Active  | scratch atualmente visível                 |
| Kept    | usuário sinalizou que não deve desaparecer |
| Deleted | removida explicitamente                    |

`Active` não precisa existir na persistência como status. Pode ser apenas estado da aplicação.

---

# 11. Entrada principal: global hotkey

O global hotkey é a principal porta de entrada.

A V1 deve possuir um atalho default configurável.

O atalho precisa funcionar:

* com outro aplicativo ativo;
* em fullscreen;
* em diferentes Spaces;
* com múltiplos monitores;
* com o aplicativo sem foco;
* com a janela principal previamente fechada.

Ao pressioná-lo, o scratchpad deve aparecer imediatamente e o cursor deve estar pronto para digitar.

Não deve existir:

* splash;
* loading;
* homepage;
* selection screen;
* botão “New Note”.

---

# 12. Decisão crítica: qual nota abre?

Para a V1, a proposta inicial é:

> **o hotkey abre o scratch ativo mais recente, exceto quando ele já foi concluído implicitamente e uma nova captura for mais apropriada.**

Essa definição ainda é abstrata demais para implementação.

Portanto, para a primeira versão concreta, recomenda-se comportamento mais previsível:

### Regra V1

Se o scratchpad está fechado e o usuário pressiona o global hotkey:

**abre a última scratch ativa.**

Se o usuário explicitamente pedir `New`, cria outra.

Isso evita uma heurística prematura tentando adivinhar quando um pensamento terminou.

Depois podemos observar se usuários frequentemente precisam apagar conteúdo antigo antes de começar outro.

---

# 13. Nova nota

A criação explícita acontece através de:

`⌘N`

ou Command Palette → `New`.

Quando uma nova nota é criada:

* conteúdo vazio;
* cursor recebe foco imediatamente;
* nota antiga é autosaved;
* nenhuma confirmação;
* nenhum título;
* nenhuma metadata solicitada.

---

# 14. Fechar

`Esc` é a ação principal de saída.

Ao pressionar:

* conteúdo é salvo;
* janela desaparece;
* foco retorna ao aplicativo anterior;
* nenhuma confirmação aparece.

O objetivo é tornar a ação tão segura que o usuário possa executá-la mecanicamente.

---

# 15. Always on top

A nota pode permanecer visível enquanto o usuário trabalha em outro aplicativo.

Esta função deve ser simples.

Possível comando:

`Pin`

Pin significa:

> “quero continuar vendo esta superfície.”

Não significa:

> “esta informação é importante para sempre.”

Portanto `Pin` e `Keep` são semanticamente diferentes.

### Pin

estado visual.

### Keep

estado de lifecycle.

A V1 deve avaliar se essa distinção é compreensível. Caso gere confusão, `Pin` pode existir sem ser exposto como conceito textual forte.

---

# 16. Restrição de uma janela

A V1 terá:

> **uma única janela de scratchpad visível por vez.**

Não haverá mural de post-its.

Isso é deliberado.

O usuário pode possuir várias notas no histórico, mas uma única superfície pode ocupar a tela.

A decisão preserva:

* foco;
* baixo clutter;
* simplicidade de window management;
* coerência com a filosofia do produto.

---

# 17. Histórico

Notas anteriores podem ser encontradas através de uma superfície de busca.

Essa superfície não deve ser chamada necessariamente de `Library`.

O conceito recomendado é:

**History**

O History representa:

> “coisas que passaram por aqui.”

Não:

> “sua base de conhecimento.”

---

# 18. Search

A busca deve ser local e extremamente rápida.

Atalho conceitual:

`⌘P` ou outro a definir.

Interface:

```text
┌──────────────────────────────────────────┐
│ > queue                                  │
├──────────────────────────────────────────┤
│ caramuru queue retry               18m   │
│ notification status                 Tue  │
│ async queue notes                   Sep  │
└──────────────────────────────────────────┘
```

O usuário digita.

Resultados aparecem.

`↑ ↓`

navegam.

`Enter`

abre.

`Esc`

fecha.

---

# 19. Search V1 não usa IA

Search será inicialmente lexical/fuzzy.

Não existem embeddings.

Não existe semantic search.

Não existe RAG.

Não existe “ask your notes”.

Motivo:

a quantidade inicial de informação tende a ser pequena e fuzzy search é:

* extremamente rápido;
* previsível;
* offline;
* simples;
* barato;
* fácil de testar.

Semantic search somente deveria ser considerado se dados reais demonstrarem dificuldade relevante de recuperação.

---

# 20. Ordenação do histórico

Sem query, a ordenação padrão deve priorizar recência.

Uma proposta:

`updated_at DESC`

Kept notes podem receber um indicador discreto, mas não necessariamente ficar sempre no topo.

Não construir múltiplas ordenações inicialmente.

---

# 21. Keep

`Keep` é a ação que transforma uma captura transitória em algo que o usuário explicitamente considera digno de preservação.

A experiência deve ser extremamente simples.

Exemplo:

`⌘⇧K`

ou Command Palette → `Keep`.

Não abre diálogo.

Não pergunta:

* folder;
* título;
* tag;
* projeto.

A nota apenas muda de estado.

---

# 22. Auto-title

Se o produto precisar mostrar um título no History, esse título não deve ser solicitado ao usuário.

Prioridade inicial:

1. primeira linha significativa;
2. fallback para trecho inicial;
3. futuramente título inferido automaticamente.

Não utilizar LLM automaticamente apenas para gerar títulos na V1 se isso introduzir latência ou processamento desnecessário.

Título é representação, não conteúdo.

---

# 23. Refine

`Refine` é a principal diferenciação da V1.

Deve ser possível executá-lo através de um único atalho.

Exemplo conceitual:

`⌘J`

Ao ser acionado:

1. captura o conteúdo atual;
2. determina qual comportamento é adequado;
3. produz uma versão refinada;
4. apresenta resultado sem destruir o original;
5. usuário aceita ou rejeita.

Não existe prompt inicial.

Não existe seleção de modelo.

Não existe escolha entre ações.

---

# 24. Contrato de Refine

A operação deve obedecer ao seguinte contrato:

### Entrada

Conteúdo atual da nota.

Possivelmente metadados mínimos como locale.

### Saída

Conteúdo refinado + metadata interna.

### Restrições

O resultado deve:

* preservar fatos;
* preservar nomes;
* preservar relações;
* preservar incerteza;
* preservar termos técnicos;
* não inventar deadlines;
* não inventar responsáveis;
* não transformar hipótese em fato;
* não transformar possibilidade em decisão;
* evitar verbosidade desnecessária;
* respeitar idioma original;
* não mudar tom excessivamente sem motivo.

---

# 25. Refine não é Expand

Um dos maiores riscos é o modelo entender “refinar” como “escrever mais”.

Isso deve ser combatido.

Por default:

> **Refine deveria preferir compressão ou reorganização à expansão.**

Se:

```text
bug talvez seja retry correndo antes do queue tick
ver logs
```

o resultado não precisa explicar arquitetura de filas.

Pode ser:

```text
Possível race condition entre retry e queue tick.

- Verificar os logs.
```

Isso é suficiente.

---

# 26. Refine Router

A implementação conceitual pode ter duas etapas:

```text
note
  ↓
intent / structure inference
  ↓
transformation
```

Isso não significa necessariamente duas chamadas ao modelo.

Pode ser uma única geração estruturada que retorna:

```json
{
  "type": "tasks",
  "confidence": 0.91,
  "transformed": "..."
}
```

A V1 deve favorecer simplicidade e latência.

Se uma única chamada entregar comportamento confiável, não há motivo para criar pipeline complexo.

---

# 27. Categorias iniciais de Refine

O sistema deve possuir poucas categorias internas.

| Tipo           | Comportamento                 |
| -------------- | ----------------------------- |
| `messy_text`   | clareza + estrutura mínima    |
| `tasks`        | checklist                     |
| `meeting`      | pontos principais + ações     |
| `idea`         | estrutura lógica              |
| `message`      | limpeza mantendo voz          |
| `technical`    | preservar precisão, organizar |
| `already_good` | mudança mínima                |
| `unknown`      | conservative cleanup          |

A classificação não deve necessariamente aparecer para o usuário.

---

# 28. Confidence

O sistema deve calcular ou inferir uma noção de confiança.

Não precisa ser um score matematicamente calibrado na primeira implementação.

O objetivo é permitir uma política:

```text
confidence high
→ transformação apropriada

confidence medium
→ transformação conservadora

confidence low
→ minimal cleanup
```

Nunca:

```text
confidence low
→ hallucinate harder
```

---

# 29. Seleção parcial

Uma decisão de V1 importante:

Se houver texto selecionado ao acionar Refine, o sistema deve refinar:

> **apenas a seleção.**

Se não houver seleção:

> a nota inteira.

Isso aumenta utilidade sem adicionar UI.

É consistente com padrões de editores.

---

# 30. Refine Preview

Após geração, o usuário precisa entender que está vendo uma proposta.

Possível estado:

```text
┌────────────────────────────────────────┐
│ refined                                │
│                                        │
│ Possível race condition entre retry e │
│ queue tick.                            │
│                                        │
│ - Verificar logs.                      │
│                                        │
│ Esc cancel                  ↵ accept   │
└────────────────────────────────────────┘
```

Nenhuma animação extravagante de IA.

Nenhum gradiente.

Nenhum “✨ magic”.

O conteúdo é o foco.

---

# 31. Accept

`Enter`

aceita.

Após aceitar:

* conteúdo refinado substitui a região correspondente;
* versão anterior permanece disponível para Undo;
* cursor retorna ao editor;
* nenhum modal secundário.

---

# 32. Cancel

`Esc`

durante preview:

* descarta resultado;
* mantém conteúdo original;
* retorna ao editor.

Importante:

`Esc` durante Refine não fecha imediatamente a aplicação.

Ele primeiro sai do estado de preview.

---

# 33. Undo

`⌘Z` deve restaurar o texto anterior normalmente.

Refine precisa participar do mesmo modelo mental de edição do restante do aplicativo.

Não criar “AI history” separado na V1.

---

# 34. Retry

Retry pode ser útil, mas não deveria dominar a interface.

Uma proposta:

`⌘R` no estado de preview

ou opção discreta na command palette/context menu.

Não adicionar botão grande “Regenerate”.

Se usuários utilizarem muito Retry, isso é potencialmente sinal de baixa qualidade do core.

---

# 35. Custom prompt

Não estará visível na interface principal.

Uma eventual operação:

`Refine with instruction…`

pode existir no futuro ou escondida na Command Palette para power users.

Não entra no core da V1.

O objetivo é justamente não obrigar prompt engineering.

---

# 36. Auto-Refine

A V1 **não altera texto automaticamente**.

Também não dispara LLM silenciosamente a cada pausa.

Motivos:

* privacidade;
* custo;
* consumo;
* imprevisibilidade;
* distração;
* risco de destruir sensação de ferramenta simples.

Refine é explicitamente acionado.

---

# 37. Sugestão discreta de Refine

Também não é necessária inicialmente.

Exemplo de feature futura:

```text
4 actions detected · ⌘J
```

É interessante, mas exige análise automática de conteúdo e adiciona comportamento ativo.

Primeiro devemos provar que Refine manual possui valor.

---

# 38. Provider de IA

A camada de IA deve ser abstraída.

Conceitualmente:

```swift
protocol RefinementProvider {
    func refine(note: String) async throws -> RefinementResult
}
```

Na V1, a única implementação embarcada é `FoundationModelsRefinementProvider`. O domínio não depende diretamente dela, pois `RefinementProvider` já é uma fronteira limpa para a implementação e os testes; não devemos construir infraestrutura adicional de providers na V1.

---

# 39. Apple Foundation Models

Em Macs compatíveis e com recurso disponível, o modelo do sistema deve ser o caminho preferencial.

Razões:

* local;
* baixa latência potencial;
* sem billing próprio;
* sem account;
* offline;
* privacidade;
* alinhamento nativo com macOS.

A disponibilidade deve ser verificada dinamicamente.

---

# 40. Providers externos — fora de escopo da V1

OpenRouter, BYOK, API keys, seleção de modelo e qualquer fallback cloud não fazem parte da V1. Não mostrar, configurar ou sugerir esses caminhos quando Foundation Models estiver indisponível.

---

# 41. Falha de IA

Refine não pode prejudicar a experiência principal quando falhar.

Situações:

* Foundation Model indisponível;
* Apple Intelligence desligada;
* resposta inválida;
* safety refusal.

Comportamento:

mostrar erro discreto e retornar imediatamente ao editor.

Exemplo:

```text
Refine unavailable
```

Nada mais.

---

# 42. Latência de Refine

A geração deve parecer rápida.

Não definimos SLA externo ainda, mas internamente devemos medir:

`time_to_first_result`

e

`total_refine_latency`.

A experiência de espera deve evitar spinner grande.

Um pequeno estado textual basta:

```text
refining…
```

A aplicação inteira continua responsiva.

---

# 43. Cancelamento de geração

Ao pressionar `Esc` durante uma geração:

* cancelar request quando tecnicamente possível;
* remover estado de loading;
* voltar ao conteúdo.

Nunca bloquear a aplicação esperando o modelo terminar.

---

# 44. Persistência

A persistência deve ser local.

Duas opções naturais:

**SwiftData**

ou

**SQLite/GRDB**.

Para V1, ambas são adequadas.

O critério principal é:

* migrations confiáveis;
* busca simples;
* performance;
* facilidade de backup;
* baixo risco operacional.

Não há benefício em construir camada de banco excessivamente sofisticada.

---

# 45. Autosave

Autosave deve acontecer continuamente ou com debounce curto.

Requisito fundamental:

> fechar a janela imediatamente após digitar não pode perder informação.

Também deve sobreviver a:

* crash;
* quit;
* reboot;
* atualização do aplicativo.

---

# 46. Crash recovery

Se o aplicativo terminar inesperadamente durante edição, o conteúdo recente deve reaparecer na próxima abertura.

Essa confiabilidade vale mais para o produto que várias features adicionais.

---

# 47. Delete

Delete precisa existir.

A nota não desaparece apenas porque foi fechada.

Possível comando:

`⌘⌫`

A V1 pode implementar soft delete local para permitir recuperação breve sem expor ainda uma interface complexa de Trash.

Caso isso aumente escopo desnecessariamente, delete permanente com confirmação mínima pode ser utilizado.

A decisão deve priorizar proteção contra perda acidental.

---

# 48. Markdown

A V1 deve suportar Markdown apenas na medida em que ajuda conteúdo textual.

Não é necessário WYSIWYG sofisticado.

Suporte mínimo útil:

* headings;
* bullets;
* numbered lists;
* checkboxes;
* inline code;
* fenced code;
* bold;
* italic.

A principal preocupação é não permitir que formatting se torne uma nova área de produto.

---

# 49. Technical content

Como parte relevante do público inicial pode trabalhar com software, o editor precisa tratar bem:

* code blocks;
* JSON;
* SQL;
* stack traces;
* URLs;
* identifiers;
* camelCase;
* snake_case.

Refine deve receber instruções fortes para preservar conteúdo técnico literal quando não houver razão para modificar.

---

# 50. Clipboard

Copy/paste precisa ser impecável.

Isso inclui:

* texto plain;
* Unicode;
* Markdown;
* multiline;
* código.

A V1 não precisa de clipboard history.

Esse seria outro produto.

---

# 51. Menu bar

Um ícone na menu bar pode oferecer:

```text
New
Open Scratchpad
Find
Preferences
Quit
```

O menu bar não deve ser necessário para uso diário.

Ele funciona como fallback descobrível.

Idealmente o usuário utiliza global hotkey quase sempre.

---

# 52. Dock

A aplicação pode operar como menu bar utility sem ícone permanente no Dock.

Essa decisão deve ser validada através de UX.

A filosofia favorece:

> utility silenciosa.

Mas durante beta pode ser útil permitir configuração para mostrar no Dock.

---

# 53. Preferences

Preferences devem ser pequenas.

V1:

| Setting               | Necessidade              |
| --------------------- | ------------------------ |
| Global hotkey         | obrigatória              |
| Launch at login       | importante               |
| Always on top default | opcional                 |
| Appearance            | talvez System/Light/Dark |
| Menu bar visibility   | talvez                   |

Evitar uma tela cheia de personalização.

---

# 54. Temas

Não existirão múltiplos themes na V1.

Suporte:

**System**

e, se necessário:

**Light / Dark**.

A aparência deve acompanhar macOS.

---

# 55. Tipografia

A direção visual pode utilizar tipografia monoespaçada no conteúdo.

Entretanto, legibilidade tem prioridade sobre estética.

A UI sistêmica deve continuar parecendo uma aplicação Mac.

Nenhuma dependência de fonte proprietária é necessária para a primeira versão.

---

# 56. Dimensões da janela

A janela deve ser compacta, mas capaz de crescer até certo limite.

Ela não deve ocupar naturalmente uma tela inteira.

Características:

* largura confortável para textos curtos;
* altura variável;
* resize manual possível;
* posição persistida;
* limite mínimo;
* limite máximo razoável.

Não otimizar V1 para long-form writing.

---

# 57. Window placement

Primeira implementação recomendada:

> lembrar a última posição utilizada.

Quando não houver posição:

> centro do display ativo.

Display ativo pode ser determinado pelo monitor onde está o cursor ou pela janela atualmente ativa.

Não desenvolver heurística complicada inicialmente.

---

# 58. Spaces

Comportamento em Spaces é uma parte crítica da experiência.

Ao pressionar global hotkey, o scratchpad deve aparecer no contexto atual.

O usuário não deveria ser transportado involuntariamente para outro Space.

Isso precisa ser validado explicitamente nos testes.

---

# 59. Fullscreen

O comportamento também precisa funcionar sobre apps fullscreen.

Uma utility que falha nesse contexto perde valor justamente durante trabalho focado.

---

# 60. Multiple monitors

O produto deve aparecer no display associado ao contexto atual.

No mínimo, precisa evitar o comportamento frustrante de abrir sempre no monitor errado.

---

# 61. Focus

Quando aparece:

> editor recebe foco.

Quando desaparece:

> aplicação anterior recupera foco naturalmente.

Esse comportamento precisa parecer instantâneo.

---

# 62. Launch at login

Será suportado.

O usuário deve poder habilitar/desabilitar nas Preferences.

O produto só consegue ser verdadeiramente instantâneo se estiver disponível no background.

---

# 63. Performance

Objetivos qualitativos:

* baixo consumo de memória;
* quase nenhum CPU em idle;
* janela praticamente instantânea;
* search imediato;
* nenhum processamento de IA em background desnecessário.

A aplicação deve ser compatível com a expectativa de uma pequena Mac utility.

---

# 64. Offline

Sem depender de Refine, todo core deve funcionar offline:

* capture;
* editing;
* history;
* search;
* Keep;
* Pin;
* delete.

Com Foundation Models disponível, Refine também pode funcionar offline.

---

# 65. Telemetria

A V1 deve ser extremamente cuidadosa aqui.

Como local-first e privacy são princípios do produto, analytics invasivos seriam incoerentes.

Para beta, a opção recomendada é:

> telemetria mínima e explicitamente descrita, sem conteúdo das notas.

Eventos possíveis:

```text
app_opened
note_created
note_closed
refine_requested
refine_completed
refine_accepted
refine_rejected
note_kept
search_opened
search_result_opened
```

Nunca enviar:

* conteúdo;
* título;
* query digitada;
* clipboard;
* prompt;
* texto refinado.

---

# 66. Evals locais de Refine

A avaliação qualitativa do modelo precisa existir separadamente da telemetria de usuários.

Manter dataset interno versionado.

Categorias devem representar uso real.

Exemplo:

```text
ID: DEV-001

Raw:
"queue pode estar chamando retry antes do update status
ver log notification
acho q queued ainda failed"

Expected:
- preserve uncertainty
- preserve queue/retry/status terminology
- structure as investigation
- no invented owner
- no invented deadline
```

Cada alteração relevante no Refinement Engine deve ser executada contra esse dataset.

---

# 67. Critérios de avaliação do Refine

Cada output pode receber scores como:

| Critério               | Questão                          |
| ---------------------- | -------------------------------- |
| Faithfulness           | preservou o conteúdo?            |
| Hallucination          | inventou algo?                   |
| Structure fit          | escolheu formato adequado?       |
| Intervention           | mexeu na medida certa?           |
| Conciseness            | ficou mais útil sem verbosidade? |
| Language               | preservou idioma/voz?            |
| Technical preservation | manteve termos técnicos?         |

A nota geral não deve mascarar falhas graves.

Uma hallucination importante deve ser tratada como falha mesmo se o texto estiver “bonito”.

---

# 68. Teste A/B conceitual

Durante validação, uma comparação útil seria:

**Grupo A**

produto completo com Refine.

**Grupo B**

scratchpad equivalente sem Refine.

A pergunta não é apenas se Refine recebe cliques.

Queremos saber se Refine muda:

* retenção;
* frequência;
* percepção de valor;
* disposição para pagar.

---

# 69. Comparação com substitutos

Também precisamos entrevistar usuários que usam:

* Apple Notes;
* Quick Note;
* Raycast;
* Antinote;
* Heynote;
* text editor simples.

A principal pergunta:

> “Por que você abriu nosso produto neste momento em vez do que já tinha?”

A resposta revela o verdadeiro diferencial.

---

# 70. Métricas do beta

As principais métricas são:

### Activation

Usuário configura hotkey e cria primeiras capturas.

### Habit

Número de dias ativos por semana.

### Capture frequency

Número médio de capturas em um dia ativo.

### Refine usage

Percentual de notas em que Refine é acionado.

### Refine acceptance

Percentual de resultados aceitos.

### Immediate edit ratio

Quanto texto é modificado imediatamente depois de aceitar.

### Retrieval

Percentual de usuários que retornam ao History.

### Keep

Percentual de notas explicitamente mantidas.

### Retention

D1, D7, D14 e D30 para beta conforme volume permitir.

---

# 71. Sinais positivos qualitativos

Comentários que indicariam product-market pull inicial:

> “Comecei a usar o shortcut sem pensar.”

> “Estou usando no lugar de criar notas descartáveis no Apple Notes.”

> “É onde escrevo coisa que ainda não sei onde colocar.”

> “Sinto falta de Refine quando estou escrevendo em outro lugar.”

> “Não precisei aprender como usar.”

---

# 72. Sinais negativos

Alertas importantes:

> “É igual ao Quick Note.”

> “Eu poderia fazer isso no Raycast.”

> “Quase nunca uso Refine.”

> “Refine muda demais o que escrevi.”

> “Nunca sei qual nota vai aparecer.”

> “Tenho medo de perder minhas notas.”

> “Preciso de folders para achar tudo.”

> “Quero usar como meu sistema de notas principal.”

Alguns desses comentários podem indicar problemas de UX. Outros podem indicar público errado.

---

# 73. Feature requests não são automaticamente roadmap

Durante beta haverá pedidos por:

* sync;
* iPhone;
* voice;
* tags;
* folders;
* reminders;
* integrations;
* todos os modelos de IA;
* custom prompts;
* várias janelas;
* browser extension.

Eles devem ser registrados.

Não necessariamente implementados.

A pergunta não é:

> quantas pessoas pediram?

Também precisamos entender:

> qual problema elas estavam tentando resolver?

Muitas vezes existe uma solução menor dentro do core.

---

# 74. Regra de expansão

Uma nova feature só deveria entrar se:

1. estiver diretamente ligada a Capture, Refine ou Keep;
2. resolver um problema recorrente observado;
3. a alternativa atual causar fricção material;
4. não introduzir uma nova categoria de gerenciamento;
5. benefício superar custo cognitivo permanente.

---

# 75. Monetização V1

Estratégia preferencial:

```text
Download
   ↓
Free trial
   ↓
One-time purchase
```

Hipótese inicial de teste:

**US$14.99–19.99**

Não é preço final.

O beta deve testar willingness to pay.

---

# 76. Sem subscription inicialmente

Subscription só faria sentido se o produto futuramente assumir custo recorrente relevante ou entregar serviço contínuo que justifique a relação.

Adicionar assinatura simplesmente porque existe IA não é coerente com a tese.

---

# 77. Sem conta

A V1 não terá account.

Licenciamento pode utilizar um mecanismo externo simples de purchase/license se necessário.

Mas utilizar o scratchpad não deve exigir:

* username;
* profile;
* onboarding account;
* cloud identity.

---

# 78. Onboarding

O onboarding precisa caber em poucos segundos.

Possível experiência:

```text
A scratchpad, one shortcut away.

[Record shortcut]

Capture anything.
Press ⌘J to Refine.
Esc to get back to work.

[Start]
```

Não criar tutorial de dez telas.

O próprio produto deve ensinar pelo uso.

---

# 79. First-run

Ao finalizar onboarding:

o scratchpad abre vazio.

O usuário pode imediatamente escrever.

Seria interessante sugerir um primeiro exemplo real, mas não preencher a nota automaticamente com marketing que o usuário precisa apagar.

---

# 80. Discoverability de Refine

Refine precisa ser descoberto sem ocupar muita UI.

Uma indicação discreta no rodapé pode mostrar:

```text
⌘J refine
```

Após o usuário demonstrar uso recorrente, essa indicação pode desaparecer ou permanecer extremamente sutil.

---

# 81. Accessibility

Mesmo sendo power-user-oriented, o produto deve respeitar:

* VoiceOver;
* keyboard navigation;
* contrast;
* Dynamic Type onde aplicável;
* reduced motion;
* system appearance.

Minimalismo não deve significar inacessibilidade.

---

# 82. Localization

A arquitetura deve aceitar vários idiomas.

Refine deve responder no idioma predominante do input.

Não forçar inglês.

UI pode ser lançada inicialmente em inglês se for estratégia de distribuição global, mas isso é uma decisão de go-to-market, não limitação técnica.

---

# 83. Segurança

Não há API key ou transmissão externa de conteúdo na V1.

Logs nunca devem incluir conteúdo das notas.

Crash reporting deve sanitizar campos dinâmicos.

---

# 84. Dados sensíveis

O produto não tentará automaticamente detectar ou bloquear informação sensível.

Na V1, Refine processa o conteúdo somente no dispositivo. Não há configuração de transmissão externa a explicar em Preferences.

---

# 85. Logging técnico

Logs locais precisam ser úteis sem armazenar conteúdo.

Exemplos:

```text
note_created id=...
autosave_completed latency_ms=...
refine_started provider=foundation_models
refine_completed latency_ms=...
refine_cancelled
search_completed results=4 latency_ms=...
```

Não:

```text
content="reunião confidencial..."
```

---

# 86. Eventos de domínio

Para manter arquitetura simples, eventos conceituais possíveis:

```text
NoteCreated
NoteUpdated
NoteKept
NoteDeleted
RefinementRequested
RefinementGenerated
RefinementAccepted
RefinementRejected
```

Não é necessário implementar event sourcing.

A lista serve apenas para definir claramente comportamento e observabilidade.

---

# 87. Arquitetura de alto nível

```text
┌───────────────────────────────┐
│          macOS UI             │
│ SwiftUI + AppKit              │
└──────────────┬────────────────┘
               │
               ▼
┌───────────────────────────────┐
│      Application Layer        │
│ Notes / Search / Refine       │
└──────────────┬────────────────┘
               │
       ┌───────┴────────┐
       ▼                ▼
┌──────────────┐  ┌────────────────┐
│ Local Store  │  │ Refinement     │
│ SQLite/etc.  │  │ Engine         │
└──────────────┘  └────────┬───────┘
                           │
                   │
                   ▼
             Foundation Models
                on-device
```

Nenhum backend é necessário no core.

---

# 88. Prioridade de engenharia

A ordem recomendada de implementação não começa pela IA.

Primeiro precisa existir um scratchpad excelente.

### Milestone A — Capture

Global hotkey, window behavior, editor, autosave, close/focus.

### Milestone B — Retrieval

Multiple notes internamente, History, fuzzy search.

### Milestone C — Refine

Provider abstraction, local model, preview, accept/revert, evals.

### Milestone D — Polish

Menu bar, preferences, launch at login, edge cases, performance.

### Milestone E — Beta instrumentation

Analytics opt-in/minimal, feedback mechanism, distribution.

---

# 89. Definition of Done — Capture

Capture só está pronto se:

* hotkey funciona consistentemente;
* janela aparece rapidamente;
* foco vai para o editor;
* digitação imediata funciona;
* fechar não perde conteúdo;
* aplicativo anterior recupera foco;
* Spaces funcionam;
* fullscreen funciona;
* multiple monitors funcionam.

Um bug significativo aqui deve bloquear lançamento.

---

# 90. Definition of Done — Search

Search está pronto quando:

* abre instantaneamente;
* resultados atualizam conforme digita;
* keyboard navigation funciona;
* abrir resultado é imediato;
* notas recentes são fáceis de recuperar;
* não requer mouse.

---

# 91. Definition of Done — Refine

Refine está pronto quando:

* funciona com nota completa;
* funciona com seleção;
* original nunca é perdido;
* cancelamento funciona;
* Undo funciona;
* falha de provider não trava aplicação;
* outputs passam pelo conjunto mínimo de evals;
* latência é medida;
* resultado não inventa sistematicamente detalhes;
* comportamento de baixa confiança é conservador.

---

# 92. Critérios para beta privado

A aplicação pode entrar em beta privado quando o core funciona de maneira confiável e nós mesmos começamos a utilizá-lo espontaneamente.

Não é necessário possuir:

* site perfeito;
* pagamento;
* branding final;
* todas as settings;
* App Store listing.

É necessário possuir:

* build assinável;
* updater ou estratégia simples de distribuição;
* mecanismo de feedback;
* proteção contra perda de dados.

---

# 93. Perfil ideal de beta testers

Preferir usuários que:

* utilizem Mac diariamente;
* trabalhem predominantemente no computador;
* já possuam hábito de quick notes/scratchpads;
* sejam capazes de comparar com substitutos;
* tenham workflows diferentes entre si.

Não recrutar apenas software engineers.

Isso poderia enviesar o produto demasiadamente cedo.

---

# 94. Tamanho inicial de beta

Não precisamos de centenas de usuários.

Algo entre aproximadamente 15–30 usuários realmente ativos pode produzir muito mais aprendizado inicial do que um lançamento aberto com pouca observação.

O objetivo da primeira fase é comportamento, não crescimento.

---

# 95. Perguntas para entrevistas após uso

As entrevistas devem partir do comportamento observado, não de opiniões abstratas.

Perguntas importantes incluem:

> Conte sobre a última vez que você abriu o app.

> O que você estava fazendo antes?

> Por que não usou sua ferramenta habitual?

> O que aconteceu com aquela nota depois?

> Quando você usou Refine pela última vez?

> O resultado ficou melhor ou apenas diferente?

> Houve algum momento em que você quis abrir o app e não abriu?

> Há algo no produto que você evita porque não confia?

> Se o produto desaparecesse amanhã, para onde você voltaria?

A última pergunta é particularmente útil para identificar o concorrente real.

---

# 96. Principal hipótese da V1

> **Usuários possuem uma necessidade recorrente de capturar informação transitória e valorizam suficientemente uma transformação contextual de baixa fricção para adotar uma utility dedicada.**

---

# 97. Hipóteses secundárias

> Uma janela única é suficiente.

> History simples é suficiente para recuperação.

> Folders e tags não são necessários.

> Refine genérico com bom routing é mais útil do que vários comandos explícitos.

> Modelo local é suficientemente competente para boa parte dos casos.

> Usuários preferem one-time purchase a subscription.

> Mac-only é um bom wedge inicial.

Todas precisam ser tratadas como hipóteses, não verdades.

---

# 98. Critério de sucesso inicial

O produto não precisa provar grande escala.

Precisa provar comportamento.

Um resultado inicial muito forte seria:

* usuários ativos em vários dias da semana;
* captura frequente;
* Refine utilizado de maneira recorrente;
* boa taxa de aceitação;
* baixa correção pós-Refine;
* relatos espontâneos de hábito;
* disposição real para pagar.

---

# 99. Kill criteria

Também é importante definir quando a tese deve ser reconsiderada.

Precisamos questionar o core se, após uso suficiente:

**Refine quase nunca é utilizado.**

Isso sugere que estamos apenas construindo scratchpad.

**Refine é utilizado mas frequentemente rejeitado.**

Problema na inteligência ou na interação.

**Usuários voltam ao Apple Notes/Raycast por falta de valor claro.**

Diferenciação insuficiente.

**A maior demanda é por organização permanente.**

Talvez o público/problema seja diferente do pressuposto.

**A principal demanda é por agents/actions.**

Talvez o mercado esteja puxando em uma direção que decidimos deliberadamente não seguir.

Nesse caso, devemos decidir conscientemente entre pivotar ou continuar nichados, não simplesmente acumular features.

---

# 100. V1 resumida em uma tela

O produto essencial é:

```text
                 GLOBAL HOTKEY
                       │
                       ▼
           ┌────────────────────┐
           │                    │
           │   unfinished       │
           │   thought          │
           │                    │
           │          ⌘J refine │
           └────────────────────┘
              │        │
             Esc      ⌘J
              │        │
              ▼        ▼
          back to    refined
           work       preview
                       │
                    Enter/Esc

History:
shortcut → search → Enter
```

Todo o restante existe para tornar esse fluxo:

**rápido, previsível, seguro e agradável.**

---

# 101. Regra final para implementação

Antes de adicionar qualquer coisa ao backlog, perguntar:

> **O usuário precisa realmente saber que isso existe?**

Se podemos decidir de maneira segura por ele, decidir.

Se podemos remover uma etapa, remover.

Se podemos esconder implementação, esconder.

Se outro produto resolve melhor a etapa seguinte, deixar o usuário utilizar esse produto.

A V1 não vence por amplitude.

Ela vence se transformar:

```text
“eu preciso anotar isso rapidinho”
```

em

```text
hotkey → type → done
```

e, quando necessário:

```text
hotkey → type → Refine → done
```

sem que o usuário precise interromper o raciocínio para operar a ferramenta.

---

# 102. Product mantra

> **Capture without thinking.**
> **Refine without prompting.**
> **Keep only what matters.**

A V1 deve ser julgada contra essa frase.

Se a implementação começar a exigir que o usuário pense mais, escolha mais, configure mais ou administre mais, estamos nos afastando do produto que decidimos construir.
