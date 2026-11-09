# Rasc — auditoria de produto, UX nativa e qualidade

**Data:** 3 de novembro de 2026  
**Revisão:** `e3b77fd` (`main`, árvore limpa antes desta auditoria)  
**Versão auditada:** 0.1.3 (build 9)  
**Ambiente:** macOS 26.5.1 (25F80), Apple M3 Pro, dois monitores (externo 1920×1080 principal; Liquid Retina XDR abaixo). Teclado ativo: Brazilian - Pro.  
**Escopo:** auditoria e plano. Nenhum comportamento de produção foi alterado.

O pedido citava “os feedbacks abaixo” e não colava uma lista separada. A reconciliação em [E] usa os pontos concretos espalhados no próprio pedido: clique fora, nível da janela, `⌘K` para Keep, `⌘W`, listas no Refine, Gatekeeper, Dock e ditado.

---

## A. Executive Summary

O Rasc já executa o ciclo certo. Atalho global abre um painel, o texto entra direto, Esc devolve o mesmo pensamento, Keep marca e esconde, o banco é local, e a Home é uma janela comum. Em uso, a superfície principal é calma: pouco chrome, hierarquia legível, Keep visível quando há texto. Não há motivo para reescrever o app.

A prontidão para divulgação pública é **boa para um beta aberto entre pessoas que aceitam um DMG sem notarização, e ainda não é a de um utilitário que se pode recomendar sem ressalvas**. Três coisas seguram essa barra:

1. **Confiança.** Apagar todo o texto do editor soft-deleta a nota, sem o Undo de Discard. `⌘Z` traz o texto de volta como uma nota nova. Um pensamento Kept perde identidade e estado.
2. **Descoberta do verbo principal.** A Command Palette, aberta com `⌘K`, não lista Keep, Copy, Share nem Discard. O código calcula essa lista depois de sair do editor, e o editor é a única superfície em que esses comandos existem.
3. **Janela.** A decisão de permanecer visível ao clicar em outro app está implementada e é coerente com o produto. O meio escolhido — `NSWindow.Level.screenSaver` (1000) — é mais largo do que “ficar acima de fullscreen”. Com a Home aberta, `⌘W` fecha a Home que está atrás, e o painel continua. `⌘,` não esconde o painel.

Enquanto o painel está visível e ocioso, o processo ficou em torno de **18% de CPU** neste Mac. Depois de esconder, caiu para **0%**. Escondido, o custo é o que o produto promete. Aberto, não.

Não houve perda confirmada no banco de produção. A primeira tentativa de isolar o app abriu o SQLite real; o arquivo não mudou de tamanho nem de data, não surgiu WAL, e o processo foi encerrado. O restante da sessão usou um banco temporário.

**Preservar:** Esc esconde e salva; New não descarta o anterior; Keep não é lixeira; Refine não grava a sugestão sozinho; sem Dock; sem transcrição própria; sem Pin nesta rodada.

**Fazer primeiro:** paleta, apagar-tudo, `⌘W`, Settings por cima do painel, CPU do Orb com a janela aberta.

---

## B. Current Product Reality

O que está em `Rasc/` manda. Vários documentos descrevem um produto anterior.

| Tema | Documento | Código e uso em 0.1.3 |
|---|---|---|
| Versão | `docs/CURRENT-PRODUCT.md` ainda diz 0.1.0 build 6 | Marketing 0.1.3, build 9 |
| Aparência | `docs/PRODUCT-STATE.md` diz que Settings não tem tema | Settings tem System, Rasc Dark e Rasc Light |
| Clique fora | UX Spec §17 e Architecture §13: não fechar | `hidesOnDeactivate = false`. Confirmado: com o Finder na frente, o painel continuou na tela |
| Pin | Spec discute e recomenda não expor na V1 | Não existe. Aberto = flutuante |
| Paleta | Product state e M16: Keep entra quando há conteúdo | A lista é calculada com a superfície já em `.commandPalette`, então Keep/Copy/Share/Discard não entram |
| Atalhos globais | Docs antigos citam `⌥Space` | Padrão atual `⌥\` e `⌘⌥\`, graváveis. `⌥Space` salvo é migrado no launch |
| Atalhos internos | Settings diz “Not customizable” | Confirmado. Só os dois globais têm recorder |
| Sparkle, sync, tags, chat | Fora | Continuam fora |
| Localização | Não está no contrato atual | A interface em `main` é inglesa. Não há catálogo de strings |
| Refine em listas | Pedido desta auditoria | O prompt pede a menor transformação e não menciona bullets |

Search e Command Palette não são janelas. São superfícies dentro do mesmo `NSPanel`. Home, Settings e Onboarding são `NSWindow`.

O painel é `.nonactivatingPanel`, mas `presentPanel()` chama `NSApp.activate(ignoringOtherApps: true)`, `orderFrontRegardless()` e `makeKeyAndOrderFront`. Mostrar o Rasc ativa o app. O painel não pode ser main (`canBecomeMain = false`). Isso explica parte do `⌘W`.

---

## C. Native Window Behavior Matrix

Comportamento efetivo, não o desejado. “Confirmado” significa visto nesta sessão. “Código” significa lido e coberto por teste de política, sem passar pelo AppKit de verdade.

| | Scratchpad | Home | Settings | Onboarding | Search / Palette |
|---|---|---|---|---|---|
| Tipo | `NSPanel`, não closable, não main | `NSWindow` normal, closable, miniaturizable | Cena SwiftUI Settings | `NSWindow` fixa 720×520 | Dentro do painel |
| Nível | `.screenSaver` (1000), confirmado | 0, confirmado | 0, confirmado | 0 | O do painel |
| Spaces | `canJoinAllSpaces`, `fullScreenAuxiliary`, `stationary` | `moveToActiveSpace`, `fullScreenAuxiliary` | O mesmo da Home, aplicado ao virar key | O mesmo da Home | — |
| Ao desativar o app | Permanece. Confirmado com Finder na frente | Permanece | Permanece | Permanece durante o setup | Permanecem com o painel |
| Como abre | `⌥\` (key up), New, Search, paleta, abrir nota | `⌘⌥\`, menu, fim do onboarding | `⌘,`, menu, paleta | Primeiro launch elegível | `⌘K` / `⌘P` |
| Foco ao abrir | Editor, campo de busca ou paleta | A janela vira key; o primeiro card já nasce selecionado | A janela vira key | A janela | O campo da superfície |
| Esc | Paleta, busca, preview e mensagem consomem. No editor, esconde e salva. Confirmado: paleta → editor, texto intacto | Não fecha | Não fecha. No recorder, Esc cancela a gravação (KeyboardShortcuts) | Não mapeado como fechar | Consomem Esc |
| `⌘W` | Não esconde, com o painel sozinho. Confirmado. Não descarta | Fecha (order out, janela reaproveitada). Com as duas abertas, `⌘W` fechou a Home e deixou o painel. Confirmado | Fecha a janela de Settings pelo comportamento padrão do sistema. Não retestado isoladamente | Botão de fechar existe; o coordenador não é avisado (código) | Não fecham a superfície; o evento vai para a janela main |
| Atalho de novo | Esconde, se o painel está visível | Alterna | Traz de novo para a frente | Durante o passo do atalho, o global é consumido pelo tutorial | `⌘K` reabre e zera a query. `⌘P` abre a busca do painel, não a da Home |
| Conteúdo ao fechar | Flush. Falha deixa o painel aberto. Não limpa o pensamento | Nada é descartado | Preferências já gravadas no controle | Progresso no store de onboarding | Busca não troca a nota. Paleta não troca a nota |
| Geometria | `scratchpadWindowFrame`. Primeira vez: centro óptico | `homeWindowFrame`. Primeira vez: centro geométrico | Autosave `com.apple.SwiftUI.Settings` | Recentrada sempre; não persiste | Não mudam o frame do painel |
| Convivência | Nível 1000. Pode cobrir Home e Settings | Abrir a Home esconde o painel, se o flush funcionar | `⌘,` nesta sessão **não** escondeu o painel | Esconder o painel no meio do tutorial volta o onboarding | — |
| App anterior | `previousApplication.activate` só se o painel ainda é key no hide | Não restaura | Não restaura | Não restaura | — |

Fullscreen, Stage Manager e um app em tela cheia **não foram reexecutados** nesta sessão. O comentário em `PanelController` diz que `.floating` fica abaixo de Spaces em fullscreen no macOS 26, e que `.screenSaver` foi a alternativa validada antes. Esta auditoria não repetiu esse teste.

---

## D. Full Findings Register

### F-01 — Apagar o editor remove a nota sem o Undo de Discard

- **Área:** persistência / Scratchpad
- **Tipo:** bug confirmado
- **Prioridade:** P1
- **Descrição:** Esvaziar o pensamento não é um Discard. O autosave trata texto vazio como exclusão.
- **Comportamento atual:** `persist` chama `repository.delete` quando o texto fica em branco, zera `noteID` e não registra o Undo “Discard Thought”. No banco isolado, a única nota passou a `deleted_at` preenchido (comprimento 58 preservado na row). `⌘Z` recolocou o texto e o autosave criou uma **segunda** nota (2 rows, 1 ainda deletada, soma dos comprimentos 116). A row original não voltou.
- **Comportamento esperado:** Limpar o editor é edição. A nota, sobretudo se estiver Kept, continua a mesma até New, Keep ou Discard. Se a intenção for mesmo apagar ao esvaziar, o mesmo Undo de Discard tem de existir e restaurar id, datas e Kept.
- **Reprodução:** Abrir um scratch com texto, esperar o autosave, selecionar tudo, apagar, esperar mais de 200 ms, `⌘Z`.
- **Evidência:** `ScratchpadSession.persist` (`Rasc/Features/Scratchpad/ScratchpadSession.swift`, por volta das linhas 975–982). SQL no banco temporário, não no do usuário. Screenshot `after-clear-undo.png`.
- **Impacto:** Alta gravidade, frequência média. Quem usa o editor como rascunho apaga o texto para recomeçar. Depois de reiniciar, a nota some da Home e não há lixeira. Inferência de frequência, não medição.
- **Causa:** Conteúdo vazio foi modelado como “não é uma nota”, e o delete desse caminho não passa por `discardActiveNote`.
- **Solução:** Não soft-deletar no autosave. Persistir vazio só se o produto quiser uma nota vazia, ou manter a row até Discard/New. Se o delete continuar, devolver o receipt para `lastDiscard` e para o `UndoManager`.
- **Alternativa:** Manter o delete, mas só depois de Discard explícito. New já cobre “quero outro pensamento”.
- **Risco de regressão:** Médio. Vários testes assumem que vazio não cria row. A mudança precisa preservar “não poluir a Home com notas em branco”.
- **Esforço:** Médio.
- **Aceite:** Apagar o texto, reiniciar o app isolado e ainda abrir a mesma nota, com `kept_at` intacto se ela era Kept. `⌘Z` não cria outra row. Discard continua com Undo.

### F-02 — A Command Palette não oferece Keep, Copy, Share nem Discard

- **Área:** Command Palette
- **Tipo:** bug confirmado
- **Prioridade:** P1
- **Descrição:** O lugar feito para descobrir comandos omite o verbo de conclusão.
- **Comportamento atual:** Com texto no editor, `⌘K` mostrou só New, Search, Open Home, Refine, Keyboard Shortcuts e Settings. Keep não aparecia no topo.
- **Comportamento esperado:** Com texto e sem um Accept em voo, Keep (ou Unkeep), Copy, Share e Discard aparecem, como o menu e o header já fazem.
- **Reprodução:** Escrever, `⌘K`.
- **Evidência:** Screenshot `command-palette.png`. `openCommandPalette` grava `surface = .commandPalette` e só então chama `refreshPaletteCommands`. `canPerformThoughtCompletion` exige `.editor` ou `.message` (`ScratchpadSession.swift`, ~187–189 e ~523–529). `PaletteCommand.availableCommands` está certo quando alguém passa `canPerformCompletion: true`; o teste não passa pelo session.
- **Impacto:** Toda vez que a paleta é o caminho de descoberta. O header ainda tem Keep, então o verbo não desaparece do produto. A paleta mente por omissão.
- **Causa:** A elegibilidade é função da superfície atual, e a superfície já mudou.
- **Solução:** Calcular a lista com a superfície de origem (editor/mensagem) antes de trocar, ou tratar a paleta como elegível se não houver `acceptanceTask`.
- **Alternativa:** Nenhuma útil. Esconder Keep na paleta não simplifica o produto.
- **Risco:** Baixo.
- **Esforço:** Pequeno.
- **Aceite:** Com texto, a paleta lista Keep primeiro. Durante preview/refining, continua sem Keep. Unkeep aparece no lugar quando a nota é Kept. Teste de session, não só de `availableCommands`.

### F-03 — O painel usa nível de screen saver para permanecer visível

- **Área:** Scratchpad / janelas
- **Tipo:** risco confirmado de implementação; a visibilidade em si é decisão de produto (ver G)
- **Prioridade:** P1 para o nível; a política “não esconder ao clicar fora” não é bug
- **Descrição:** `hidesOnDeactivate = false` cumpre o contrato. `level = .screenSaver` (1000) coloca o painel acima de janelas normais, painéis modais (8), status (25) e menus (101).
- **Comportamento atual:** Com o Finder ativo, o painel continuou on screen, layer 1000, 720×440. Home (layer 0) e o painel coexistiram e os retângulos se sobrepunham (Home em x=460, y=215, 1000×680; painel em x=600, y=388, 720×440, coordenadas Quartz).
- **Comportamento esperado:** Visível sobre o trabalho, inclusive fullscreen se esse requisito continuar. Alertas, senha, menus e a própria Settings não devem ficar por baixo.
- **Reprodução:** Abrir o painel, ativar outro app, inspecionar `kCGWindowLayer`.
- **Evidência:** `PanelController.configurePanel` (~318–329). Medição de layer nesta sessão. Fullscreen **não** retestado.
- **Impacto:** Sempre que o painel está aberto. A obstrução depende de onde a janela está. Não medi quantas vezes um menu ficou por baixo.
- **Causa:** Comentário no código: `.floating` não vence fullscreen no macOS 26. Screen saver foi o nível que venceu.
- **Solução:** Manter “não esconder ao desativar”. Experimentar, fora do app de produção, `.popUpMenu` e `.statusBar` com o mesmo `collectionBehavior`, sobre um app em fullscreen. Adotar o menor nível que ainda vence fullscreen. Enquanto o nível for 1000, `⌘,`, alertas do próprio Rasc e o share sheet precisam baixar o painel ou subir o modal.
- **Alternativa:** Esconder ao desativar e acrescentar Pin. Mais um modo, que a spec V1 já recusou. Não recomendo agora.
- **Risco:** Alto se o nível mudar sem o teste de fullscreen. Baixo se a mudança for só “abaixar enquanto um alerta nosso está aberto”.
- **Esforço:** Médio para achar o nível; pequeno para ceder a vez aos próprios alertas.
- **Aceite:** Checklist manual: fullscreen nativo, menu do app de baixo, diálogo de senha, alerta de quit do Rasc, Settings. O painel continua visível no caso de referência e não cobre esses UI do sistema.

### F-04 — `⌘,` deixa o Scratchpad aberto por cima do mundo

- **Área:** Settings / Scratchpad
- **Tipo:** bug confirmado
- **Prioridade:** P1
- **Descrição:** Abrir Settings pelo atalho não passa pelo hide que o código preparou para a apresentação explícita.
- **Comportamento atual:** `⌘,` abriu “Rasc Settings” (560×450, layer 0) e o painel continuou layer 1000. Nesta sessão caíram em monitores diferentes, então não se cobriram. No mesmo monitor, o painel ganharia.
- **Comportamento esperado:** Settings fica utilizável. O painel esconde, ou desce de nível, até Settings fechar.
- **Reprodução:** Painel visível, `⌘,`.
- **Evidência:** Frames acima. O hide está em `SettingsWindowPresentation.present(using:)`, chamado por menu, paleta e `prepareForSettingsPresentation`. O `⌘,` é um `SettingsLink` em `RascApp.swift` (~59–64), caminho da cena SwiftUI.
- **Impacto:** Cada ida a Settings com o scratch aberto.
- **Causa:** Dois caminhos de abertura; só um esconde o painel.
- **Solução:** Um único caminho. O `SettingsLink` também chama `present()`.
- **Risco:** Baixo.
- **Esforço:** Pequeno.
- **Aceite:** `⌘,`, menu e paleta escondem o painel (ou o colocam abaixo) e o pensamento continua lá ao voltar.

### F-05 — `⌘W` não esconde o Scratchpad e pode fechar a Home que está atrás

- **Área:** janelas / teclado
- **Tipo:** bug confirmado
- **Prioridade:** P1
- **Descrição:** `⌘W` não descarta. Também não fecha a janela que a pessoa está olhando.
- **Comportamento atual:** Com Home e painel abertos, `⌘W` fechou a Home e deixou o painel. Com só o painel, `⌘W` não fez nada. A nota continuou (1 row, 58 caracteres, não deletada). `windowShouldClose` do painel chama `hide()` e devolve `false`, mas o painel não é closable nem main, então o Close do menu não o alcança.
- **Comportamento esperado:** `⌘W` esconde a superfície Rasc que está key, com o mesmo flush do Esc, sem Discard. Se a Home é a key, `⌘W` fecha a Home. Se o painel é a key, `⌘W` esconde o painel, mesmo no meio da paleta ou da busca.
- **Reprodução:** Abrir os dois, `⌘W`. Fechar a Home, focar o painel, `⌘W` de novo.
- **Evidência:** Sessão descrita. `ScratchpadPanel.canBecomeMain` é false. Máscara sem `.closable` (`PanelController` ~37–42 e ~295–300).
- **Impacto:** Alto para quem traz o reflexo de fechar janela. Não há perda de texto.
- **Causa:** Close do AppKit mira a janela main. O painel recusa esse papel.
- **Solução:** Equivalente de teclado `⌘W` no painel que chama `hide()`, sem Discard. Não depender de `performClose` numa janela que não é main.
- **Alternativa:** Deixar `⌘W` sem efeito no painel e ensinar só Esc. Pior: o reflexo já existe e hoje acerta a janela errada.
- **Risco:** Médio. `⌘W` não pode passar a significar Discard em nenhum caminho.
- **Esforço:** Pequeno.
- **Aceite:** Painel sozinho: `⌘W` esconde, texto restaura no próximo atalho. Home sozinha: `⌘W` fecha a Home. As duas: `⌘W` age na que está key. Nota intacta nos três.

### F-06 — CPU alta enquanto o Scratchpad está apenas aberto

- **Área:** performance
- **Tipo:** medição confirmada; a causa é indício forte, não um trace de Instruments
- **Prioridade:** P1
- **Descrição:** O app ocioso com o painel aberto não é barato. Escondido, é.
- **Comportamento atual:** `ps` com o painel visível há cerca de dois minutos: 16,8%, depois 19,5%, depois 18,1% de CPU. RSS ~115–125 MB. Cerca de 1,2 s depois de esconder: 0,0% de CPU, RSS ainda ~125 MB. Não usei `powermetrics`.
- **Comportamento esperado:** Janela aberta sem Refine e sem digitação fica perto do idle de um painel estático. Escondido continua perto de zero.
- **Evidência:** Medição acima, processo isolado. `RascOrbState.isPaused` é sempre false. O Orb usa `TimelineView(.animation)` enquanto a janela está visível e Reduce Motion está desligado. Não há outro loop óbvio na captura ociosa.
- **Impacto:** O tempo inteiro em que o painel fica na tela como referência. Uma sessão, uma máquina. Não extrapolar para bateria sem uma segunda medição.
- **Causa provável:** O Orb anima também no estado de escrita, não só enquanto “shaping”.
- **Solução:** Animar no Refine e, se o produto quiser, num pulso curto ao abrir. No editor ocioso, um frame estático. Não mudar o desenho do Orb.
- **Risco:** Baixo se o estado shaping continuar animado.
- **Esforço:** Pequeno.
- **Aceite:** Painel visível, sem Refine, CPU do processo sustentada bem abaixo dos ~18% desta sessão (repetir `ps`/`top` por 10 s). Escondido, continua ~0. Reduce Motion continua estático.

### F-07 — O menu bar não reabre o pensamento atual

- **Área:** menu bar
- **Tipo:** bug confirmado por código; o menu em si não foi clicado (menu extra fica fora do controle de UI usado aqui)
- **Prioridade:** P1
- **Descrição:** O único item que mostra o painel a partir do ícone é “New Scratch”, e New grava o atual e abre outro.
- **Comportamento atual:** O menu tem Open Home, New Scratch, Search thoughts, Settings, feedback e Quit. Não tem “mostrar o scratch”. O clique no ícone abre o menu, não o painel. O atalho global é o único resume direto.
- **Comportamento esperado:** Um item “Open Scratch” (ou o clique) traz o pensamento ativo. New continua sendo New.
- **Evidência:** `MenuBarController.swift` ~44–88. `startNewScratch` limpa a sessão depois do flush.
- **Impacto:** Toda vez que a pessoa esquece `⌥\` e usa o mouse. O texto não se perde; a impressão é de que se perdeu.
- **Solução:** Item no topo, “Open Scratch”, chamando `show()`/`toggle` sem New. New fica onde está.
- **Alternativa:** Clique esquerdo abre o scratch, clique com menu no ícone. Mais nativo para utility, e esconde Settings atrás de um secundário. Eu faria só o item, sem reinventar o clique.
- **Risco:** Baixo.
- **Esforço:** Pequeno.
- **Aceite:** Com um rascunho pela metade, o menu reabre esse texto. New só troca depois de um comando explícito.

### F-08 — Esconder no fim da primeira captura pula Esc versus Keep

- **Área:** onboarding
- **Tipo:** inconsistência de UX confirmada
- **Prioridade:** P2
- **Descrição:** O caminho natural (escrever e esconder) conclui o tutorial sem distinguir os dois verbos.
- **Comportamento atual:** Welcome e o passo do atalho estão claros. Depois de escrever e usar o atalho de novo, caiu em “You're ready”, com Home e Launch at Login. Não houve tela de Keep versus Esc. O hint de `⌘J` apareceu no rodapé durante a escrita. O código só mostra Keep/Esc depois de dispensar a indisponibilidade do Refine, ou se a pessoa não esconder cedo.
- **Comportamento esperado:** Quem completa a primeira captura sabendo esconder também sabe que Keep é outra coisa, sem precisar do Refine.
- **Evidência:** Fluxo percorrido no app isolado. `OnboardingCoordinator` avança no hide quando já há texto.
- **Impacto:** Uma vez por instalação. É o conceito que o resto do produto assume.
- **Solução:** No overlay da primeira escrita, duas linhas estáveis: Esc esconde, `⇧⌘K` fica com você. Não acrescentar um passo.
- **Risco:** Baixo.
- **Esforço:** Pequeno.
- **Aceite:** Capturar e esconder no primeiro launch mostra as duas ações antes de “You're ready”. Refine indisponível não bloqueia.

### F-09 — O header ganha New, Refine e Keep só depois do primeiro texto

- **Área:** Scratchpad
- **Tipo:** inconsistência visual confirmada
- **Prioridade:** P2
- **Descrição:** O cluster da direita muda de largura no momento em que a nota passa a existir.
- **Comportamento atual:** Vazio: Orb e Home. Com texto: New, Refine, Keep e Home entram juntos e empurram para a esquerda. Keep é o único primário (laranja). A troca é compreensível, e o salto existe.
- **Comportamento esperado:** A posição do Home e do Keep não pula quando o primeiro caractere é persistível. Ações indisponíveis podem ficar invisíveis, com a largura reservada, ou o Home fica ancorado na direita com um vão fixo.
- **Evidência:** Captura do vazio (sessão) e `scratchpad-editor.png`. `showsRefineAction` em `ScratchpadView.swift` ~122–126 e ~151–197.
- **Impacto:** Uma vez por nota nova. Pequeno, repetido.
- **Solução:** Reservar o slot. Não adicionar botões novos.
- **Risco:** Baixo.
- **Esforço:** Pequeno.
- **Aceite:** Screenshot vazio e com uma letra: Home no mesmo x. Keep não empurra o Orb.

### F-10 — Atalhos com vários modificadores viram uma tecla ilegível

- **Área:** atalhos / visual
- **Tipo:** bug visual confirmado
- **Prioridade:** P2
- **Descrição:** `ShortcutKeycapView` quebra o rótulo em espaços. `⌘⌥\` não tem espaços, então vira uma cápsula só.
- **Comportamento atual:** No fim do onboarding, “Open Rasc Home with” mostrou um bloco escuro. Em Settings, o recorder de Toggle Home mostra os glifos amontoados. O rótulo de acessibilidade está certo (`Shortcut ⌥⌘\`). `⌘N` em uma cápsula ainda se lê.
- **Evidência:** `settings.png`, passo final do onboarding, `ShortcutKeycapView.tokens` (~31–36). `KeyboardShortcuts.Shortcut.description` não separa modificadores com espaço.
- **Solução:** Partir a string em glifos de modificador conhecidos e na tecla final, em vez de partir por espaço.
- **Risco:** Baixo.
- **Esforço:** Pequeno.
- **Aceite:** `⌘⌥\` renderiza três cápsulas legíveis no onboarding, na paleta e não regride `⌘N` / `⇧⌘K`.

### F-11 — O hint vazio usa um símbolo que não parece cursor

- **Área:** Scratchpad
- **Tipo:** defeito visual confirmado
- **Prioridade:** P3
- **Descrição:** `Image(systemName: "text.cursor")` em `.caption2` aparece como “A]” ao lado de “Anything unfinished is enough.”
- **Evidência:** Captura do painel vazio nesta sessão. `OnboardingScratchpadOverlay.emptyHint`.
- **Solução:** Trocar por um glifo que ainda se lê a 11 pt, ou só o texto. O VoiceOver já ignora o ícone.
- **Risco:** Baixo. **Esforço:** Pequeno.
- **Aceite:** O rodapé vazio não contém um glifo ambíguo em dark mode a 1x e 2x.

### F-12 — A janela de Settings abre mais curta do que o formulário

- **Área:** Settings
- **Tipo:** problema visual confirmado
- **Prioridade:** P2
- **Descrição:** A primeira vista corta o segundo Restore Default. Refine e a lista “Inside Rasc” ficam abaixo.
- **Comportamento atual:** Janela medida em 560×450. O conteúdo continua; é preciso scroll. O formulário em si está bem composto: Theme, Launch at Login, recorders, texto secundário legível.
- **Evidência:** `settings.png` e o frame 560×450.
- **Solução:** Altura inicial que mostre os dois globais por completo e o início de Inside Rasc, sem passar de uma tela 1080.
- **Risco:** Baixo. **Esforço:** Pequeno.
- **Aceite:** No tamanho padrão, os dois Restore Default e o título da seção seguinte estão visíveis sem scroll.

### F-13 — Home e Scratchpad abertos ao mesmo tempo, com o painel por cima

- **Área:** Home / Scratchpad
- **Tipo:** inconsistência confirmada
- **Prioridade:** P2
- **Descrição:** Abrir a Home esconde o painel. Abrir o painel não esconde a Home.
- **Comportamento atual:** Os dois ficaram on screen e os frames se cruzavam. O painel, nível 1000, cobre o centro da Home.
- **Comportamento esperado:** Ou os dois podem conviver com o painel num nível que não tape a Home, ou mostrar o painel esconde a Home com a mesma regra inversa. Eu manteria os dois vivos e corrigiria o nível (F-03), em vez de acoplar ainda mais o hide.
- **Evidência:** Frames desta sessão. `AppBootstrap.openHome` esconde o painel; `presentPanel` não fecha a Home.
- **Risco:** Médio se um passar a fechar o outro. Baixo se só o nível mudar.
- **Esforço:** Pequeno, junto de F-03.
- **Aceite:** Com os dois abertos, dá para ler um card da Home sem mover o painel, ou o produto documenta que o painel cobre e Esc devolve a Home.

### F-14 — Um erro de gravação oferece Undo do Discard anterior

- **Área:** Scratchpad / erros
- **Tipo:** bug confirmado por código, não reproduzido na UI
- **Prioridade:** P2
- **Descrição:** O banner de falha de save mostra Undo sempre que `lastDiscard != nil`, mesmo que o erro seja de outra nota.
- **Evidência:** `ScratchpadView.swift` ~40–46.
- **Solução:** Retry no erro de save. Undo só no banner “Thought discarded.”
- **Risco:** Baixo. **Esforço:** Pequeno.
- **Aceite:** Teste com `lastDiscard` setado e `saveErrorMessage` setado: o botão é Retry.

### F-15 — Open Home no menu do app não mostra o atalho

- **Área:** menus
- **Tipo:** inconsistência confirmada por código
- **Prioridade:** P3
- **Descrição:** O status item, a paleta e o onboarding mostram o atalho global da Home. O item “Open Home” em `RascApp` não tem `keyboardShortcut`.
- **Evidência:** `RascApp.swift` ~19–22 contra `MenuBarController` `setShortcut(for: .toggleHome)`.
- **Solução:** Não duplicar o atalho global no menu do app se ele só funciona com o app ativo. Mostrar o rótulo atual como texto, ou aceitar que o global não aparece no menu do app. Não registrar `⌘⌥\` duas vezes.
- **Esforço:** Pequeno. **Risco:** Baixo.

### F-16 — A tela do app da frente é calculada com coordenada Quartz sem inverter Y

- **Área:** placement
- **Tipo:** bug confirmado no código; efeito no uso não reproduzido
- **Prioridade:** P2
- **Descrição:** `kCGWindowBounds` usa origem no topo. O código copia X/Y para um `NSRect` e intersecta com `NSScreen.frame`, origem embaixo.
- **Comportamento atual:** Neste arranjo (externo em cima, laptop em y AppKit −982), uma janela no laptop tem Y Quartz > 1080. Interpretada como AppKit, cai fora dos dois frames e o código desce para a posição do mouse. Uma janela no monitor principal ainda intersecta o monitor principal, então o bug se esconde. A primeira abertura do painel caiu no monitor principal, onde o Cursor estava. Settings abriu no laptop; não registrei a posição do cursor, então não chamo isso de falha.
- **Evidência:** `WindowFrameStore.swift` `frontmostOnScreenWindowFrame` ~49–72. Frames de `NSScreen` desta máquina.
- **Solução:** Converter Y: `flippedY = primaryHeight - (quartzY + height)`, usando a altura do arranjo global, e testar com dois monitores empilhados.
- **Risco:** Médio. Placement errado é pior que o fallback atual para o mouse.
- **Esforço:** Pequeno, mais um teste manual nos dois monitores.
- **Aceite:** Fixture com bounds Quartz de uma janela no monitor de baixo escolhe esse monitor, não o do mouse.

### F-17 — “Centro óptico” fica abaixo do centro geométrico

- **Área:** Scratchpad
- **Tipo:** inconsistência confirmada
- **Prioridade:** P3
- **Descrição:** O nome e o teste dizem “above”. A matemática e a janela desta sessão ficam abaixo.
- **Evidência:** Razão 0,45 a partir da base (`RascWindowPlacement.swift`). O teste `opticalCenterSitsAboveGeometricCenter` espera `optical.y < geometric.y`. No monitor 1080 pt, o painel de 440 pt começou em Y Quartz 388; o centro visual fica ~50 pt abaixo do centro da área útil.
- **Solução:** Se a intenção é o centro óptico clássico, usar ~0,55 e corrigir o teste. Se a intenção é “um pouco abaixo”, renomear. Não mover a janela de quem já tem frame salvo.
- **Esforço:** Pequeno. **Risco:** Baixo.

### F-18 — O guia público de instalação não diz para rolar Privacy & Security

- **Área:** instalação / rasc-web
- **Tipo:** parcialmente confirmado
- **Prioridade:** P2
- **Descrição:** No macOS recente, Privacy & Security abre no topo e “Open Anyway” fica na seção Security, abaixo da dobra. O pedido cita esse relato.
- **Comportamento atual:** `docs/PRIVATE-BETA.md` diz “Scroll to the security message”. `docs/INSTALL-UNSIGNED.md` e a landing (`InstallationGuide.tsx`) dizem “Under Security, choose Open Anyway” e “Not listed? Open Rasc again”. Não dizem para rolar. As capturas da landing já mostram a seção certa, o que pode fazer parecer que o botão está no topo. Não abri System Settings nesta sessão para não mexer em autorização, e não reinstalei o DMG.
- **Solução:** Uma frase no guia público e na landing: role até Security; o botão só aparece depois de uma tentativa de abrir. Não sugerir desligar o Gatekeeper. O caminho durável continua sendo Developer ID e notarização.
- **Esforço:** Pequeno. **Risco:** Baixo.

### F-19 — Refine não tem contrato de transformar enumeração corrida em lista

- **Área:** Refine
- **Tipo:** limitação conhecida, consistente com o prompt atual. Não reproduzi uma chamada ao modelo nesta sessão
- **Prioridade:** P2, e fora desta auditoria como mudança
- **Descrição:** O prompt pede a menor transformação, conservação de voz e `noChange` quando a melhoria segura não é clara. Não menciona bullets, quebras de lista nem markdown. Um resultado sem bullets não é, por si, uma falha da integração.
- **Integração que o código sustenta:** pedido isolado, preview antes de gravar, Esc / Keep original não aceitam, Accept faz compare-and-swap em `beforeContent`, resultado atrasado é descartado se revisão, nota ou texto mudaram. New durante o Refine cancela a sugestão. Isso está coberto por testes de session. Não exercitei o modelo on-device aqui.
- **Não fazer agora:** alterar prompt, provider ou validador.
- **Quando for a hora:** um caso de eval com enumeração corrida, decidindo se bullet é transformação permitida ou invenção de estrutura. Sem isso, “não vira lista” é o comportamento conservador que o texto pede.

### F-20 — O `persist` do Refine pode reapontar a nota ativa

- **Área:** Refine / persistência
- **Tipo:** risco técnico confirmado por inspeção, sem teste que falhe
- **Prioridade:** P2
- **Descrição:** `performRefinement` chama `persist` e essa função, no caminho de create, atribui `self.noteID` e `activeNoteStore.noteID` depois do `await`. `cancelRefinement` não espera essa tarefa. New e hide também não.
- **Comportamento atual:** Se New limpa a sessão durante esse `await`, a continuação pode gravar o id antigo de volta. O `isCurrent` seguinte impede a sugestão de aparecer, mas o id já foi escrito. Não montei esse interleaving na UI.
- **Solução:** `persist` só publica `noteID` se a sessão ainda for a mesma geração que começou a escrita. Guardar um token de sessão e ignorar a continuação obsoleta.
- **Risco:** Médio. **Esforço:** Médio.
- **Aceite:** Teste que inicia Refine, dá New antes do create retornar, e afirma `activeNoteID == nil` e que o editor vazio não reabre a nota anterior.

### F-21 — Atalhos internos não são personalizáveis

- **Área:** teclado
- **Tipo:** oportunidade, alinhada a um pedido real. Não é bug
- **Prioridade:** P2
- **Descrição:** Só Toggle Scratchpad e Toggle Home são graváveis. Keep é `⇧⌘K`, a paleta é `⌘K`. Quem quer `⌘K` para Keep não tem para onde ir, e a paleta nem mostra Keep (F-02).
- **O que não fazer:** tornar todo atalho editável, inclusive Esc, `⌘,`, `⌘Q` e o futuro `⌘W`.
- **Recomendação:** um conjunto fechado — New, Search, Refine, Command Palette, Keep — com uma fonte só, lida pelo menu, pelo header, pela paleta e por Settings. Conflito com o outro comando do conjunto e com os dois globais bloqueia a gravação. O padrão continua `⌘K` paleta e `⇧⌘K` Keep. Quem quiser inverter, reatribui os dois. Detalhe em G.
- **Esforço:** Médio. **Risco:** Médio, porque menu SwiftUI não acompanha `UserDefaults` sozinho.
- **Aceite:** Mudar Keep para `⌘K` atualiza menu, botão, paleta e Settings, obriga outro atalho para a paleta, e sobrevive ao relaunch. Esc não entra na lista.

### F-22 — Home: primeiro card já selecionado, `⌘P` não é a busca da Home

- **Área:** Home
- **Tipo:** comportamento confirmado por código; a Home foi vista com um card e a seleção visual bate
- **Prioridade:** P3
- **Descrição:** `reconcileSelection` seleciona o primeiro resultado antes de qualquer tecla. `⌘P` abre a busca do painel, não o campo da Home. Return no campo da Home só move o foco para a grade. No estado vazio, Return é “New Scratch”.
- **Julgamento:** A seleção inicial ajuda o teclado. Não é um defeito. Dois searches com o mesmo nome são a parte confusa, e já está no desenho (painel = rápida, Home = até 500). Não unificaria nesta rodada.
- **Aceite se alguém mexer:** o rótulo da paleta continua “Search thoughts” e a Home deixa claro que o campo é outro. Sem atalho novo.

### F-23 — Contraste aumentado ignorado no botão vazio da Home

- **Área:** acessibilidade
- **Tipo:** bug de código, aparência não verificada
- **Prioridade:** P3
- **Evidência:** `HomeView` passa `increasedContrast: false` fixo na borda do New Scratch vazio (~853). Outras bordas consultam o ambiente.
- **Solução:** Usar o mesmo flag do ambiente.
- **Esforço:** Pequeno. **Risco:** Baixo.

### F-24 — Fechar o onboarding pelo botão vermelho não avisa o coordenador

- **Área:** onboarding
- **Tipo:** risco por código, não clicado
- **Prioridade:** P3
- **Evidência:** A janela é closable e não tem delegate que chame o coordenador.
- **Solução:** `windowWillClose` marca o fluxo como dispensado ou volta ao passo certo, em vez de deixar `isActive` preso.
- **Esforço:** Pequeno.

---

## E. Previously Reported Feedback

| Feedback no pedido | Veredito |
|---|---|
| O Scratchpad deveria sumir ao clicar em outro app? | **Rejeitado como mudança.** O código e a spec já dizem para ficar. Confirmei que fica, com o Finder na frente. O problema real é o nível 1000 (F-03), não a permanência. |
| Nível alto para cobrir fullscreen | **Parcialmente confirmado.** O nível é 1000 e cobre app normal. Fullscreen não foi retestado aqui. O comentário de implementação segue plausível e o efeito colateral é real. |
| Personalizar atalhos internos; `⌘K` para Keep | **Confirmado como limite atual.** Não é bug. `⌘K` abre a paleta e funcionou. A paleta não lista Keep (F-02), o que torna o pedido mais forte. Recomendação em G: conjunto fechado, padrão intacto. |
| `⌘W` fecha ou esconde, e não descarta | **Confirmado que não descarta. Confirmado que também não esconde o painel.** Pode fechar a Home atrás (F-05). |
| Refine não transforma lista corrida em bullets | **Não reproduzido no modelo nesta sessão.** O prompt não pede essa transformação (F-19). Registrar como lacuna de produto, sem mudar prompt agora. |
| É preciso rolar Privacy & Security para achar Open Anyway | **Parcialmente confirmado.** O guia de beta diz para rolar; o guia público e a landing não dizem. Não reabri o painel do sistema. |
| Preferência Show in Dock | **Rejeitado.** Não existe, e não deveria entrar. Ver G. |
| Voice capture / ditado nativo | **Não verificado.** O editor é `AXTextArea` padrão. Não há hook de fala. Não proponho transcrição própria. |
| Esc na Home e em Settings | **Confirmado que não fecham.** Recomendo manter assim. |
| New não pode descartar o anterior | **Confirmado no código e nos testes de session.** Não vi motivo para mudar. |

---

## F. Newly Discovered Opportunities

Isto não estava formulado como feedback no pedido:

- **F-01** apagar o texto apaga a nota.
- **F-02** a paleta sem os comandos de conclusão.
- **F-04** Settings pelo atalho não guarda o painel.
- **F-05** `⌘W` acerta a janela de trás.
- **F-06** ~18% de CPU com o painel parado.
- **F-07** o menu bar não retoma o scratch.
- **F-08** o tutorial deixa Esc e Keep de fora se a pessoa simplesmente esconde.
- **F-10** cápsula ilegível em `⌘⌥\`.
- **F-11** glifo `text.cursor`.
- **F-12** Settings abre curto.
- **F-14** banner de erro com o Undo errado.
- **F-16** coordenada de tela sem inversão.
- **F-17** centro óptico abaixo do centro, com teste nomeado ao contrário.
- **F-20** corrida do `persist` do Refine com o id ativo.
- **F-23** contraste fixo em `false` num botão da Home.

Não achei, e portanto não listo como defeito: perda de texto no Esc, no `⌘W` ou no hide; Discard ligado a `⌘W`; o painel sumindo sozinho ao ativar outro app; duplicação de nota no New (os testes de session cobrem o caminho sequencial).

---

## G. Proposed UX Decisions

### Clique fora do Scratchpad

**Ficar visível.** O ciclo de captura usa Esc e o atalho para ir embora. O uso como referência — olhar a nota enquanto se trabalha — é o motivo escrito na spec e o comportamento que o código já tem. Esconder ao desativar tornaria o painel imprevisível e empurraria um modo Pin. Pin custa um conceito que a V1 já cortou, mais estado, mais teste de fullscreen e mais uma explicação no onboarding. Não paga o custo enquanto “aberto = visível, Esc = embora” for verdade.

O que muda é o nível (F-03), não a regra.

### Retenção de foco

Mostrar o painel pode ativar o Rasc: a pessoa vai digitar. Clicar em outro app devolve o foco para lá e **deixa o painel na tela**. Não roubar o teclado de volta até o próximo clique no painel ou o próximo atalho. Isso já é o que aconteceu com o Finder na frente.

### Esc na Home

**Não fecha.** A Home é uma janela de documento, não um diálogo. Esc dentro da busca, se um dia for tratado, limpa a query. Fechar é `⌘W`.

### Esc em Settings

**Não fecha.** Esc já pertence ao recorder (cancela a gravação). `⌘W` fecha Settings, como qualquer janela de preferências.

### `⌘W`

**Esconde ou fecha a janela key. Nunca descarta.**

- Painel, inclusive com paleta, busca ou preview: o mesmo que hide (flush, cancela sugestão não aceita, não apaga a nota).
- Home: fecha a janela.
- Settings: fecha a janela.
- Se as duas primeiras estiverem abertas, o alvo é a que está key, não “a main que estiver atrás”.

### New

**Manter.** Salva, abre outro, fica na mesma janela, não marca Kept, não esconde. O bug a corrigir é esvaziar o editor (F-01), não o New.

### Visibilidade entre janelas

Não tornar as janelas iguais.

- Scratchpad: utility flutuante, visível entre apps, sai por Esc, atalho ou `⌘W`.
- Home: janela normal. Perde o foco e continua. Sai por `⌘W` ou pelo botão.
- Settings: janela normal de preferências. `⌘,` traz de volta em vez de duplicar. Não usa Esc para fechar.
- Onboarding: janela modal de primeira vez. Não flutua no nível do painel.
- Search e paleta: não são janelas. Esc desfaz a superfície e o painel fica.

### Personalização de atalhos internos

**Conjunto fechado, depois do conserto da paleta. Não um editor geral.**

Fonte única consumida por menu, botão, paleta e Settings. Editáveis: New, Search thoughts, Refine, Command Palette, Keep. Fixos: Esc (pilha de cancelamento), Return no preview, `⌘,`, `⌘Q`, `⌘W` (hide/fechar). Os dois globais continuam no recorder que já existe.

Conflito entre dois desse conjunto, ou com um global, recusa a gravação. Sem “use anyway” para cima de `⌘Q` ou `⌘W`. O padrão não muda: quem gosta de `⌘K` para Keep reatribui a paleta. Fazer isso antes de F-02 só deixa a pessoa trocar o atalho de uma paleta que não mostra Keep.

`⌘P` nesta sessão abriu Search thoughts com o editor focado. Não vi o diálogo de Imprimir. O conflito com o item Print do sistema continua possível em outro responder; ao implementar a fonte única, substituir de fato `.printItem` se `⌘P` seguir sendo Search.

### Dock

**Não oferecer.** `LSUIElement` está certo para este ciclo. Um interruptor “Show in Dock” muda política de ativação, o que o clique no Dock deveria abrir (painel? Home? nada?), e a expectativa de que fechar a janela encerra o app — hoje `applicationShouldTerminateAfterLastWindowClosed` é false de propósito. É configuração que o produto disse que prefere não ter. Se pessoas não acharem o app, o conserto é o menu bar (F-07) e o atalho, não um ícone no Dock.

### Ditado

**Não construir captura por voz.** O editor é um `AXTextArea`. O ditado do sistema, se funcionar, já é o recurso. Esta sessão não ditou: não marco como funcionando. Checklist manual abaixo. Só voltar a falar em transcrição própria se o ditado do sistema falhar nesse campo e houver relato repetido.

---

## H. Visual Quality Review

O que foi visto no app isolado, dark mode do sistema, sem Increase Contrast, Reduce Motion nem Dynamic Type.

**Onboarding.** Composição segura: marca, uma frase, um botão laranja, muito ar. O passo do atalho é o melhor momento do produto — uma tecla, “Press to change”, Continue, Skip quieto. O passo “Try it” fica vazio demais dentro de 720×520, e isso é aceitável. O fim compete dois laranjas (Enable at Login e Finish). Finish é o preenchido; ainda assim o outro parece primário. Não cliquei Enable at Login.

**Scratchpad.** É a tela certa. Texto a 16 pt, pouco chrome, Keep como única ação preenchida, Orb pequeno. O vão entre o header e a primeira linha é confortável. Nota curta deixa a maior parte da janela vazia; isso é o produto, não um buraco. Problemas reais: o salto do header (F-09), o glifo do hint (F-11), e os atalhos do header em cinza muito baixo — legíveis de perto, fáceis de perder. Não moveria botões. Não acrescentaria barra de formatação.

**Paleta e busca.** A paleta é limpa e o item selecionado tem contraste suficiente. Falha de conteúdo, não de desenho (F-02). A busca mostra a nota, um tempo relativo e Open. O miolo vazio abaixo de um resultado é o mesmo respiro do painel. Bom.

**Home.** Janela normal com semáforo completo, busca, New Scratch laranja, um card com título, excerpt e hora. “Today” é discreto. Com um card, sobra área vazia; a hierarquia ainda se lê. O “…” do card selecionado aparece sem hover, o que ajuda teclado. Não vi regressão de título no hover nesta passagem curta.

**Settings.** Form nativo, bem espaçado, Theme e atalhos compreensíveis. A janela nasce curta (F-12) e o atalho da Home no recorder está apertado (F-10). Não há excesso de preferências. Theme em três opções é pouco e justificado; não é um painel de aparência.

**Claro, contraste aumentado, Reduce Motion, Reduce Transparency, VoiceOver, Full Keyboard Access:** não verificados na tela. O código consulta Reduce Motion, Reduce Transparency e Increase Contrast na maior parte das superfícies. Isso não vale como aceite visual.

---

## I. Validation Report

### Builds e testes

- Debug build: `xcodebuild -scheme Rasc -configuration Debug`, derived data em `/tmp/rasc-audit-derived`. **BUILD SUCCEEDED.**
- `python3 Scripts/test-domain.py`: **297 testes em 21 suites passaram**, mais `AppReliabilityScaleTests`. Esse script não inclui as suites de janela.
- Benchmark sintético do próprio teste, não a UI: 1000 notas, busca ~2,1 ms, troca ~0,6 ms, autosave ~1,2 ms, bootstrap ~6,1 ms.
- **Não rodei** `xcodebuild test`. O host de teste sobe o app e abriria o banco padrão do usuário. As suites de janela (`PanelControllerTests`, `HomeWindowControllerTests`, `SettingsWindowPresentationTests`, `WindowFrameStoreTests`, `AppReliabilityLifecycleTests`) ficaram por executar.

### Uso manual

App copiado para `/tmp`, bundle id `com.rafaeltorres.rasc.audit`, suporte de aplicação redirecionado para `/tmp/rasc-audit-home` por um dylib só dessa cópia. Banco temporário. Notas sintéticas.

Percorrido: onboarding até Finish (sem Launch at Login), escrita, header, `⌘K`, Esc, `⌘P`, `⌘W` com e sem Home, atalho global com outro app na frente, esvaziar o editor, `⌘Z`, `⌘,`.

CPU com `ps`, layers com `CGWindowList`.

### Segurança dos dados reais

| Arquivo | Antes e depois |
|---|---|
| `~/Library/Application Support/Rasc/Rasc.sqlite` | 22 out 2026, 57344 bytes, sem WAL. Igual ao fim |
| container sandbox `Rasc.sqlite` | 22 out 2026, 49152 bytes. Não foi aberto |
| `~/Library/Preferences/com.rafaeltorres.rasc.plist` | 22 out 2026. Igual ao fim |

A primeira execução com `HOME` temporário **ainda abriu o SQLite real** (FileManager ignora `HOME` neste app). O processo foi morto antes de qualquer nota. Mtime e tamanho não mudaram. As execuções seguintes usaram o banco temporário. O app de auditoria foi encerrado no fim.

### Não verificado

- Fullscreen, Spaces, Stage Manager, Mission Control.
- Ditado do sistema no editor.
- VoiceOver, Full Keyboard Access, Increase Contrast, Reduce Motion, Reduce Transparency, tema claro (Settings estava em System / dark).
- Mais de um monitor como repro do bug de coordenada (o arranjo foi medido; o clique de placement não).
- Gatekeeper e a posição real de Open Anyway.
- Refine on-device, Accept, Undo de sugestão, lista corrida.
- Sleep/wake, troca de resolução, sessão longa de horas.
- `⌘W` em Settings sozinho.
- Clique físico no menu bar do Rasc.
- Latência em milissegundos até o primeiro keystroke. O painel apareceu no ciclo seguinte de observação (~0,5 s incluindo AppleScript). Sem instrumentação melhor, isso não é uma medida.

---

## J. Prioritized Execution Plan

PRs pequenos, na ordem. Sem reescrita. Sem prompt de Refine. Sem dependência nova.

### PR 1 — Paleta mostra os comandos de conclusão

- **Objetivo:** F-02.
- **Problema:** Keep e vizinhos somem porque a superfície muda antes da lista.
- **Onde:** `ScratchpadSession.openCommandPalette`, `canPerformThoughtCompletion`, `PaletteCommandTests` / teste de session.
- **Risco:** baixo. **Depende de:** nada.
- **Aceite:** com texto, Keep aparece; durante Accept, não. Unkeep no lugar certo.
- **Testes:** session abre a paleta e a lista contém Keep; preview não contém.

### PR 2 — Esvaziar o editor não apaga a nota

- **Objetivo:** F-01.
- **Problema:** autosave de string vazia soft-deleta sem Undo.
- **Onde:** `ScratchpadSession.persist`, talvez `NoteRepository` se o delete vazio for só desse chamador. Testes de “blank não cria row” precisam de um caso novo: row existente sobrevive ao clear.
- **Risco:** médio. **Depende de:** nada. Não misturar com a paleta.
- **Aceite:** clear, relaunch, a mesma nota volta; Kept permanece; `⌘Z` não cria outra row; nota que nunca teve texto continua sem row.
- **Testes:** persist vazio em nota existente; undo de texto não duplica; Discard segue com receipt.

### PR 3 — `⌘W` esconde o painel e não a janela de trás

- **Objetivo:** F-05.
- **Onde:** equivalente no painel para `hide()`; não usar Discard. Verificar que a Home closable não recebe o evento quando o painel é key.
- **Risco:** médio. **Depende de:** nada.
- **Aceite:** a matriz de G para `⌘W`. Texto intacto.
- **Testes:** o que der em `PanelController` sem UI; o resto, checklist manual.

### PR 4 — Settings e o painel não se empilham no nível errado

- **Objetivo:** F-04, e o caso de alerta do F-03 que for barato.
- **Onde:** `RascApp` SettingsLink e `SettingsWindowPresentation.present`. Um caminho só, que esconde o painel ou o abaixa enquanto Settings estiver key.
- **Risco:** baixo. **Depende de:** PR 3 ajuda, não bloqueia.
- **Aceite:** `⌘,`, menu e paleta deixam Settings utilizável no mesmo monitor. Voltar mostra o mesmo texto.

### PR 5 — Orb parado quando ninguém está refinando

- **Objetivo:** F-06.
- **Onde:** estado do Orb na captura ociosa. Não redesenhar o Orb. Não “otimizar” mais nada.
- **Risco:** baixo. **Depende de:** nada.
- **Aceite:** repetir a medição `ps` por 10 s com o painel aberto e sem Refine; comparar com os ~18% desta sessão. Escondido, ~0. Shaping continua em movimento.

### PR 6 — Open Scratch no menu bar

- **Objetivo:** F-07.
- **Onde:** `MenuBarController`, delegate, um teste de menu se já houver padrão.
- **Risco:** baixo.
- **Aceite:** o item retoma o texto; New continua criando outro.

### PR 7 — Acabamento que não muda comportamento

Um PR ou três, separados se ficarem grandes:

- F-10 keycaps.
- F-12 altura inicial de Settings.
- F-14 Retry versus Undo.
- F-09 reserva de espaço no header, se ainda incomodar depois de olhar os screenshots lado a lado.
- F-11 glifo.
- F-23 flag de contraste.

Não incluir F-16 (coordenada) aqui: é comportamento, e precisa dos dois monitores.

### PR 8 — Placement entre monitores

- **Objetivo:** F-16.
- **Onde:** `WindowFramePlacement.frontmostOnScreenWindowFrame` e um teste com rects falsos, mais uma passada manual no laptop de baixo.
- **Risco:** médio. Fazer isolado.
- **Aceite:** o monitor da janela da frente, não o do mouse, quando os dois discordam.

### PR 9 — Atalhos internos, conjunto fechado

- **Objetivo:** F-21. Só depois dos PRs 1 e 3, para a paleta e o `⌘W` já terem um significado estável.
- **Onde:** um store, menus, botões, paleta, seção em Settings. Sem tornar Esc/`⌘W`/`⌘,`/`⌘Q` editáveis.
- **Risco:** médio.
- **Aceite:** inverter Keep e paleta, relaunch, menus e botões batem, conflito é recusado.

### Fora desta fila

- Pin, Dock, transcrição, notarização (distribuição, não este app), prompt de listas, reescrita de janelas, Sparkle.
- Documentar em `CURRENT-PRODUCT.md` a versão 0.1.3, o tema em Settings, e a frase de scroll no guia público, quando alguém for tocar docs. Não bloquear os PRs de produto.

### O que não mudaria

Esc esconde e preserva. New não descarta. Keep não apaga. Refine pede Accept. Sem nuvem. Sem Dock. Sem Pin. Home é janela normal. Settings não fecha com Esc. O painel continua visível quando outro app está na frente.
