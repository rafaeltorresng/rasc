# UX/UI Spec V1 — Scratchpad Inteligente para macOS

**Status:** Especificação de experiência
**Versão:** V1
**Plataforma:** macOS
**Objetivo:** traduzir o PRD em comportamento de interface suficientemente concreto para prototipação e implementação.

---

# 1. Princípio central de UX

A aplicação não deve parecer um “lugar para entrar”.

Ela deve parecer uma camada temporária do macOS.

O fluxo ideal é:

```text
estou trabalhando
      ↓
atalho
      ↓
escrevo
      ↓
Esc
      ↓
continuo trabalhando
```

Ou:

```text
estou trabalhando
      ↓
atalho
      ↓
escrevo algo confuso
      ↓
Refine
      ↓
aceito
      ↓
Esc
      ↓
continuo trabalhando
```

A interface deve existir somente durante o intervalo em que agrega valor.

---

# 2. Hierarquia de importância

Toda decisão visual deve seguir esta ordem:

1. velocidade;
2. previsibilidade;
3. legibilidade;
4. ausência de distração;
5. aparência.

Uma interface visualmente bonita que atrasa foco ou exige interpretação é pior que uma interface simples e instantânea.

---

# 3. Superfícies da V1

A aplicação terá apenas cinco superfícies relevantes:

1. Scratchpad
2. Refine Preview
3. History/Search
4. Command Palette
5. Preferences

Menu bar existe como affordance secundária.

Não existe homepage.

Não existe dashboard.

Não existe sidebar.

Não existe workspace principal.

---

# 4. Scratchpad

O Scratchpad é a superfície dominante.

Visualmente:

```text
┌──────────────────────────────────────────┐
│                                      ·   │
│                                          │
│ escrever aqui                            │
│                                          │
│                                          │
│                                          │
│                                          │
│                           ⌘J  refine      │
└──────────────────────────────────────────┘
```

O conteúdo ocupa quase toda a janela.

Elementos permanentes devem ser mínimos.

---

# 5. Header

Idealmente não existe um header tradicional.

Evitar:

```text
[traffic lights]  Untitled Note      [...]
```

A janela pode utilizar chrome reduzido ou oculto quando tecnicamente seguro.

Precisamos preservar comportamento nativo de macOS sem criar uma barra visualmente pesada.

Se forem necessários controles visuais, eles devem aparecer apenas em hover ou quando a janela não está em modo de escrita.

---

# 6. Indicador de estado

A interface pode possuir um indicador extremamente discreto no topo ou rodapé.

Exemplos:

```text
scratch
```

ou:

```text
kept
```

ou nenhum indicador para scratch normal.

`Kept` merece um pequeno sinal porque é uma mudança semântica.

Evitar badges chamativos.

---

# 7. Editor

O editor é plain-text first.

Markdown pode ser reconhecido, mas não deve transformar a experiência em editor visual complexo.

Características:

* cursor padrão;
* seleção nativa;
* copy/paste nativos;
* Undo/Redo;
* spellcheck compatível com macOS;
* smart quotes opcionais de acordo com sistema;
* multiline;
* links detectáveis;
* code blocks preservados.

Não haverá toolbar de formatting.

---

# 8. Tipografia

Conteúdo:

* fonte monoespaçada;
* aproximadamente 13–15 pt;
* line-height confortável;
* sem densidade excessiva.

Interface sistêmica:

* SF Pro.

A fonte mono deve transmitir precisão, não nostalgia terminal.

O texto precisa funcionar bem tanto para prosa quanto para código.

---

# 9. Margens

A janela precisa respirar, apesar da estética compacta.

Algo aproximadamente equivalente a:

```text
24 px horizontal
20–24 px vertical
```

deve ser explorado visualmente.

Margens pequenas demais deixam a utility com aparência de terminal cru.

Margens grandes demais desperdiçam espaço e tornam o painel visualmente dominante.

---

# 10. Cor

Usar system appearance.

Light:

* fundo próximo das superfícies nativas do macOS;
* texto de alto contraste;
* borders quase imperceptíveis.

Dark:

* fundo escuro neutro;
* evitar preto absoluto;
* texto levemente reduzido em contraste quando apropriado.

Não estabelecer uma cor de marca dominante dentro do editor.

---

# 11. Janela

Tamanho inicial sugerido:

```text
width: 480–560 px
height: 300–380 px
```

Ponto inicial razoável para protótipo:

```text
520 × 340
```

A janela é redimensionável.

Limites iniciais sugeridos:

```text
min width: 360
min height: 220

max width: ~800
max height: ~700
```

Não permitir fullscreen como parte normal da UX.

---

# 12. Radius e sombra

A superfície deve parecer uma utility nativa moderna.

Utilizar:

* corner radius moderado;
* shadow suave;
* border sutil se necessário.

Nada semelhante a um post-it amarelo literal.

A metáfora de post-it deve existir no comportamento, não na aparência física.

---

# 13. Abertura

Ao pressionar global hotkey:

1. localizar display relevante;
2. abrir janela imediatamente;
3. restaurar conteúdo ativo;
4. posicionar cursor;
5. aceitar digitação.

Não deve haver animação longa.

Fade/scale muito curto pode existir se não prejudicar sensação de instantaneidade.

---

# 14. Comportamento se já estiver aberto

Se o Scratchpad já estiver visível e o usuário pressionar o mesmo global hotkey:

primeira hipótese para V1:

> esconder.

Isso transforma o atalho em toggle.

```text
hotkey → show
hotkey → hide
```

É simples de aprender.

---

# 15. Foco ao abrir

Ao abrir:

* janela torna-se key;
* editor recebe first responder;
* cursor aparece na última posição conhecida ou ao final.

Hipótese inicial:

> cursor no local onde estava anteriormente.

Se a nota for nova:

> início.

---

# 16. Fechar com Esc

`Esc`:

* salva;
* oculta;
* devolve foco ao aplicativo anterior.

Não destrói janela/processo necessariamente.

Não pergunta nada.

---

# 17. Clique fora

Precisamos deliberadamente decidir se clicar fora fecha.

Recomendação inicial:

> não fechar automaticamente.

Motivo:

o usuário pode querer consultar a nota enquanto trabalha em outro app.

Auto-dismiss ao perder foco tornaria a aplicação imprevisível.

O usuário usa `Esc` ou hotkey para esconder.

---

# 18. Always on top

Por padrão, recomendo que a janela seja:

> floating enquanto visível.

Isso reforça a função de scratchpad.

Ela não deve roubar foco quando o usuário clica no aplicativo abaixo.

O conteúdo continua visível.

---

# 19. Pin

Essa decisão pode ser simplificada.

Se a janela naturalmente fica above other windows enquanto aberta, talvez `Pin` não seja necessário na V1.

Isso elimina uma distinção desnecessária.

A UX pode ser:

```text
open = visible/floating
Esc = gone
```

Mais simples.

Recomendação atual:

> remover `Pin` como feature explícita da V1.

---

# 20. Nova nota

`⌘N`

Comportamento:

1. salvar nota atual;
2. criar scratch vazia;
3. permanecer na mesma janela;
4. foco no editor.

Não transicionar para outra tela.

---

# 21. Trocar entre notas

O usuário não navega por tabs.

Não existem tabs.

Troca entre notas acontece através de History/Search.

Isso reduz chrome e estado visual.

---

# 22. History/Search

Atalho sugerido:

```text
⌘P
```

ou:

```text
⌘O
```

Precisamos verificar conflitos durante implementação.

A superfície pode substituir temporariamente o conteúdo da janela atual:

```text
┌──────────────────────────────────────────┐
│ > search notes                           │
├──────────────────────────────────────────┤
│ meeting follow-up                  3m    │
│ queue debugging                   42m    │
│ app idea                           Tue   │
│ monitor dimensions                Mon   │
└──────────────────────────────────────────┘
```

Não abrir nova janela.

---

# 23. Search field

O campo recebe foco automaticamente.

Placeholder:

```text
Search notes…
```

ou simplesmente:

```text
Search…
```

Sem filtros iniciais.

---

# 24. Search results

Cada item deve mostrar somente:

* título inferido/primeira linha;
* trecho opcional;
* recência;
* indicador `kept`, se necessário.

Exemplo:

```text
queue debugging
retry acontecendo antes do update...             42m
```

Evitar metadata demais.

---

# 25. Navegação no History

```text
↑ / ↓       selecionar
Enter       abrir
Esc         voltar
⌘N          nova nota
```

Mouse também funciona normalmente.

---

# 26. Busca vazia

Sem query:

mostrar notas recentes.

Algo como 8–12 resultados visíveis é suficiente.

Não criar seções como:

* Recent
* Favorites
* Pinned
* Today
* This Week

na V1.

---

# 27. Empty state

Se não houver outras notas:

```text
No previous notes.
```

Só isso.

Sem ilustração.

Sem CTA grande.

---

# 28. Keep

A necessidade de `Keep` deve ser tratada cuidadosamente.

Visualmente, se existir:

```text
⌘⇧K
```

alterna:

```text
scratch ↔ kept
```

Feedback discreto:

```text
kept
```

durante ~1 segundo ou como pequeno estado persistente.

Não há diálogo.

---

# 29. Consideração sobre Keep

Há uma possibilidade real de que Keep seja desnecessário na V1.

Se todo histórico é persistente, o significado de Keep fica fraco.

Portanto, precisamos responder durante prototipação:

> O que Keep efetivamente muda?

Se a única resposta for “mostra uma estrela”, removemos.

Keep só deve existir se estiver associado a um lifecycle real, como retenção futura.

Até lá:

> **candidate feature, não requisito obrigatório.**

---

# 30. Refine — entrada

Atalho recomendado:

```text
⌘J
```

Motivos:

* fácil;
* não tão disputado quanto alguns atalhos padrão;
* suficientemente próximo da mão;
* pode virar memória muscular.

Ao pressionar:

* se existe seleção → refinar seleção;
* caso contrário → refinar nota inteira.

---

# 31. Refine — loading

A janela permanece igual.

No rodapé:

```text
refining…
```

Talvez uma animação textual mínima.

Evitar modal.

Evitar skeleton.

Evitar abrir painel lateral.

---

# 32. Refine — resultado

Quando resultado chega, o editor entra em um modo temporário de preview.

Exemplo:

```text
┌──────────────────────────────────────────┐
│ refined                                  │
│                                          │
│ Possible race condition between retry    │
│ and queue tick.                          │
│                                          │
│ - Inspect the logs.                      │
│                                          │
│ Esc cancel                   ↵ accept    │
└──────────────────────────────────────────┘
```

O preview deve parecer claramente diferente do estado de edição, mas sem criar outra interface pesada.

---

# 33. Diferenciação visual do preview

Possibilidades:

* pequeno label `refined`;
* subtle border;
* texto temporariamente read-only;
* linha divisória sutil no rodapé.

Não usar cores chamativas.

---

# 34. Original vs refined

Não mostrar diff completo na V1 por default.

Um diff visual permanente acrescentaria complexidade.

O usuário sabe que está vendo uma proposta.

Se quiser:

```text
Esc → original
Enter → refined
```

Essa dicotomia é suficiente.

---

# 35. Accept

`Enter`

aceita.

Ao aceitar:

* preview vira conteúdo normal;
* editor volta a ser editável;
* cursor vai para posição razoável;
* Undo guarda versão anterior.

Feedback opcional:

```text
refined
```

por ~1 segundo.

---

# 36. Cancel

`Esc`

durante preview:

* descarta resultado;
* restaura conteúdo original;
* mantém janela aberta;
* foco volta ao editor.

`Esc` novamente:

* fecha Scratchpad.

Isso é uma hierarquia natural.

---

# 37. Retry

Não exibir como botão principal.

Pode existir via:

```text
⌘R
```

durante preview.

Mas precisamos verificar conflito semântico com refresh.

Alternativa:

Command Palette → Retry Refine.

Se pouco usado, ótimo.

---

# 38. Falha de Refine

Erro aparece como linha discreta:

```text
Refine unavailable.
```

ou:

```text
Couldn't refine this note.
```

Pode existir ação:

```text
Try again
```

apenas se útil.

Não abrir alert modal.

---

# 39. Conteúdo vazio

Se usuário pressiona `⌘J` em nota vazia:

não fazer nada.

Opcionalmente:

```text
Nothing to refine.
```

durante um instante.

---

# 40. Conteúdo muito curto

Exemplo:

```text
joão amanhã
```

O produto deve poder concluir internamente que não há transformação segura.

Pode responder:

```text
No refinement needed.
```

ou manter praticamente igual.

Não inventar significado.

---

# 41. Command Palette

Atalho:

```text
⌘K
```

Visual:

```text
┌──────────────────────────────────────────┐
│ >                                        │
├──────────────────────────────────────────┤
│ Refine                            ⌘J      │
│ New note                          ⌘N      │
│ Find note                         ⌘P      │
│ Keep                            ⇧⌘K       │
│ Copy                              ⌘C      │
│ Delete                           ⌘⌫       │
│ Preferences                       ⌘,      │
└──────────────────────────────────────────┘
```

Poucas ações.

---

# 42. Command Palette como aprendizado

O objetivo não é tornar o produto dependente dela.

Ela serve para:

* descoberta;
* fallback;
* ensino de atalhos.

Após alguns dias, o usuário deveria quase não abrir.

---

# 43. Busca da Command Palette

Pode ser fuzzy.

Digitar:

```text
ref
```

seleciona:

```text
Refine
```

Não incluir configurações obscuras.

---

# 44. Preferences

Abrir com:

```text
⌘,
```

A janela pode ser nativa, separada.

Tabs talvez sejam desnecessárias inicialmente.

Uma única tela simples.

---

# 45. Preferences — seção General

```text
General

Global shortcut     [⌥ Space]
Launch at login     [on]
Show menu bar icon  [on]
Appearance          [System ▾]
```

Só isso.

---

# 46. Preferences — seção Refine

```text
Refine

Model               On-device
                    Apple Intelligence
```

Foundation Models é o único provider de Refine na V1; não há fallback cloud, BYOK, API key ou seletor de modelo.

Possível copy:

```text
Refine runs on-device when available.
```

---

# 47. Providers externos — fora de escopo da V1

Não há configuração de OpenRouter, API key, BYOK, fallback cloud ou provider externo na V1.

---

# 48. Privacidade na Preferences

Uma frase simples:

```text
Your notes are stored locally on this Mac.
Refine runs on-device when available.
```

Isso agrega confiança sem transformar a tela em documentação jurídica.

---

# 49. Menu bar

Clique no ícone:

```text
Open Scratchpad
New Note
Find Note
──────────────
Preferences
Quit
```

No máximo.

O menu bar não deve ter lista inteira de notas.

Isso já começaria a duplicar History.

---

# 50. Right-click

Context menu no editor pode respeitar operações nativas:

* Cut
* Copy
* Paste
* Select All
* Look Up
* Writing Tools do sistema, se tecnicamente aplicável

E talvez:

* Refine

Não adicionar muitas ações próprias.

---

# 51. Status visual

Evitar sistema de badges.

Estados que podem aparecer discretamente:

```text
refining…
refined
saved
kept
offline
```

`saved` talvez nem precise aparecer, já que autosave deve ser confiável por definição.

---

# 52. Autosave UX

Não exibir spinner de save.

Salvar deve ser silencioso.

Só mostrar algo se houver falha real.

Exemplo:

```text
Couldn't save locally.
```

Essa falha é grave e deve ser rara.

---

# 53. Delete UX

Possível atalho:

```text
⌘⌫
```

Recomendação:

não apagar imediatamente.

Fluxo:

```text
⌘⌫
```

→ nota some e entra em soft-delete.

Toast discreto:

```text
Note deleted · Undo
```

durante poucos segundos.

Isso reduz confirmação modal.

---

# 54. Empty scratch behavior

Se uma nota vazia for fechada:

não precisa ser persistida.

Isso evita History cheio de vazios.

Regra:

```text
content.trim().isEmpty
→ discard automatically
```

---

# 55. Whitespace

Uma nota apenas com espaços/newlines também é vazia.

Não persistir.

---

# 56. Untitled behavior

Usuário nunca vê “Untitled”.

Se não há título inferido:

mostrar primeira linha.

Se primeira linha for longa:

truncar.

Se conteúdo começar com code block:

usar primeiro trecho textual ou representação curta.

---

# 57. AI title

Não necessário para cada scratch.

Somente considerar quando nota fica difícil de representar na busca.

Podemos gerar title como parte do mesmo output de Refine sem chamada adicional:

```json
{
  "type": "technical",
  "title": "Queue retry race condition",
  "content": "..."
}
```

Mas isso continua invisível ao usuário.

---

# 58. History item hover

Hover pode revelar ações secundárias:

```text
delete
keep
```

Mas não exibir ícones permanentemente.

No teclado, ações continuam disponíveis.

---

# 59. Scroll

Notas grandes podem scrollar normalmente.

History também.

Não adicionar minimap ou document outline.

---

# 60. Code blocks

Se uma nota possui fenced code:

````
```json
...
```
````

renderização pode usar syntax tinting futuramente.

V1 pode simplesmente preservar monoespaçado.

O editor inteiro já é mono.

---

# 61. URLs

Clique com Command pode abrir.

Comportamento deve seguir convenções macOS.

Não transformar o produto em bookmark manager.

---

# 62. Links copiados

Ao colar URL, manter URL.

Não buscar automaticamente:

* title;
* favicon;
* preview;
* metadata.

Esse tipo de enrichment adiciona rede e estado sem resolver core.

---

# 63. Imagens

Não suportar V1.

Se usuário colar imagem:

opções possíveis:

* ignorar;
* manter apenas texto do clipboard se existir.

Não criar attachment architecture prematuramente.

---

# 64. Drag and drop

Não necessário inicialmente.

---

# 65. Voice

Não V1.

---

# 66. Menu de modelos

Não V1 na superfície principal.

---

# 67. Shortcut map inicial

Proposta sujeita a validação:

```text
Global hotkey   Open/Hide scratchpad
⌘N              New scratch
⌘P              Find note
⌘J              Refine
⌘K              Command Palette
⌘,              Preferences
⌘⌫              Delete
Esc             Back / Hide
Enter           Accept Refine
⌘Z              Undo
```

`Keep` não recebe necessariamente um atalho até confirmarmos sua utilidade.

Menos shortcuts é melhor.

---

# 68. Hierarquia do Esc

`Esc` deve ser extremamente consistente.

Prioridade:

```text
Command Palette open
→ close palette

Search open
→ close search

Refine preview
→ cancel preview

Refine loading
→ cancel request

Normal editor
→ hide scratchpad
```

Isso deve funcionar sem exceções surpreendentes.

---

# 69. Hierarquia do Enter

Normal editor:

> newline.

Refine preview:

> accept.

Search:

> open selected result.

Command Palette:

> execute selected command.

Contexto deve deixar o comportamento óbvio.

---

# 70. Onboarding V1

Tela 1:

```text
A scratchpad,
one shortcut away.

Capture anything without leaving
what you're doing.

[Continue]
```

Tela 2:

```text
Choose your shortcut

[⌥ Space]

[Continue]
```

Tela 3:

```text
Write first.
Refine when needed.

⌘J   Refine
Esc  Back to work

[Open Scratchpad]
```

Fim.

---

# 71. Não explicar tudo no onboarding

Não ensinar:

* History;
* Delete;
* Preferences;
* Keep;
* command palette.

Essas coisas podem ser descobertas depois.

O usuário precisa aprender apenas:

```text
open
type
refine
close
```

---

# 72. Primeira captura

Scratchpad abre vazio.

Um placeholder opcional:

```text
Write anything…
```

Assim que usuário começa a digitar, some.

Não inserir exemplo pré-preenchido.

---

# 73. Primeira descoberta de Refine

Enquanto usuário ainda não usou Refine:

rodapé:

```text
⌘J refine
```

Após algumas utilizações:

pode continuar, mas visualmente mais discreto.

---

# 74. First successful Refine

Após aceitar pela primeira vez, talvez mostrar apenas uma microexplicação:

```text
⌘Z to undo
```

uma única vez.

Sem celebratory UI.

---

# 75. History discovery

Depois de múltiplas notas criadas, poderia aparecer apenas uma vez:

```text
⌘P finds previous notes
```

Isso ensina no contexto certo.

---

# 76. Visual personality

A personalidade deve ser:

* quiet;
* precise;
* confident;
* utilitarian;
* sophisticated;
* slightly technical.

Não deve ser:

* playful;
* gamified;
* futuristic AI;
* corporate;
* cyberpunk.

---

# 77. Motion

Animações devem existir apenas para continuidade espacial.

Exemplo:

Scratch → Search:

crossfade/slide mínimo.

Scratch → Refine Preview:

subtle content transition.

Nada de bounce.

Nada de particles.

Nada de AI shimmer exagerado.

---

# 78. Sound

Nenhum som por default.

---

# 79. Haptics

Mac não exige.

Não prioritário.

---

# 80. Mouse users

Apesar de keyboard-first, tudo essencial deve poder ser feito com mouse.

Possíveis affordances em hover:

* refine;
* search;
* menu.

Mas esses affordances não precisam ficar permanentemente visíveis.

---

# 81. Toolbar invisível em hover

Uma possibilidade visual interessante:

quando cursor entra na região superior:

```text
[ search ] [ refine ] [ ••• ]
```

aparece discretamente.

Quando usuário digita:

some.

Isso precisa ser prototipado, pois pode adicionar descoberta sem poluição.

Não é requisito técnico inicial.

---

# 82. Preferência atual: nenhuma toolbar

Para a primeira implementação, eu escolheria:

> **sem toolbar.**

Rodapé discreto + Command Palette são suficientes.

Isso mantém a direção clara.

---

# 83. Estado normal final recomendado

```text
┌──────────────────────────────────────────┐
│                                          │
│ revisar queue porque retries podem estar │
│ acontecendo antes do update de status   │
│                                          │
│ ver logs e falar com vitor              │
│                                          │
│                                          │
│                              ⌘J refine   │
└──────────────────────────────────────────┘
```

É praticamente tudo.

---

# 84. Estado Refine final recomendado

```text
┌──────────────────────────────────────────┐
│ refined                                  │
│                                          │
│ Possible issue in the notification queue │
│                                          │
│ - Check whether retries happen before    │
│   the status update.                     │
│ - Inspect the logs.                      │
│ - Align findings with Vitor.             │
│                                          │
│ Esc cancel                    ↵ accept   │
└──────────────────────────────────────────┘
```

---

# 85. Estado Search final recomendado

```text
┌──────────────────────────────────────────┐
│ > queue                                  │
├──────────────────────────────────────────┤
│ queue retry issue                  18m   │
│ notification status                Tue   │
│ queue architecture                 Sat   │
│                                          │
└──────────────────────────────────────────┘
```

---

# 86. Estado Command Palette final recomendado

```text
┌──────────────────────────────────────────┐
│ >                                        │
├──────────────────────────────────────────┤
│ Refine                             ⌘J    │
│ New note                           ⌘N    │
│ Find note                          ⌘P    │
│ Delete                            ⌘⌫    │
│ Preferences                        ⌘,    │
└──────────────────────────────────────────┘
```

Cinco comandos já podem ser suficientes.

---

# 87. Estado Preferences final recomendado

```text
General

Shortcut
[ ⌥ Space ]

[x] Launch at login
[x] Show in menu bar

Appearance
[ System ]


Refine

On-device Apple Intelligence
```

Nada de página avançada inicialmente.

---

# 88. Fluxo completo: quick capture

```text
User in VS Code

⌥Space

Scratchpad appears
cursor active

types:
"ver bug na fila depois"

Esc

Scratchpad disappears
VS Code active again
```

Número de decisões:

zero além de escrever.

---

# 89. Fluxo completo: Refine

```text
User in Slack

⌥Space

types rough meeting notes

⌘J

refining…

preview appears

Enter

content replaced

Esc

back to Slack
```

O usuário nunca escolhe “Meeting Notes”.

Esse é um ponto fundamental.

---

# 90. Fluxo completo: recovery

```text
user remembers:
"onde escrevi aquele negócio da queue?"

⌥Space
⌘P

types:
queue

↓
Enter

note opens
```

Sem navegar por estrutura.

---

# 91. Fluxo completo: accidental Refine

```text
⌘J
preview

user dislikes result

Esc
```

Original intacto.

Nenhum custo emocional.

---

# 92. Fluxo completo: AI unavailable

```text
⌘J

Refine unavailable.
```

A nota continua normal.

Nada bloqueia.

---

# 93. Fluxo completo: selected Refine

Conteúdo:

```text
A primeira parte já está boa.

mas essa parte aqui ta bem confusa e meio repetida,
talvez tenha como organizar melhor

Essa parte também está boa.
```

Usuário seleciona somente segundo parágrafo.

`⌘J`

Somente seleção muda.

Isso torna Refine muito mais poderoso sem adicionar feature nova.

---

# 94. Fluxo: technical preservation

Entrada:

```text
next_retry_at pode estar ficando menor que scheduled_at
ver combineWithPacingSlot e whatsapp_queue tick
```

Refine ideal:

```text
Possível inconsistência entre `next_retry_at` e `scheduled_at`.

- Revisar `combineWithPacingSlot`.
- Verificar o tick de `whatsapp_queue`.
```

Não renomear identifiers.

Não explicar conceitos não solicitados.

---

# 95. Fluxo: tasks

Entrada:

```text
comprar passagem
ver hotel
responder pedro
sexta mandar documento
```

Refine:

```text
- [ ] Comprar passagem
- [ ] Ver hotel
- [ ] Responder Pedro
- [ ] Enviar documento na sexta-feira
```

Nada além.

---

# 96. Fluxo: message draft

Entrada:

```text
oi lucis acho q consegui resolver aquela parte da fila
vou monitorar hoje e se aparecer alguma coisa te aviso
```

Refine pode gerar:

```text
Oi, Lucis. Acho que consegui resolver aquela parte da fila. Vou monitorar hoje e, se aparecer alguma coisa, te aviso.
```

Não:

```text
Prezado Lucis,

Gostaria de informar que implementei com sucesso...
```

Preservação de voz importa.

---

# 97. O Refinement Engine precisa conhecer “do nothing”

Internamente deve existir uma saída equivalente a:

```text
NO_MEANINGFUL_REFINEMENT
```

Não precisamos mostrar isso dessa forma ao usuário.

Mas o modelo precisa poder concluir:

> o texto já está bom.

Isso é melhor do que modificar por obrigação.

---

# 98. Design system mínimo

A V1 não precisa de um design system gigante.

Precisamos de poucos tokens:

```text
background
surface
primaryText
secondaryText
border
selection
danger

spaceXS
spaceS
spaceM
spaceL

radius
shadow

bodyMono
caption
systemLabel
```

Manter pequeno.

---

# 99. Componentes de UI

Também poucos:

```text
ScratchEditor
FooterHint
SearchField
SearchResult
CommandItem
RefinePreview
SettingsRow
TransientMessage
```

Se a lista de componentes crescer rapidamente, é sinal de expansão de escopo.

---

# 100. Não criar componentes para problemas futuros

Sem:

```text
TagChip
FolderTree
AgentMessage
AIModelCard
TaskBoard
TemplatePicker
WorkspaceSwitcher
```

Nem “deixar pronto”.

YAGNI deve ser levado seriamente.

---

# 101. Edge cases prioritários

Antes do beta, testar explicitamente:

* duas ativações rápidas do hotkey;
* hotkey durante Refine;
* Esc durante geração de Refine;
* nota enorme;
* paste de 50 mil caracteres;
* caracteres Unicode;
* emoji;
* RTL text;
* código;
* Mac dormindo/voltando;
* troca de monitor;
* desconexão de monitor;
* mudança de Space;
* app fullscreen;
* encerramento durante autosave;
* atualização do app durante notas abertas;
* modelo local indisponível;
* resultado vazio do modelo;
* resultado igual ao input.

---

# 102. Notas muito grandes

Precisamos impor ou não um limite prático.

Recomendação:

não bloquear escrita inicialmente.

Para Refine, se conteúdo ultrapassar limite do provider:

mostrar:

```text
This note is too long to refine at once.
Select a smaller section.
```

Isso é melhor que chunking automático.

Chunking introduziria comportamento imprevisível.

---

# 103. Refine de seleção como escape para long notes

Isso reforça a utilidade de seleção parcial.

O produto não precisa resolver documentos longos.

---

# 104. Accessibility visual

O hint:

```text
⌘J refine
```

não pode ser a única maneira de descobrir a ação para usuários de VoiceOver.

A ação precisa estar também em menu/Command Palette.

---

# 105. Preferences e accessibility

Todos os toggles precisam usar componentes nativos sempre que possível.

Não reinventar checkboxes.

---

# 106. Native feel

Usar controles nativos quando não prejudicarem direção visual.

O editor pode ser altamente customizado.

Preferences devem parecer macOS.

Menus devem parecer macOS.

Keyboard behavior deve parecer macOS.

---

# 107. Produto invisível

Um princípio de design que deve ser continuamente reforçado:

> **quanto menos o usuário percebe a aplicação enquanto trabalha, melhor.**

Isso significa que o produto não deve competir com o trabalho.

Não enviar notificações.

Não pedir avaliações durante fluxo.

Não mostrar daily stats.

Não lembrar que “você tem 32 notas”.

Não tentar reengagement artificial.

---

# 108. Sem inbox anxiety

History não deve criar “unread”, “unprocessed” ou “needs review”.

Essas mecânicas transformariam informação transitória em dívida.

O objetivo é exatamente o oposto.

---

# 109. Sem contador

Não mostrar:

```text
143 notes
```

Não agrega ao core.

---

# 110. Sem cleanup gamificado

Não incentivar:

```text
You have 32 old scratches. Clean them now.
```

Informação temporária não deve gerar obrigação administrativa.

---

# 111. Filosofia de History

History existe como seguro e recuperação.

Não como destino de trabalho.

Usuário ideal quase nunca “organiza History”.

Ele apenas busca quando precisa.

---

# 112. Filosofia de Refine

Refine não é criatividade irrestrita.

Ele é:

> **editing with judgment.**

A implementação deve favorecer previsibilidade.

---

# 113. Filosofia de IA

A melhor experiência de IA aqui é aquela em que o usuário pensa:

> “ficou melhor.”

não:

> “uau, olha o que a IA fez.”

Essa diferença deve orientar design.

---

# 114. Filosofia visual

A aplicação deve parecer uma ferramenta profissional pequena.

Uma analogia mais adequada é:

> uma boa faca de cozinha.

Poucas funções, muito domínio sobre elas.

Não:

> um canivete com cinquenta ferramentas.

---

# 115. Decisões que eu fecharia agora

Com base no produto amadurecido, eu consideraria estas decisões suficientemente sólidas para seguir:

**1. Uma janela visível por vez.**

**2. Sem tabs.**

**3. Sem folders/tags.**

**4. History via fuzzy search.**

**5. Refine único em vez de menu de AI actions.**

**6. Refine explícito, nunca automático na V1.**

**7. Preview + accept/cancel obrigatório.**

**8. Local-first.**

**9. Foundation Models é o único provider de Refine na V1; o conteúdo permanece on-device.**

**10. Sem fallback cloud, BYOK, API key ou provider externo na V1.**

**11. Sem AI chat.**

**12. Sem toolbar permanente.**

**13. Sem auto-dismiss ao perder foco.**

**14. Esc como principal saída.**

**15. Hotkey como show/hide toggle.**

**16. Sem backend obrigatório.**

---

# 116. Decisões que eu não fecharia ainda

Precisam de protótipo:

**Keep**

Pode ser desnecessário.

**Expiração automática**

Muito cedo.

**Tamanho exato da janela**

Precisa de sensação real.

**Atalho global default**

Precisa evitar conflitos.

**⌘P vs outro shortcut para History**

Testar.

**Markdown rendering**

Ver quanto realmente agrega.

**Dock icon default**

Testar percepção.

**Última nota vs nova nota no global hotkey**

Este é provavelmente o maior comportamento ainda aberto.

---

# 117. Principal protótipo a construir

O primeiro protótipo não precisa de IA real.

Precisa provar sensação.

Deve possuir:

```text
global hotkey
window
editor
autosave
Esc
New
History
fake Refine transition
```

Podemos simular Refine inicialmente com outputs hardcoded.

Objetivo:

> avaliar se a aplicação parece uma extensão natural do workflow.

Só depois conectamos inteligência real.

---

# 118. Segundo protótipo

Adicionar Refinement Engine.

Testar com conjunto controlado de notas.

Não focar ainda em billing, updater ou branding.

---

# 119. Terceiro estágio

Dogfooding real.

Utilizar durante trabalho diário por vários dias.

Registrar manualmente:

* quando abrimos;
* quando preferimos outro app;
* onde houve fricção;
* quando Refine ajudou;
* quando Refine piorou;
* quais desejos surgiram.

Só então beta externo.

---

# 120. Critério de excelência da interface

Se conseguirmos chegar a uma V1 em que um usuário experiente consegue operar praticamente tudo através de:

```text
global hotkey
typing
Esc
⌘J
⌘P
⌘N
```

provavelmente estamos na direção certa.

Se a operação diária começar a exigir:

* menus;
* mouse;
* configuração;
* escolha de modos;
* organização;
* vários estados visuais;

estamos adicionando complexidade demais.

---

# 121. Experiência ideal em uma frase

> **The app appears when the thought appears and disappears when the thought is handled.**

---

# 122. Interface ideal em uma frase

> **Text first, commands second, chrome last.**

---

# 123. Regra final de UX

Toda nova superfície deve justificar por que não pode ser:

* um atalho;
* um estado temporário;
* uma linha de texto;
* uma ação implícita.

Adicionar uma nova tela é uma decisão cara.

Adicionar uma nova escolha recorrente é ainda mais caro.

O objetivo não é simplesmente fazer um aplicativo visualmente minimalista.

É fazer uma experiência na qual quase não exista nada para aprender, administrar ou configurar.

---

# 124. Estado atual da V1

Com esta especificação, o produto pode ser resumido operacionalmente como:

```text
BACKGROUND UTILITY

        global hotkey
              │
              ▼
┌─────────────────────────────┐
│                             │
│         Scratch             │
│                             │
│                     Refine  │
└─────────────────────────────┘
       │      │       │
      Esc    ⌘J      ⌘P
       │      │       │
       ▼      ▼       ▼
     hide   preview  history
              │
          Enter/Esc
```

Essa é a aplicação.

Todo o resto é suporte para tornar essas poucas transições excelentes.
