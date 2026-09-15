# Documento-base de Produto

## Scratchpad inteligente para pensamentos ainda não terminados

**Status:** tese de produto / documento de contexto
**Data de referência:** setembro de 2026
**Plataforma inicial:** macOS
**Tese resumida:** *Capture without thinking. Refine without prompting. Keep only what matters.*

---

## 1. Resumo executivo

O produto nasce de uma observação simples: nem toda informação que uma pessoa precisa escrever merece imediatamente virar uma “nota”.

Durante o trabalho surgem pensamentos incompletos, pequenas listas, hipóteses, trechos de texto, mensagens ainda não enviadas, lembretes de curto prazo, decisões provisórias, números, links, pedaços de código e ideias que ainda não têm estrutura suficiente para entrar em um sistema permanente.

As ferramentas tradicionais de notas resolvem bem o armazenamento de informação que já sabemos que queremos guardar. Elas resolvem pior o momento anterior: **o intervalo entre pensar algo e decidir o que aquilo realmente é**.

Abrir Notion, Obsidian, Apple Notes ou outro sistema permanente pode exigir pequenas decisões: qual nota abrir, onde colocar, qual título usar, se aquilo merece uma página, se deve receber tag ou se precisa ser organizado. Separadamente, scratchpads como Antinote, Heynote ou pequenas utilities do Mac reduzem bastante essa fricção, mas normalmente param na captura: aquilo que entrou desestruturado permanece desestruturado.

A oportunidade investigada neste projeto fica exatamente entre esses dois mundos.

O produto não pretende ser um novo sistema de conhecimento, editor completo ou assistente pessoal. Ele é uma **camada temporária de pensamento no macOS**.

O fluxo fundamental é:

**pensar → capturar → refinar → usar → descartar ou manter**

O usuário deve conseguir abrir o produto a partir de qualquer lugar com um atalho global, escrever imediatamente e retornar à atividade anterior sem organizar nada. Quando o pensamento cru precisar se tornar mais útil, uma única ação — conceitualmente chamada de **Refine** — interpreta o conteúdo e escolhe uma transformação adequada, preservando intenção e informação.

A aposta central não é disponibilizar IA dentro de uma nota. Isso já está amplamente commoditizado. A aposta é **retirar do usuário a necessidade de decidir como utilizar a IA**.

Em vez de:

> Rewrite
> Summarize
> Improve
> Expand
> Create tasks
> Change tone
> Structure
> Fix grammar

o produto oferece:

> **Refine**

A inteligência está na decisão que acontece por trás dessa ação.

Se o conteúdo se parece com tarefas, o resultado pode ser uma checklist. Se parece com um despejo de uma reunião, pode separar decisões e ações. Se é uma ideia desorganizada, pode estruturar melhor o raciocínio. Se já está quase bom, deve fazer pouco. Se modificar o texto provavelmente o prejudicaria, deve preservar.

A ambição não é criar a ferramenta com mais capacidades. É construir uma ferramenta excepcionalmente eficiente dentro de uma responsabilidade pequena.

---

## Decisão de IA da V1

Foundation Models é o único provider de Refine embarcado na V1. Refine é inteiramente on-device: não há OpenRouter, BYOK, cloud fallback, backend ou provider externo. Quando Foundation Models não estiver disponível, somente Refine fica indisponível; captura, histórico e busca continuam funcionando normalmente. `RefinementProvider` permanece como uma fronteira interna já útil para a implementação e testes, sem infraestrutura adicional de providers.

---

# 2. O problema

## 2.1 Nem todo pensamento deveria nascer permanente

A maior parte dos aplicativos de notas assume implicitamente um comportamento:

**escreva algo que você pretende guardar.**

Esse modelo é adequado para documentação, estudo, conhecimento permanente, atas, referências, projetos e escrita longa.

No cotidiano, porém, existe outra categoria de informação:

* um telefone necessário pelos próximos minutos;
* uma mensagem sendo preparada antes de enviar;
* uma hipótese de bug;
* passos de uma investigação;
* três itens que precisam ser feitos durante a próxima hora;
* ideias durante uma reunião;
* um trecho copiado de outro aplicativo;
* um JSON que precisa ser observado;
* um pensamento que talvez seja útil e talvez não;
* uma ideia ainda incapaz de justificar sua própria nota.

Produtos especializados já demonstram que essa distinção é relevante.

O Antinote se posiciona explicitamente como um scratchpad para notas que provavelmente serão descartadas e deliberadamente evita competir com sistemas permanentes. Armazena localmente em SQLite, oferece acesso por hotkey global e permite posteriormente exportar aquilo que realmente merece ser mantido.

O Heynote se define como um scratchpad persistente para power users, citando exatamente usos como preparar uma mensagem do Slack, inspecionar JSON, manter notas de reunião e listas temporárias. Atualmente possui milhares de estrelas no GitHub, mostrando que existe interesse concreto em uma ferramenta dedicada a esse tipo de buffer.

A existência desses produtos não significa que o problema esteja em aberto. Significa que a **job-to-be-done é real**.

---

## 2.2 O custo real é context switching + decisão

O produto não deve ser fundamentado simplesmente em “digitar mais rápido”.

A fricção que queremos eliminar tem dois componentes.

### Fricção operacional

Abrir um aplicativo, navegar até determinado lugar, iniciar uma nota, posteriormente voltar ao contexto original.

### Fricção cognitiva

Decidir antecipadamente o que aquele pensamento significa:

* isso merece ser salvo?
* onde deveria estar?
* qual é o título?
* é uma tarefa?
* é uma nota?
* pertence ao projeto X?
* deveria virar uma página?
* deveria ser organizado agora?

Cada decisão individual é pequena. A soma delas quebra o fluxo.

O scratchpad ideal inverte essa relação:

> **capture agora; atribua significado depois, se isso realmente for necessário.**

---

# 3. Job-to-be-done

A job principal pode ser formulada assim:

> **Quando uma informação surgir enquanto estou fazendo outra coisa, quero capturá-la e torná-la utilizável sem interromper meu fluxo ou precisar decidir antecipadamente como organizá-la.**

Isso é diferente de:

> “Quero guardar meu conhecimento.”

Também é diferente de:

> “Quero que uma IA faça tarefas no meu computador.”

E diferente de:

> “Quero conversar com minhas notas.”

Essa delimitação é central.

O produto existe para o momento **anterior à formalização da informação**.

---

# 4. A tese de produto

A formulação mais adequada encontrada durante a exploração é:

> **A scratchpad for unfinished thoughts.**

Em uma formulação mais operacional:

> **An instant, local-first, keyboard-first scratchpad for macOS that turns messy thoughts into usable thoughts with minimal interaction.**

E a constituição mais curta do produto:

> **Capture without thinking. Refine without prompting. Keep only what matters.**

Esses três verbos — **Capture, Refine, Keep** — devem funcionar como filtro de produto.

Toda feature deveria responder claramente:

1. melhora Capture?
2. melhora Refine?
3. melhora Keep?

Se não melhora nenhum deles de maneira significativa, provavelmente está fora do produto.

---

# 5. O produto não é um aplicativo de notas tradicional

Essa distinção precisa ser preservada desde cedo.

Se o produto evoluir naturalmente para:

* folders;
* tags;
* databases;
* templates;
* backlinks;
* graph view;
* dashboards;
* tarefas complexas;
* calendário;
* colaboração;
* documentos;
* projetos;

ele estará caminhando para a mesma categoria de produtos que originalmente pretendia evitar.

A interface minimalista não é suficiente para impedir isso.

Um sistema pode parecer minimalista e ainda impor muitas decisões.

Minimalismo relevante aqui significa:

> **reduzir possibilidades que o usuário precisa considerar.**

Um menu visualmente limpo contendo dez transformações de IA continua sendo cognitivamente complexo.

Por isso, limitar funcionalidade é parte da proposta de valor, não simplesmente uma restrição de desenvolvimento.

---

# 6. O cenário competitivo

A análise de concorrência mostra que praticamente todos os componentes isolados da ideia já existem.

Isso obriga o produto a competir pela **combinação, comportamento e julgamento**, e não por uma feature individual.

## 6.1 Apple Quick Note

O próprio macOS possui Quick Note. O usuário pode utilizar `Fn/Globe + Q` para abrir rapidamente uma nota enquanto trabalha em outro aplicativo, mantendo-a visível enquanto coleta informação.

Consequência estratégica:

**quick capture isoladamente não é um diferencial suficiente.**

Qualquer experiência proposta precisa justificar por que é significativamente melhor do que simplesmente utilizar a capacidade que já acompanha o Mac.

---

## 6.2 Apple Writing Tools

Apple Intelligence torna Writing Tools disponível em grande parte dos lugares onde o usuário escreve, inclusive aplicações e sites de terceiros.

A funcionalidade já inclui proofreading, rewrite, mudanças de tom, resumo, key points, listas, tabelas e transformações por instrução livre. O usuário também consegue comparar com o original e reverter mudanças.

Isso elimina como diferencial qualquer tese genérica do tipo:

> “Use IA para melhorar suas notas.”

Essa capacidade já existe no sistema operacional.

A oportunidade precisa estar em uma experiência superior:

**o produto entende qual transformação faz sentido sem exigir que o usuário escolha a ferramenta ou escreva um prompt.**

---

# 7. Antinote

Antinote é talvez a referência filosófica mais próxima.

O produto explicitamente se posiciona como o lugar onde ficam informações que não deveriam poluir o sistema permanente de notas. Atualmente custa US$5 em compra única, não exige conta, utiliza SQLite local e oferece iCloud opcional. Também possui global hotkey e exportação para sistemas como Apple Notes, Bear e Obsidian.

A principal lição é conceitual:

> **impermanência pode ser uma feature.**

Outra lição é disciplina.

O produto deliberadamente admite que não pretende vencer aplicativos de notas tradicionais nas funcionalidades em que eles são naturalmente melhores.

### O que aprender

* global shortcut;
* rapidez extrema;
* armazenamento local;
* ausência de conta;
* UI quase inexistente;
* temporary-first;
* integração com o OS;
* preço simples;
* capacidade de entregar uma nota para outro sistema.

### O que não fazer

Não construir simplesmente:

> Antinote + botão de IA.

Isso seria uma diferença de feature, não uma nova tese.

---

# 8. Raycast Notes

Raycast Notes é uma ameaça competitiva mais estrutural.

O produto abre com um único hotkey como janela flutuante sobre outros aplicativos, suporta Markdown, múltiplas notas, pesquisa, exportação e integração com o ecossistema Raycast. Cinco notas podem ser utilizadas gratuitamente e notas ilimitadas fazem parte do plano Pro.

Para usuários que já vivem no Raycast, a barreira para adicionar outra utility é alta.

Além disso, o ecossistema Raycast já possui comandos de IA para manipular texto.

Portanto:

**floating notes + keyboard shortcuts + AI commands também não constitui espaço de diferenciação suficiente.**

O produto precisa ser mais específico.

---

# 9. Heynote

Heynote explora outra vertente importante: o scratchpad para power users e developers.

Sua unidade principal é um grande buffer persistente dividido em blocos. Cada bloco pode ter linguagem própria, syntax highlighting e formatting. Atualmente suporta uma ampla variedade de linguagens, pesquisa, múltiplos buffers, atalhos globais, cálculo e outras funcionalidades.

A principal lição é que existe um público disposto a utilizar uma ferramenta dedicada simplesmente porque ela é muito eficiente para informação transitória.

Também mostra o risco de crescimento de escopo: uma scratchpad bem-sucedida naturalmente recebe demandas para múltiplos buffers, imagens, search, cálculos, formatting e diversas outras capacidades.

Por isso, simplicidade precisa ser defendida continuamente, não apenas na V1.

---

# 10. Einfall

Einfall ocupa uma região particularmente próxima da tese.

Sua filosofia é **Capture → Hold → Route**.

Capturar é gratuito e ilimitado. O usuário pode posteriormente enviar pensamentos para Reminders, Calendar e outros destinos. Depois das primeiras ações gratuitas, o desbloqueio completo custa atualmente US$29,99 em compra única. O serviço enfatiza também não possuir infraestrutura própria pela qual o conteúdo do usuário precise passar.

Einfall demonstra que há espaço para pensar o scratchpad como **entrada de um fluxo**, não como destino final.

Mas também indica uma direção que este produto deveria evitar.

Einfall ocupa:

> capture → route.

Nossa oportunidade é diferente:

> **capture → refine.**

Não queremos ser um roteador universal de informação.

---

# 11. Tucky

Tucky representa uma direção mais expansiva.

O posicionamento atual é “Notes at the edge. An agent inside.” As notas vivem na borda da tela e existe um agente associado. Atualmente oferece cinco notas gratuitas e plano de US$4 por mês; o produto enfatiza armazenamento criptografado no Mac.

Essa direção combina notas com uma camada progressivamente mais agentic.

É relevante principalmente porque representa o caminho que **não** queremos seguir:

> notes + agent + connectors + actions + automação.

Existe mercado para isso, mas entrar nele implica competir cada vez mais com Raycast, assistentes gerais e ferramentas de automação.

Nossa vantagem potencial está justamente em resistir a essa expansão.

---

# 12. sticky.md

sticky.md explora de maneira quase literal a tese inicial de “post-its com IA”.

Cada sticky funciona como um pequeno workspace contendo assistente próprio, escolha entre diferentes modelos, Markdown e até terminal embutido.

É uma ótima referência do que aconteceria se a direção original fosse levada ao extremo.

Em termos conceituais:

**sticky.md**

`note → AI workspace`

**produto proposto**

`thought → refine`

A diferença é fundamental.

O primeiro adiciona possibilidades à nota.

O segundo remove trabalho do usuário.

---

# 13. Mapa estratégico

Podemos imaginar o mercado em dois eixos.

No eixo vertical:

**informação temporária → conhecimento permanente**

No horizontal:

**ferramenta passiva → sistema inteligente/ativo**

Aproximadamente:

```text
                   CONHECIMENTO PERMANENTE
                            ↑
                            |
          Apple Notes       |      Tana / Reflect
          Obsidian          |
                            |
 PASSIVO -------------------+------------------- ATIVO
                            |
       Antinote             |     Tucky
       Scratchpad           |     Einfall
       Heynote              |
                            |     NOSSO ESPAÇO
                            |       Refine
                            ↓
                  INFORMAÇÃO TEMPORÁRIA
```

O quadrante inferior direito está crescendo, mas ainda permite diferentes interpretações sobre o que “inteligência” significa.

As principais interpretações observadas são:

**Route** — encaminhar informação.

**Act** — executar ações.

**Chat** — conversar sobre informação.

**Organize** — classificar e armazenar informação.

A tese escolhida é:

> **Refine — compreender um pensamento ainda malformado e transformá-lo na versão mais útil dele.**

---

# 14. O principal diferencial: AI as judgment

A IA não deveria ser tratada como um conjunto de ferramentas disponibilizado ao usuário.

O usuário não deveria precisar aprender:

* qual modelo utilizar;
* qual prompt funciona;
* se deve escolher rewrite ou summarize;
* se deveria pedir bullet points;
* se precisa selecionar “extract action items”;
* se deveria abrir um chat.

O produto deveria absorver essa decisão.

Entrada:

```text
essa fila talvez esteja causando retry duplicado
ver logs
notification queued acho q tá como failed
falar com vitor
```

Ação:

```text
⌘J — Refine
```

Possível resultado:

```text
Possível problema no fluxo de notificações

- Verificar se QUEUED está sendo tratado como FAILED.
- Investigar retries duplicados nos logs.
- Validar o comportamento da fila.
- Alinhar o diagnóstico com Vitor.
```

O modelo fez três coisas:

1. compreendeu o tipo aproximado do conteúdo;
2. escolheu uma estrutura coerente;
3. preservou o significado.

O usuário não precisou definir nenhuma delas.

Essa é a hipótese mais importante do produto.

---

# 15. Refinement Engine

Internamente, Refine pode ser visto como um pequeno sistema de decisão.

Uma primeira taxonomia poderia conter apenas alguns comportamentos:

| Conteúdo identificado | Comportamento                                  |
| --------------------- | ---------------------------------------------- |
| texto desorganizado   | clarificar e estruturar                        |
| conjunto de ações     | checklist                                      |
| meeting dump          | decisões, pontos e próximos passos             |
| ideia                 | estrutura lógica mínima                        |
| rascunho de mensagem  | limpar preservando voz                         |
| texto já bom          | alterações mínimas                             |
| fragmento técnico     | preservar termos e estruturar apenas se seguro |
| baixa confiança       | fazer pouco ou não transformar                 |

A taxonomia deve permanecer pequena.

Não há benefício em possuir cinquenta intents se isso torna o sistema imprevisível.

---

# 16. Princípio de conservação

O Refinement Engine deve seguir uma regra central:

> **Quanto menor a certeza, menor a intervenção.**

Esse princípio é especialmente importante porque generative AI tem tendência a “ajudar demais”.

Uma frase:

```text
perguntar pra João amanhã
```

não deveria virar:

```text
Plano de comunicação com João

Objetivo:
Estabelecer alinhamento estratégico...
```

O resultado correto talvez seja simplesmente:

```text
Perguntar a João amanhã.
```

Ou nenhuma transformação.

Qualidade aqui significa não apenas gerar bons textos, mas saber **quando não gerar muito**.

---

# 17. IA não pode alterar silenciosamente o pensamento

Refine nunca deve destruir o original automaticamente.

O fluxo ideal inclui preview ou capacidade imediata de reversão.

Por exemplo:

```text
original → refined

Esc       cancelar
Enter     aceitar
⌘Z        desfazer
```

Isso está alinhado com a recomendação atual da Apple para experiências generativas: manter o usuário no controle, permitir descartar, retry e revert, e criar uma boa experiência mesmo quando IA não estiver disponível.

A confiança do usuário depende dessa reversibilidade.

---

# 18. IA como implementação, não identidade

O produto não deveria ser vendido como:

> AI Notes.

Modelos estão rapidamente se tornando infraestrutura.

Além disso, funcionalidades como rewrite e summarization já são fornecidas pelo próprio macOS.

A camada duradoura do produto é:

* comportamento;
* interação;
* velocidade;
* critérios de transformação;
* refinamento;
* design;
* confiabilidade;
* hábito.

O modelo utilizado pode mudar sem que o produto mude de identidade.

Arquiteturalmente:

```text
                     PRODUCT EXPERIENCE
                            |
                     Refinement Engine
                            |
                     Apple Foundation
                          Models
                       on-device
```

---

# 19. Apple Foundation Models como único provider da V1

O Foundation Models framework foi introduzido pela Apple em 2025 e disponibilizou para aplicativos acesso ao modelo on-device utilizado pelo Apple Intelligence. O framework suporta geração, análise, guided generation e tool calling; como a inferência pode acontecer localmente, o conteúdo enviado ao modelo permanece no dispositivo e pode funcionar offline.

No macOS 26, a Apple adicionou diretamente essa capacidade ao sistema.

O comportamento principal de Refine — classificação leve, estruturação, extração e rewrite — está muito próximo dos tipos de tarefas apropriados para inferência local.

Consequências:

* nenhuma API key obrigatória;
* nenhuma conta obrigatória;
* ausência de custo de inferência para o fluxo local;
* baixa dependência de backend;
* funcionamento offline;
* privacidade forte;
* integração nativa em Swift.

---

# 20. Sem fallback cloud na V1

```text
Apple Foundation Model disponível
→ Refine on-device

Apple model indisponível
→ Refine indisponível

Em ambos os casos
→ scratchpad, histórico e busca continuam funcionando
```

Não há OpenRouter, BYOK, API key, backend, configuração ou sugestão de fallback cloud na V1.

---

# 21. Local-first deve ser estrutural

Informação temporária frequentemente é mais sensível do que parece.

Um scratchpad naturalmente recebe:

* mensagens ainda não enviadas;
* informação de reunião;
* snippets internos;
* URLs privadas;
* códigos;
* dados copiados;
* rascunhos pessoais;
* fragments de trabalho.

Por isso, armazenamento local não deveria ser apenas marketing de privacidade.

Deveria ser a arquitetura padrão.

A tendência também aparece em produtos comparáveis: Antinote mantém SQLite local e utiliza iCloud opcional do próprio usuário; Tucky enfatiza que as notas ficam no Mac; Einfall afirma não possuir infraestrutura intermediária para o conteúdo.

A V1 pode seguir:

```text
note
 ↓
local database
 ↓
AI only when explicitly invoked
```

Sem backend de notas.

Sem account system.

Sem login.

Sem banco remoto próprio.

---

# 22. Local-first não significa complexidade criptográfica prematura

Não é necessário adicionar encryption application-level simplesmente para utilizar “encrypted” no marketing.

Isso aumenta complexidade em:

* search;
* recovery;
* migrations;
* debugging;
* backups;
* sync.

Na V1, é suficiente priorizar armazenamento local corretamente protegido pelo sistema operacional. Refine não transmite conteúdo: não há segredo externo, Keychain de provider ou ação de envio a configurar.

Criptografia própria pode ser avaliada posteriormente se pesquisas mostrarem que ela influencia materialmente confiança ou compra.

Privacidade deve ser real, não performática.

---

# 23. Lifecycle de uma nota

O modelo de lifecycle precisa evitar dois extremos.

### Extremo 1 — tudo é um único scratch

Extremamente simples, mas pensamentos diferentes se misturam.

### Extremo 2 — tudo vira nota permanente

Retorna ao problema original.

A abordagem recomendada é:

```text
Capture
   ↓
Scratch
   ↓
Use
  / \
 /   \
Discard Keep
```

O usuário nunca precisa escolher “Save”.

Autosave deve ser implícito.

O comando `Keep` significa apenas:

> **isso deixou de ser transitório; não quero perdê-lo.**

Durante o beta, não é aconselhável apagar automaticamente scratches antigos. A confiança seria prejudicada caso usuários interpretem o histórico como persistente.

Primeiro observar comportamento.

Depois decidir se existe valor real em expiração automática.

---

# 24. History, não Library

“Library” carrega um modelo mental de coleção e organização.

“History” comunica melhor:

> isso é o que passou por aqui.

A interface pode sequer possuir uma homepage tradicional.

Busca:

```text
┌───────────────────────────────────────────┐
│ > queue                                   │
├───────────────────────────────────────────┤
│ caramuru queue retry                18m   │
│ queue architecture                  Tue   │
└───────────────────────────────────────────┘
```

Nada de:

* sidebar;
* folder tree;
* dashboards;
* cards;
* collections;
* smart folders;
* organization mode.

O produto deve ser usado, não administrado.

---

# 25. Uma nota ativa por vez

O conceito original falava em post-its na tela.

A pesquisa sugere que isso deveria ser reduzido.

Permitir dezenas de notas flutuantes leva naturalmente à experiência clássica de Stickies: informação espalhada pela tela, competição por atenção e desktop clutter.

Isso contradiz “pouca tinta na tela”.

Uma restrição mais coerente seria:

> **uma superfície ativa de cada vez.**

Ela pode ser mantida always-on-top quando necessário.

Outras notas continuam acessíveis no history/search.

Isso transforma “post-it” em metáfora de comportamento, não em mural.

---

# 26. As três superfícies fundamentais

Idealmente o produto inteiro pode ser compreendido através de três superfícies.

## Scratch

```text
┌───────────────────────────────────────┐
│                                       │
│ ideia: refine deveria inferir o tipo  │
│ da nota antes de transformar...       │
│                                       │
│                          refine  ⌘J  │
└───────────────────────────────────────┘
```

## Refine

```text
┌───────────────────────────────────────┐
│ refined                               │
│                                       │
│ O Refine deve inferir o tipo da nota │
│ antes de escolher a transformação.    │
│                                       │
│ Esc cancel                 ↵ accept   │
└───────────────────────────────────────┘
```

## History/Search

```text
┌───────────────────────────────────────┐
│ > refine                              │
├───────────────────────────────────────┤
│ refinement architecture         12m   │
│ product idea                    Mon   │
└───────────────────────────────────────┘
```

Se a maior parte da experiência não couber nesses três estados, precisamos questionar a complexidade adicionada.

---

# 27. Keyboard-first, mas não keyboard-only

O usuário inicial provavelmente será alguém que trabalha predominantemente pelo teclado.

Isso justifica:

* hotkey global;
* Esc para sair;
* Enter para confirmar;
* shortcuts consistentes;
* fuzzy search;
* command palette.

Mas atalhos não deveriam ser uma barreira de entrada.

O melhor modelo é permitir descobrir comandos por interface e aprender atalhos progressivamente.

Uma command palette pequena poderia conter somente:

```text
New
Find
Keep
Refine
Copy
Delete
Preferences
```

Não pretendemos recriar Raycast dentro da aplicação.

---

# 28. Tempo de interação como requisito

A promessa de velocidade deveria ser mensurável.

Idealmente:

**Capturar**

```text
hotkey → escrever
```

**Sair**

```text
Esc
```

**Refinar**

```text
⌘J → Enter
```

**Encontrar**

```text
hotkey de busca → digitar → Enter
```

As ações frequentes devem precisar de uma ou duas decisões.

Essa regra importa mais do que quantos botões existem visualmente.

---

# 29. Direção visual

A estética de terminal continua fazendo sentido, mas deve ser interpretada como filosofia de interface e não fantasia visual.

Não queremos:

* Matrix green;
* prompt `$`;
* terminal fake;
* excesso de ASCII;
* estética hacker caricata.

Queremos:

* tipografia monoespaçada quando apropriada;
* excelente ritmo;
* pouco chrome;
* indicação textual de estado;
* keyboard affordances;
* alta densidade sem poluição;
* superfícies simples;
* contrastes precisos;
* transições discretas.

“Terminal” significa:

> **precisão e ausência de decoração desnecessária.**

Elementos nativos do macOS podem continuar utilizando SF Pro para que a aplicação pareça parte do sistema.

O texto pode utilizar uma boa fonte mono, preservando legibilidade.

---

# 30. O produto deve parecer uma extensão do macOS

O usuário não deveria pensar:

> “vou entrar no meu aplicativo de notas.”

Idealmente:

> hotkey → pensamento → Esc.

A aplicação aparece no momento necessário e desaparece.

Isso tem consequências:

* startup extremamente rápido;
* baixo uso de recursos;
* animações curtas;
* foco correto imediatamente;
* janela aparecendo no monitor/Space certo;
* comportamento impecável com fullscreen;
* clipboard confiável;
* atalhos confiáveis;
* nenhuma tela intermediária.

Nesse tipo de utility, detalhes de comportamento são mais importantes do que quantidade de funcionalidade.

---

# 31. Arquitetura técnica

Como o produto é Mac-first e sua principal vantagem depende de integração profunda com o sistema, a escolha recomendada é desenvolvimento nativo.

Stack conceitual:

```text
Swift
SwiftUI
AppKit quando necessário
local persistence
Foundation Models
```

SwiftUI deve resolver a maior parte das superfícies.

AppKit provavelmente será necessário para controle fino de:

* janela;
* floating behavior;
* foco;
* Spaces;
* key events;
* ativação;
* menu bar;
* seleção;
* painel acima de outros apps.

Não há um argumento forte para Electron nesse produto.

Cross-platform não faz parte da proposta inicial, enquanto integração nativa é uma das vantagens competitivas.

---

# 32. macOS versioning

O core da aplicação não deveria necessariamente exigir a versão mais recente do macOS apenas por causa da IA.

Uma estratégia possível:

```text
macOS compatível sem Foundation Models
→ capture/history normalmente
→ Refine indisponível

macOS com Foundation Models
→ Refine on-device
```

Isso preserva mercado potencial e permite que AI continue sendo uma melhoria sobre uma aplicação útil, não uma dependência absoluta.

A abstração de modelo também deve considerar que a Apple atualiza `SystemLanguageModel` junto com versões do OS. A própria documentação recomenda retestar prompts quando o modelo muda.

---

# 33. Evals são parte fundamental da engenharia

O Refinement Engine não deveria ser desenvolvido apenas através de “prompt parece bom”.

Precisamos criar um dataset representativo.

Cada exemplo pode possuir:

```text
raw_note
expected_intent
must_preserve
must_not_invent
acceptable_structure
intervention_level
```

Exemplo:

```text
raw:
"falar com mirella amanhã revisar export talvez separar preview"

expected:
actions / messy thought

must_preserve:
- Mirella
- amanhã
- revisar export
- hipótese de separar preview

must_not_invent:
- horário
- decisão já tomada
- responsável além do mencionado
```

Métricas podem combinar:

* preservation;
* hallucination;
* structure fit;
* verbosity;
* transformation acceptance;
* similarity às preferências humanas.

Isso se torna especialmente importante se o Foundation Model variar entre versões do macOS.

A Apple atualmente também oferece um Evaluations framework voltado para testar comportamento de experiências baseadas em modelos.

---

# 34. Métrica norteadora de IA

Uma das melhores métricas comportamentais seria:

> **Refine Acceptance Rate**

Quantas vezes o usuário executa Refine e aceita o resultado?

Mas aceitação isolada ainda não é suficiente.

Também interessa observar:

> quanto ele modifica imediatamente depois?

Uma possível métrica:

**post-refine edit distance**

Se o usuário aceita Refine e depois precisa reescrever metade do resultado, a feature aparentemente foi utilizada, mas não resolveu bem o problema.

---

# 35. Métricas de produto

Na fase inicial, métricas úteis incluem:

| Métrica             | O que revela                     |
| ------------------- | -------------------------------- |
| time to capture     | fricção central                  |
| active days/week    | formação de hábito               |
| captures/day        | frequência natural da job        |
| refine rate         | relevância da IA                 |
| refine acceptance   | qualidade percebida              |
| edits after refine  | qualidade real                   |
| search/revisit rate | utilidade do histórico           |
| keep rate           | proporção transitório/permanente |
| session duration    | deve provavelmente ser baixa     |

Uma característica interessante:

**session duration alta pode ser ruim.**

O objetivo não é prender atenção.

Um usuário que abre a utility 15 vezes no dia por dez segundos pode estar obtendo mais valor que alguém que passa 40 minutos nela.

---

# 36. Validação

Antes de desenvolver uma aplicação grande, precisamos validar a tese comportamental.

A pergunta principal não é:

> “Você acha a ideia legal?”

É:

> **Depois de utilizar isso por uma semana, você naturalmente começa a abrir esse scratchpad quando um pensamento surge?**

E principalmente:

> **Refine oferece valor suficiente para justificar utilizar esta ferramenta em vez de Quick Note, Raycast ou Antinote?**

Experimentos prioritários incluem protótipo funcional, uso real durante vários dias, entrevistas posteriores e comparação explícita com alternativas existentes.

Um teste particularmente rigoroso seria comparar a experiência contra:

**Apple Quick Note + Writing Tools.**

Se nosso fluxo não for claramente melhor, o produto não tem justificativa suficiente.

---

# 37. Hipótese crítica

A hipótese que pode matar o produto é:

> **Refine não acrescenta valor suficiente.**

Se isso acontecer, teremos essencialmente construído outro scratchpad minimalista.

Esse mercado já possui boas alternativas.

Portanto, antes de investir em sync, polished preferences, onboarding sofisticado ou outras funcionalidades, precisamos descobrir se:

```text
messy thought
     ↓
   Refine
     ↓
usable thought
```

é uma interação que as pessoas passam a desejar repetidamente.

---

# 38. Público inicial

Não deveríamos posicionar o produto como:

> notes for everyone.

O público inicial mais coerente é:

> **keyboard-heavy Mac users who deal with many temporary thoughts during focused work.**

Exemplos naturais:

* software engineers;
* designers;
* product managers;
* founders;
* writers;
* researchers;
* analysts;
* knowledge workers.

A estética pode dialogar particularmente bem com developers e power users, mas não é aconselhável fechar o mercado prematuramente a desenvolvedores.

---

# 39. Possível wedge developer-first

Existe, porém, um caminho alternativo interessante caso o produto generalista não demonstre diferenciação suficiente.

Refine poderia compreender fragmentos típicos do trabalho técnico:

```text
JSON → format
SQL → format
stack trace → summarize
rough bug → structure issue
debug dump → investigation steps
meeting notes → actions
code → preserve strictly
```

Heynote demonstra que developers utilizam scratchpads dedicados para exatamente alguns desses fluxos.

Por enquanto isso deveria permanecer como possível pivot, não como requisito da V1.

---

# 40. Anti-features

A restrição precisa ser explícita.

Na tese atual, deliberadamente **não fazem parte do produto**:

**Folders** — criam organização antecipada.

**Tags manuais** — adicionam housekeeping.

**Graph view** — pertence a knowledge management.

**Databases** — muda completamente o modelo mental.

**Task manager** — tarefas extraídas podem ser úteis, mas gerenciá-las é outro produto.

**Calendar** — outro domínio.

**Agents** — aumenta drasticamente superfície, risco e expectativas.

**Connectors** — transformam a utility em hub.

**Chat com todas as notas** — empurra para second brain.

**AI model picker** — fora de escopo da V1.

**Templates** — exigem escolha antecipada.

**Collaboration** — outro problema.

**Team accounts** — outro mercado.

**Dashboard** — incentiva gerenciamento.

**Gamification** — desalinhada à proposta.

**Browser extension** — não necessária para validar o core.

**iPhone app** — não necessária inicialmente.

**Voice capture** — potencialmente útil, mas não antes de provar capture/refine textual.

Essas decisões não são eternas.

Mas quebrá-las deve exigir evidência, não entusiasmo.

---

# 41. Escopo recomendado da V1

A primeira versão pode ser surpreendentemente pequena.

### Obrigatório

**Global shortcut**

Abre instantaneamente o scratch atual.

**Editor extremamente simples**

Texto, seleção e operações básicas confiáveis.

**Autosave local**

Nenhuma ação de Save.

**History/Search**

Recuperar scratches existentes.

**Always-on-top**

Quando o usuário precisa consultar algo enquanto trabalha.

**Refine**

Uma única ação inteligente.

**Preview / Accept / Revert**

Nenhuma transformação destrutiva.

**Menu bar**

Acesso secundário e configurações.

### Possivelmente V1

**Keep**

Se o lifecycle demonstrar necessidade.

**Markdown muito básico**

Somente se ajudar legibilidade sem transformar o produto em editor.

**Command palette pequena**

Para discoverability.

### Não V1

Sync, mobile, integrations, agents, voice, múltiplos sticky windows, AI chat, folders, tags, reminders e automações.

---

# 42. Monetização

A categoria demonstra diferentes estratégias.

Antinote cobra atualmente US$5 one-time.

Einfall cobra US$29,99 uma única vez para liberar routing ilimitado.

Tucky utiliza US$4/mês.

Para este produto, subscription inicialmente parece menos coerente.

Como o core e o Refine da V1 são locais, o custo marginal recorrente por usuário pode ser muito pequeno.

Uma estrutura plausível para teste seria:

> **free trial → pagamento único**

Uma hipótese inicial razoável de preço seria algo entre **US$14,99 e US$19,99**, não como decisão final, mas como faixa a validar.

Ela posiciona o produto como utility premium sem exigir uma relação de subscription que ainda não possui justificativa econômica.

---

# 43. Distribuição

Para um beta inicial, distribuição direta parece mais adequada do que começar exclusivamente pela Mac App Store.

A Apple permite distribuição externa com Developer ID, assinatura apropriada e notarização. Na Mac App Store, sandboxing é obrigatório; fora dela, é recomendado, enquanto updates e billing ficam sob responsabilidade do desenvolvedor.

Um fluxo inicial possível:

```text
website
↓
download
↓
signed + notarized macOS app
↓
automatic updater
```

Isso facilita iteração durante beta.

A Mac App Store pode ser avaliada posteriormente como canal adicional.

Para desenvolvedores elegíveis ao Small Business Program, a Apple mantém atualmente comissão reduzida de 15% em apps pagos e compras elegíveis.

---

# 44. Distribuição orgânica e apresentação

Esse tipo de produto possui uma vantagem relevante:

**é extremamente demonstrável.**

Um vídeo de dez segundos pode explicar toda a proposta.

Exemplo:

```text
VS Code

⌥Space

"queue retry ta duplicando
queued parece failed
falar com vitor"

⌘J

"Investigate notification retries

□ Verify duplicated retries
□ Check QUEUED vs FAILED status
□ Align findings with Vitor"

Enter
Esc

VS Code
```

Nenhum tutorial é necessário para compreender a transformação.

Isso torna comunidades de Mac users, developers, productivity enthusiasts, Hacker News, Reddit e Product Hunt canais naturais para validação inicial.

---

# 45. Posicionamento

Evitar:

> AI-powered note taking.

Genérico e facilmente replicável.

Evitar:

> The ultimate productivity app.

Contrário à filosofia.

Evitar:

> Your second brain.

Categoria completamente diferente.

Evitar:

> AI agent for Mac.

Competição muito mais ampla e desalinhada.

Possíveis formulações:

> **A scratchpad for unfinished thoughts.**

> **Turn messy thoughts into useful ones.**

> **The space between thinking and writing it down properly.**

> **Capture first. Refine later.**

A formulação conceitualmente mais completa continua:

> **Capture without thinking. Refine without prompting. Keep only what matters.**

---

# 46. O moat

Não existe um moat tecnológico óbvio.

Qualquer concorrente relevante poderia implementar uma função semelhante a Refine.

A defensibilidade precisa vir de uma combinação:

```text
taste
+ interaction quality
+ speed
+ reliability
+ refinement quality
+ native integration
+ habit
+ brand
```

É uma lógica semelhante a excelentes Mac utilities: nenhuma feature isolada é impossível de copiar, mas o conjunto pode construir preferência forte.

O objetivo não deve ser fingir que existe uma barreira tecnológica que não existe.

---

# 47. Tipo de oportunidade

A tese parece particularmente forte como:

> **indie software / small focused software business**

Pode se tornar um produto pago muito bom para um nicho global de usuários de Mac.

Mantendo deliberadamente esse escopo, não existe razão para supor que ele se transformará naturalmente em uma companhia de escala enorme.

Isso não é uma deficiência.

Um produto pequeno, altamente utilizado, barato de operar e global pode ser economicamente muito interessante.

Tentar artificialmente transformá-lo em startup de plataforma — adicionando teams, agents, integrations, workflow automation e enterprise — pode destruir justamente o que o torna valioso.

---

# 48. Critério de decisão para novas features

Em vez de perguntar:

> “Isso seria legal?”

utilizar:

### Pergunta 1

**Isso reduz o tempo entre ter um pensamento e ter algo útil?**

### Pergunta 2

**Isso reduz ou aumenta a quantidade de decisões exigidas do usuário?**

### Pergunta 3

**Isso pertence estruturalmente a Capture, Refine ou Keep?**

### Pergunta 4

**A funcionalidade precisa estar dentro deste produto ou existe outro aplicativo que deveria continuar resolvendo esse problema?**

### Pergunta 5

**Remover essa funcionalidade faria o core pior?**

Se não, provavelmente não precisamos dela.

---

# 49. Princípios permanentes de produto

### 1. Friction is the enemy

Qualquer interação evitável deve ser questionada.

### 2. Intelligence should remove choices

IA deve reduzir decisões, não criar um menu maior de capacidades.

### 3. Temporary is a valid state

Nem toda informação precisa ser promovida a conhecimento permanente.

### 4. Local by default

Dados ficam na máquina sempre que possível.

### 5. The original thought is sacred

IA não deve inventar, sobrescrever silenciosamente ou alterar intenção.

### 6. Do less when uncertain

Incerteza deve reduzir a magnitude da transformação.

### 7. The app should disappear

A melhor sessão muitas vezes termina poucos segundos depois de começar.

### 8. Native behavior beats feature count

Focus, hotkeys, Spaces, clipboard, window placement e responsiveness importam mais que uma longa lista de funcionalidades.

### 9. No organization tax

O usuário não deveria manter o sistema para poder utilizá-lo.

### 10. Features must earn their existence

A complexidade é um custo permanente.

---

# 50. Perguntas ainda em aberto

Apesar da tese estar consideravelmente mais madura, algumas decisões só devem ser tomadas após uso real.

### Scratch lifecycle

Cada hotkey cria uma nova scratch ou retorna à última?

### Keep

É necessário existir explicitamente ou search/history já resolve?

### Expiration

Scratches antigos deveriam desaparecer automaticamente ou apenas sair do caminho?

### One active note

Uma restrição de uma nota visível é realmente melhor ou usuários precisam comparar duas informações?

### Markdown

Até que ponto formatting melhora a utilidade antes de virar editor?

### Refine trigger

Refine deve existir apenas manualmente ou o sistema pode discretamente sinalizar que identificou uma transformação útil?

### Refine indisponível

Em Macs sem modelo local disponível, Refine fica indisponível sem oferecer fallback externo; o produto principal continua útil.

### Naming

Notas mantidas precisam de título? Ele pode ser completamente inferido?

### Window behavior

Centro, posição anterior, próximo ao cursor ou outra estratégia?

### Search

Somente lexical/fuzzy é suficiente? Provavelmente sim inicialmente.

Essas são perguntas para protótipo e pesquisa, não para especulação indefinida.

---

# 51. O experimento central

O principal experimento pode ser reduzido a uma pergunta:

> **Se entregarmos a uma pessoa um scratchpad instantâneo e um Refine excepcionalmente bom, isso se torna parte natural do fluxo diário dela?**

Se sim, existe produto.

Se o scratchpad é utilizado mas Refine não é, existe demanda por quick capture, mas ainda não diferenciação.

Se Refine é utilizado mas os resultados são frequentemente refeitos, o problema está no Refinement Engine.

Se os usuários preferem Apple Quick Note ou Raycast, nossa redução de fricção não é suficiente.

Se pedem imediatamente folders, projects e organização, talvez estejamos atraindo o público errado ou resolvendo uma job diferente.

---

# 52. North Star comportamental

Não escolheria inicialmente MAU, número de notas ou minutos dentro do aplicativo como north star.

Uma interpretação melhor de sucesso seria:

> **número de dias em que o produto intercepta naturalmente pensamentos transitórios e os resolve com baixa fricção.**

No estágio inicial, um sinal forte seria um usuário dizer:

> “Comecei a apertar o shortcut sem pensar.”

Nesse momento, o produto tornou-se hábito.

O segundo sinal seria:

> “Sinto falta do Refine quando escrevo em outro lugar.”

Nesse momento, existe diferenciação.

---

# 53. A grande disciplina necessária

Praticamente todos os produtos dessa categoria demonstram uma tendência:

uma utility pequena resolve uma dor;

usuários gostam;

começam a pedir mais;

as funcionalidades parecem individualmente razoáveis;

e progressivamente nasce outro sistema complexo.

A dificuldade não será encontrar coisas para construir.

Será recusar coisas boas que não pertencem à tese.

Por isso, a lista de omissões é parte do produto.

---

# 54. Definição final do produto neste estágio

**O produto é um scratchpad nativo e local-first para macOS destinado a capturar pensamentos transitórios sem interromper o fluxo de trabalho. Ele aparece instantaneamente por um atalho global, não exige organização e desaparece assim que deixa de ser necessário. Quando um pensamento cru precisa se tornar mais útil, uma única ação de Refine compreende o conteúdo e aplica a transformação mínima mais adequada, sem exigir prompt, escolha de modelo ou seleção entre inúmeras ferramentas de IA. O usuário sempre mantém controle sobre o original e pode simplesmente utilizar, descartar ou preservar o resultado.**

Ele não pretende guardar toda a vida digital do usuário.

Não pretende substituir seu sistema permanente de notas.

Não pretende executar tudo por ele.

Não pretende transformar cada pensamento em um objeto organizado.

Ele existe para resolver excepcionalmente bem os poucos segundos entre:

> **“pensei em algo”**

e

> **“agora isso está escrito de uma forma útil.”**

---

# 55. Visão

O melhor resultado para esse produto não é possuir cem funcionalidades.

É chegar ao ponto em que a interação pareça óbvia em retrospecto:

```text
thought
  ↓
hotkey
  ↓
write
  ↓
refine if needed
  ↓
back to work
```

Uma ferramenta pequena o suficiente para desaparecer.

Inteligente o suficiente para ajudar.

Restrita o suficiente para não exigir gerenciamento.

E útil o suficiente para se tornar memória muscular.

---

## Tese final

> **Capture without thinking.**
> **Refine without prompting.**
> **Keep only what matters.**
