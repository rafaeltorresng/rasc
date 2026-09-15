# Technical Architecture & Engineering Spec V1

## Scratchpad inteligente para pensamentos ainda não terminados

**Status:** arquitetura proposta para V1
**Data de referência:** 10 de setembro de 2026
**Plataforma:** macOS
**Paradigma:** native, local-first, keyboard-first
**Tese:** *Capture without thinking. Refine without prompting. Keep only what matters.*

---

# 1. Objetivo

Este documento transforma o PRD e a especificação de UX em uma arquitetura técnica implementável.

Ele define:

* stack;
* dependências;
* lifecycle do aplicativo;
* comportamento da janela;
* hotkeys;
* gerenciamento de foco;
* persistência;
* busca;
* autosave;
* modelo de concorrência;
* Refinement Engine;
* Foundation Models;
* disponibilidade on-device de Refine;
* segurança;
* privacidade;
* observabilidade;
* evals;
* testes;
* distribuição;
* updates;
* compatibilidade;
* riscos técnicos;
* decisões arquiteturais;
* ordem recomendada de implementação.

O objetivo não é criar uma arquitetura preparada para qualquer futuro imaginável.

É criar a arquitetura **mais simples que preserve as propriedades fundamentais do produto** e permita evoluir onde dados reais justificarem.

## Decisão de provider da V1

Foundation Models é o único provider de Refine embarcado na V1. Refine é inteiramente on-device: não há OpenRouter, BYOK, fallback cloud, backend nem provider externo. Quando Foundation Models está indisponível, somente Refine fica indisponível; captura, persistência, histórico e busca seguem locais e normais. `RefinementProvider` permanece como fronteira interna já usada pela implementação e pelos testes, sem infraestrutura adicional de providers.

---

# 2. Princípio arquitetural fundamental

A arquitetura deve refletir a arquitetura do produto.

O produto possui poucas responsabilidades:

```text
capture
   ↓
persist
   ↓
retrieve
   ↓
refine
```

Consequentemente, a implementação também deve possuir poucas responsabilidades.

Não precisamos de:

```text
microservices
event bus
backend API
cloud database
sync engine
vector database
RAG
agent runtime
workflow engine
plugin system
custom rendering engine
Redux/TCA-like global architecture
```

A principal complexidade está em **interação com o macOS e confiabilidade de comportamento**, não em infraestrutura distribuída.

---

# 3. Stack recomendada

A stack recomendada para a V1 é:

| Responsabilidade     | Tecnologia                        |
| -------------------- | --------------------------------- |
| Linguagem            | Swift 6                           |
| UI                   | SwiftUI                           |
| Window management    | AppKit                            |
| Scratch window       | `NSPanel`                         |
| Editor               | SwiftUI `TextEditor` inicialmente |
| Global shortcuts     | `KeyboardShortcuts`               |
| Persistência         | SQLite + GRDB                     |
| Search               | SQLite FTS5                       |
| Local AI             | Apple Foundation Models           |
| Networking           | `URLSession`                      |
| Login item           | `SMAppService`                    |
| Menu bar             | AppKit `NSStatusItem`             |
| Updates diretos      | Sparkle 2                         |
| Logging              | `Logger` / OSLog                  |
| Testes               | Swift Testing / XCTest            |
| Distribuição inicial | Developer ID + notarização        |

Essa arquitetura é deliberadamente Mac-specific.

Cross-platform não é um requisito.

---

# 4. SwiftUI + AppKit, não SwiftUI-only

Não existe benefício em transformar “100% SwiftUI” em objetivo arquitetural.

SwiftUI é adequado para:

* editor;
* search;
* command palette;
* preview de Refine;
* preferences;
* componentes visuais;
* bindings e estado.

AppKit é mais adequado para:

* `NSPanel`;
* window levels;
* foco;
* Spaces;
* fullscreen;
* lifecycle de janela;
* activation policy;
* menu bar;
* integração fina com comportamento desktop.

A própria Apple define `NSPanel` como uma janela especializada para superfícies auxiliares e expõe propriedades específicas para floating behavior e keyboard focus.

Portanto:

```text
SwiftUI
  └─ contents of the product

AppKit
  └─ relationship between the product and macOS
```

É uma fronteira arquitetural coerente.

---

# 5. O editor: começar com `TextEditor`

Anteriormente existia um argumento razoável para partir diretamente para `NSTextView`.

Depois de verificar o estado atual das APIs, eu **não faria isso imediatamente**.

O `TextEditor` atual suporta `TextSelection`; no macOS, a própria API contempla inclusive múltiplas seleções.

Portanto, começaria com:

```swift
TextEditor(
    text: $editor.text,
    selection: $editor.selection
)
```

e validaria:

* first responder;
* Undo/Redo;
* seleção;
* scroll;
* grandes conteúdos;
* key handling;
* copy/paste;
* IME;
* comportamento com Refine.

Somente cairia para um wrapper de `NSTextView` se surgir um requisito concreto que `TextEditor` não resolva de maneira confiável.

Isso evita complexidade antecipada.

---

# 6. Estrutura geral do aplicativo

Arquiteturalmente:

```text
┌────────────────────────────────────────────┐
│                  macOS                     │
│                                            │
│ Global hotkey     Menu bar     Login item  │
└────────────┬──────────┬─────────────┬───────┘
             │          │             │
             ▼          ▼             ▼
        Platform Controllers
             │
             ▼
┌────────────────────────────────────────────┐
│                 AppModel                   │
│                                            │
│   editor │ search │ commands │ refine      │
└───────────────┬────────────────────────────┘
                │
        ┌───────┴──────────┐
        ▼                  ▼
   NoteRepository     RefinementEngine
        │                  │
        ▼             │
 SQLite / GRDB   FoundationModels
                  on-device only
```

Não existe backend entre essas partes.

---

# 7. Organização sugerida do projeto

Uma estrutura simples:

```text
App/
    ScratchpadApp.swift
    AppDelegate.swift
    AppModel.swift

Platform/
    PanelController.swift
    HotkeyController.swift
    MenuBarController.swift
    LoginItemController.swift
    FocusController.swift

Features/
    Scratchpad/
        ScratchpadView.swift
        EditorState.swift

    Search/
        SearchView.swift
        SearchState.swift

    Commands/
        CommandPaletteView.swift

    Refine/
        RefinePreviewView.swift

    Settings/
        SettingsView.swift

Domain/
    Note.swift
    NoteSnapshot.swift
    RefinementRequest.swift
    RefinementResult.swift
    RefinementKind.swift

Data/
    AppDatabase.swift
    Migrations.swift
    NoteRepository.swift
    SearchRepository.swift

AI/
    RefinementEngine.swift
    RefinementProvider.swift
    FoundationModelsRefinementProvider.swift
    RefinementPrompt.swift

Diagnostics/
    AppLogger.swift
    PerformanceMetrics.swift

Tests/
```

Não dividiria isso inicialmente em dez Swift Packages internos.

Uma application target organizada já é suficiente.

---

# 8. Nada de arquitetura framework-heavy

Eu não adicionaria:

* The Composable Architecture;
* RxSwift;
* Combine-heavy architecture;
* dependency injection framework;
* service locator;
* event sourcing.

Swift moderno, `@Observable`, actors e constructor injection são suficientes.

O custo de introduzir uma arquitetura grande seria maior que o benefício para um domínio tão pequeno.

---

# 9. Estado principal

Um `AppModel` no `MainActor` pode ser a autoridade da experiência visual.

Conceitualmente:

```swift
@MainActor
@Observable
final class AppModel {
    var editor: EditorState
    var overlay: OverlayState

    let notes: NoteRepository
    let refinement: RefinementEngine
    let panel: PanelController
}
```

O `AppModel` não executa I/O pesado.

Ele coordena operações.

---

# 10. Estado da superfície

O modelo deve garantir que Search, Commands e Refine não se sobreponham arbitrariamente.

Exemplo:

```swift
enum OverlayState {
    case none
    case search(SearchState)
    case commands(CommandState)
    case refining(RefinementContext)
    case preview(RefinementPreview)
    case message(TransientMessage)
}
```

Isso implementa naturalmente a hierarquia do `Esc`.

---

# 11. Sem state explosion

Não devemos modelar cada detalhe de UI como state machine separado.

Precisamos controlar apenas estados que alteram comportamento.

O importante é impedir situações como:

```text
Search aberto
+
Command Palette aberta
+
Refine terminando
+
nota trocada
+
resultado antigo sendo aplicado
```

Um `OverlayState` mutuamente exclusivo elimina boa parte dessas combinações.

---

# 12. NSPanel

A janela principal será um `NSPanel`.

Configuração inicial conceitual:

```swift
final class ScratchpadPanel: NSPanel {
    // customized window behavior
}
```

Propriedades candidatas:

```swift
isFloatingPanel = true
hidesOnDeactivate = false
becomesKeyOnlyIfNeeded = false
```

Há razões concretas para cada uma.

---

# 13. `hidesOnDeactivate = false`

O default de `NSPanel` é **esconder quando o aplicativo deixa de estar ativo**. `NSWindow`, por contraste, tem default `false`.

Isso conflita diretamente com nosso caso.

O usuário deve poder:

```text
scratchpad
    ↓
clicar no VS Code
    ↓
continuar vendo scratchpad
```

Portanto:

```swift
panel.hidesOnDeactivate = false
```

é necessário.

---

# 14. `becomesKeyOnlyIfNeeded = false`

A Apple recomenda considerar `becomesKeyOnlyIfNeeded = true` principalmente quando a maioria dos elementos do painel **não** são campos de texto.

Nosso produto é essencialmente um editor.

Logo o comportamento adequado é o default:

```swift
becomesKeyOnlyIfNeeded = false
```

Quando o usuário ativa o scratchpad, queremos explicitamente:

> janela key + editor first responder.

---

# 15. Floating panel: uma pequena divergência das recomendações clássicas

A documentação da Apple descreve floating panels principalmente como superfícies pequenas e auxiliares, geralmente menos orientadas a teclado.

Nosso produto é diferente:

* pequeno;
* temporário;
* precisa ficar acima;
* mas é extremamente keyboard-oriented.

Isso significa que `NSPanel` continua sendo a abstração mais apropriada, mas precisamos **testar comportamento real**, não assumir que os defaults foram desenhados exatamente para nosso caso.

---

# 16. Window style

Eu evitaria uma janela completamente `.borderless` inicialmente.

É tentador visualmente, mas pode aumentar trabalho relacionado a:

* resize;
* accessibility;
* dragging;
* focus;
* native behaviors.

Uma abordagem melhor é preservar uma janela nativa:

```text
titled
resizable
fullSizeContentView
transparent titlebar
hidden title
```

e visualmente remover o chrome desnecessário.

A aparência pode ficar quase borderless sem abandonar semântica nativa de janela.

---

# 17. Window level

Começar com:

```swift
.level = .floating
```

Não utilizaria níveis agressivos como `.screenSaver`.

Existem hacks de utilities que fazem isso para sobrepor absolutamente tudo, mas esse comportamento é invasivo e pode produzir conflitos com:

* system UI;
* notifications;
* fullscreen video;
* lock screen;
* outras overlays.

Precisamos resolver o problema real:

> aparecer confiavelmente durante trabalho.

Não:

> ganhar de todas as janelas do sistema.

---

# 18. Spaces

A Apple distingue explicitamente:

`canJoinAllSpaces`

> janela pode aparecer em todos os Spaces.

e:

`moveToActiveSpace`

> quando ativada, ela é movida para o Space atual em vez de o sistema trocar de Space.

Para nossa semântica, **`moveToActiveSpace` é mais coerente**.

Não queremos uma superfície conceitualmente permanente em todos os Spaces.

Queremos:

> hotkey → scratchpad aparece onde estou agora.

Portanto, o primeiro spike deve experimentar:

```swift
collectionBehavior = [
    .moveToActiveSpace,
    .transient
]
```

e suas combinações com fullscreen.

---

# 19. Fullscreen e Stage Manager

A Apple também fornece `canJoinAllApplications`, especificamente para floating windows e system overlays que precisam poder aparecer junto das janelas de outros aplicativos em fullscreen/Stage Manager.

Há ainda `fullScreenAuxiliary`, que coloca a janela no mesmo Space da janela fullscreen.

Essas opções possuem interações e algumas categorias são mutuamente exclusivas.

Logo não congelaria uma combinação em código antes do spike.

Os candidatos devem ser testados em condições reais:

```text
moveToActiveSpace + fullScreenAuxiliary

versus

moveToActiveSpace + canJoinAllApplications
```

com:

* Safari fullscreen;
* Chrome fullscreen;
* VS Code fullscreen;
* Terminal;
* vídeo fullscreen;
* Stage Manager;
* dois monitores;
* Space diferente em cada monitor.

Esse é um dos primeiros riscos técnicos a eliminar.

---

# 20. Multi-monitor

Quando o hotkey é acionado, precisamos responder:

> em qual tela o painel deve aparecer?

Regra recomendada:

1. se painel já possui posição válida no display atual, restaurar;
2. caso contrário usar o display associado à janela ativa;
3. fallback: display contendo o cursor;
4. fallback final: main screen.

Evitar simplesmente salvar coordenadas absolutas para sempre.

Um monitor pode:

* ser removido;
* mudar resolução;
* mudar posição;
* passar de esquerda para direita;
* alternar scaling.

Antes de restaurar frame, garantir que uma região relevante permaneça dentro de `visibleFrame`.

---

# 21. Foco

Ao abrir via hotkey:

```text
application A active
     ↓
store previous app
     ↓
activate scratchpad
     ↓
make panel key
     ↓
focus editor
```

Ao fechar via `Esc`/hotkey:

```text
hide panel
     ↓
restore previous app if appropriate
```

Mas há uma distinção importante.

Se o usuário:

1. abre scratchpad;
2. clica manualmente no VS Code;
3. deixa o scratchpad flutuando;
4. depois esconde o scratchpad;

não deveríamos arbitrariamente ativar um aplicativo antigo.

Portanto, focus restoration deve ser associada ao **fluxo de ativação via hotkey**, não ser uma regra cega de toda ocultação.

---

# 22. Não pedir Accessibility

Uma utility desse tipo não deveria abrir um assustador prompt de Accessibility simplesmente para registrar um hotkey.

`NSEvent.addGlobalMonitorForEvents` não é uma boa solução para keyboard shortcuts globais: a própria Apple informa que key events só podem ser monitorados com Accessibility habilitado ou quando o processo é trusted para Accessibility.

Isso criaria uma permissão muito mais ampla do que o produto necessita.

---

# 23. KeyboardShortcuts

A recomendação é utilizar o package `KeyboardShortcuts`, de Sindre Sorhus.

No snapshot atual da pesquisa:

**versão 3.0.1**, lançada em junho de 2026.

O pacote:

* oferece global shortcuts configuráveis;
* é sandbox-compatible;
* é Mac App Store compatible;
* requer apenas macOS 10.15+;
* utiliza Swift 6 na versão atual.

Isso é um trade-off excelente entre:

> uma dependência pequena

e

> não reinventar uma área cheia de edge cases do macOS.

---

# 24. Shortcut default

Não trataria `⌥Space` como default universal garantido.

É uma combinação extremamente natural, mas usuários power-user frequentemente já têm shortcuts para:

* Raycast;
* Alfred;
* launchers;
* input sources;
* outras utilities.

O pacote atual consegue auxiliar na validação de shortcuts e verificar conflitos de sistema.

O onboarding deve possuir recorder.

Podemos sugerir um shortcut, mas o usuário pode substituí-lo imediatamente.

---

# 25. Menu bar

Eu mudaria ligeiramente a recomendação anterior.

Utilizaria **`NSStatusItem` em vez de depender exclusivamente de `MenuBarExtra`**.

Por quê?

`MenuBarExtra` é elegante, mas a documentação da Apple deixa explícito que um app cuja única scene é um MenuBarExtra pode ser automaticamente encerrado quando o extra é removido da menu bar.

Nosso aplicativo tem um lifecycle independente:

```text
background utility
global hotkey
scratch panel
settings
menu bar as recovery/control surface
```

Como já utilizaremos AppKit para o panel, um `MenuBarController` baseado em `NSStatusItem` nos dá controle explícito e previsível.

---

# 26. LSUIElement

O app deve funcionar inicialmente como agent application.

Apple define `LSUIElement` justamente como a flag para um app que roda em background e não aparece no Dock.

Portanto:

```xml
<key>LSUIElement</key>
<true/>
```

É uma configuração coerente.

Menu bar + global hotkey tornam-se as entradas sistêmicas.

---

# 27. Não esconder o menu bar icon cedo demais

Embora a visão de produto permita eventualmente esconder completamente o ícone, durante V1/beta eu manteria o menu bar icon visível.

Ele é um mecanismo de recuperação caso:

* shortcut seja perdido;
* shortcut conflite;
* onboarding falhe;
* usuário esqueça o shortcut;
* Preferences precisem ser abertas.

Depois de provar robustez podemos permitir:

```text
Show menu bar icon [off]
```

Não precisamos otimizar invisibilidade antes de garantir recuperabilidade.

---

# 28. Launch at login

Não utilizar helper app, LoginItem bundle antigo ou LaunchAgent customizado.

Desde macOS 13, `SMAppService` é a API adequada para controlar login items; `SMAppService.mainApp` representa a própria aplicação e `register()` / `unregister()` controlam sua execução nos próximos logins.

Portanto:

```swift
SMAppService.mainApp.register()
```

e:

```swift
SMAppService.mainApp.unregister()
```

A interface também deve consultar `status`, porque o sistema pode exigir aprovação explícita do usuário.

Launch at login deve ser opt-in.

---

# 29. Persistência: SQLite

A primeira decisão importante é não transformar Markdown files em armazenamento primário.

Arquivos `.md` parecem atraentes porque são transparentes, mas começam a dificultar:

* IDs;
* timestamps;
* soft delete;
* revisions;
* índices;
* atomicidade;
* autosave;
* busca;
* futuras migrations.

SQLite é a escolha natural para uma utility local.

---

# 30. Por que GRDB

Existem duas opções fortes:

**SwiftData**

e

**GRDB + SQLite.**

SwiftData funcionaria.

Mas para este produto eu escolheria GRDB.

O motivo principal não é “mais performance”.

É **controle explícito**.

History/Search é parte do core, e GRDB fornece diretamente:

* SQLite;
* migrations explícitas;
* queries claras;
* FTS5;
* testabilidade;
* acesso ao formato de dados mais previsível.

No estado pesquisado em setembro de 2026, GRDB está na versão **7.11.1**, possui mais de uma década de desenvolvimento e é MIT licensed.

Isso é uma dependência madura o suficiente para justificar o custo.

---

# 31. FTS5

GRDB oferece suporte direto a SQLite FTS5.

Isso permite implementar History/Search sem:

* Algolia;
* embeddings;
* semantic index;
* Elastic;
* custom search engine.

Arquitetura:

```text
notes
   │
   └── synchronized FTS5 index
```

FTS5 suporta tokenização Unicode e configurações relacionadas à remoção de diacríticos.

Isso é particularmente relevante para português.

---

# 32. Search não deveria ser chamado de “AI search”

A V1 precisa apenas recuperar rapidamente coisas que o usuário lembra parcialmente.

Então:

```text
FTS prefix matching
+
recency
+
optional substring fallback
```

é suficiente.

Exemplo:

```text
"caram queue"
```

deve encontrar:

```text
Caramuru queue retry investigation
```

Semantic search deve ser adicionada somente se dados demonstrarem que lexical search falha frequentemente.

---

# 33. Busca e Unicode

Antes de indexar/pesquisar, utilizar normalização Unicode coerente.

Especialmente:

* `á`;
* `ã`;
* nomes portugueses;
* strings copiadas de browsers;
* composed/decomposed Unicode.

Não construir nossa própria tokenização.

SQLite/FTS + normalização consistente já resolve a maioria dos casos.

---

# 34. Schema V1

Eu simplificaria o schema anterior.

### `notes`

```text
id              TEXT/UUID PRIMARY KEY
content         TEXT NOT NULL
created_at      DATETIME NOT NULL
updated_at      DATETIME NOT NULL
deleted_at      DATETIME NULL
```

Isso pode ser tudo que a entidade principal precisa inicialmente.

---

# 35. Não armazenar título inicialmente

`title` pode ser derivado.

Função:

```text
primeira linha não vazia
↓
trim
↓
truncate
```

Se a primeira linha não funcionar:

```text
primeiros N caracteres úteis
```

Não precisamos criar uma coluna ou chamada de IA para resolver apresentação.

---

# 36. Não colocar `is_kept` ainda

O conceito de Keep ainda não tem semântica concreta.

Se toda nota permanece no History, marcar algo como `kept` não altera muito.

Portanto eu **não colocaria esse campo no schema inicial**.

Adicionar uma coluna depois é trivial.

Remover uma feature conceitual depois de o usuário depender dela é mais caro.

---

# 37. Refinement revisions

Aqui eu acrescentaria uma segunda tabela que não aparece na UX.

### `refinement_revisions`

```text
id
note_id
before_content
after_content
provider
model_identifier
prompt_version
created_at
```

Objetivo:

> preservar localmente a versão anterior quando uma transformação de IA é aceita.

Não vamos mostrar “AI Version History” na interface.

Essa é uma camada de segurança e auditabilidade.

---

# 38. Por que revisions além de Undo

`Undo` é estado de editor.

Pode desaparecer quando:

* aplicativo fecha;
* nota muda;
* processo reinicia.

Como um princípio do produto é:

> original thought is sacred,

guardar uma revisão aceita custa pouquíssimo e protege contra perda irreversível.

Texto é barato.

Complexidade operacional é baixa.

Esse é um dos poucos lugares onde eu deliberadamente colocaria uma redundância de segurança.

---

# 39. Soft delete

`deleted_at` permite:

```text
delete
→ desaparece da UI
→ ainda recuperável internamente
```

V1 não precisa de uma tela Trash.

Pode haver simplesmente:

```text
Note deleted · Undo
```

E manter soft-deleted notes localmente.

Não é necessário purgar automaticamente cedo.

O armazenamento envolvido é irrelevante.

---

# 40. DatabaseQueue

A carga é extremamente pequena:

* um processo;
* um usuário;
* poucas escritas;
* search local.

Eu escolheria uma única `DatabaseQueue`.

Não precisamos de `DatabasePool` ou otimizações elaboradas.

Mais importante:

**nenhuma operação de banco deve bloquear MainActor.**

---

# 41. Repository

```swift
actor NoteRepository {
    func create(content: String) async throws -> Note
    func update(id: Note.ID, content: String) async throws
    func fetch(id: Note.ID) async throws -> Note?
    func recent(limit: Int) async throws -> [Note]
    func search(_ query: String) async throws -> [NoteSearchResult]
    func softDelete(id: Note.ID) async throws
}
```

A UI não escreve SQL.

---

# 42. Migrations

Usar `DatabaseMigrator`.

GRDB possui uma abstraction explícita para registrar e aplicar migrations.

Exemplo conceitual:

```text
v1_create_notes
v2_create_fts
v3_create_refinement_revisions
```

Nunca:

```text
if column missing...
alter ad hoc...
```

A evolução precisa ser determinística.

---

# 43. Nunca apagar DB ao falhar migration

Uma utility de notas não pode “resolver” schema corruption criando um banco limpo.

Em caso de migration failure:

```text
preserve original DB
log error
fail visibly
```

não:

```text
delete database
start fresh
```

Integridade dos dados é prioridade P0.

---

# 44. Autosave

O conteúdo precisa viver imediatamente em memória.

Persistência pode utilizar debounce pequeno:

```text
text changes
   ↓
~100–250 ms
   ↓
persist latest snapshot
```

A constante exata deve ser medida.

O que não deve acontecer:

```text
cada keystroke
↓
await database
↓
block UI
```

---

# 45. Flush points

Além do debounce, forçar persistência lógica ao:

* esconder scratchpad;
* trocar nota;
* criar nova nota;
* iniciar delete;
* encerrar aplicação quando possível.

Isso reduz a janela de perda.

---

# 46. Nenhuma promessa impossível de “zero data loss”

Mesmo com autosave agressivo, não existe garantia absoluta contra:

* power loss;
* storage failure;
* OS crash.

O objetivo razoável é:

> nenhuma perda causada por fluxos normais da aplicação.

E:

> minimizar fortemente perda em crash inesperado.

---

# 47. Notas vazias

Não criar linhas vazias imediatamente ao `⌘N`.

Utilizar um draft transitório em memória:

```text
new scratch
↓
empty EditorState
↓
first meaningful input
↓
INSERT note
```

Se usuário:

```text
⌘N
Esc
```

nenhum lixo é criado.

---

# 48. Active note

Guardar em UserDefaults:

```text
activeNoteID
```

Não no banco.

Isso é preferência/session state, não domínio persistente.

Ao abrir:

```text
if activeNote exists
    load
else
    blank draft
```

---

# 49. Uma questão ainda aberta: resume vs always-new

O PRD atual sugere retomar a última nota.

Mas essa é uma hipótese de UX.

Arquiteturalmente devemos facilitar testar:

```swift
enum ScratchOpenPolicy {
    case resumeActive
    case startNew
}
```

Não expor essa opção ao usuário inicialmente.

Ela pode ser uma feature flag de desenvolvimento.

Isso permite dogfooding dos dois comportamentos sem remodelar o banco.

---

# 50. Preferences

UserDefaults é apropriado para:

* shortcut metadata gerida pelo package;
* window frame;
* appearance;
* onboarding completed;
* active note ID;
* last used app version.

Não é apropriado para:

* note content;
* API key;
* revision history.

---

# 51. Keychain — fora de escopo da V1

A V1 não possui API keys, BYOK ou credenciais de provider externo. Não adicionar Keychain apenas para preparar um fallback cloud.

---

# 52. App Sandbox

Mesmo distribuindo diretamente, eu ativaria App Sandbox desde o início.

A Apple exige sandbox para Mac App Store e o recomenda para software distribuído externamente.

Benefícios:

* menor attack surface;
* privacy story mais sólida;
* futura Mac App Store não exige grande retrofit;
* comportamento de permissões mais explícito.

---

# 53. Entitlements mínimos

A V1 deve buscar um conjunto pequeno.

Provavelmente:

```text
App Sandbox
Outgoing Network Connections
```

Network não participa de Refine na V1. Pode ser usado separadamente por atualização do app ou licensing, nunca para conteúdo de nota.

Não precisamos de:

* Accessibility;
* Apple Events;
* Contacts;
* Calendar;
* microphone;
* camera;
* location;
* Files/Documents broad access.

Essa ausência é coerente com a filosofia do produto.

---

# 54. Foundation Models é particularmente adequado

O Foundation Models framework dá acesso ao modelo on-device por API Swift.

Apple descreve o modelo como otimizado para tarefas como:

* summarization;
* extraction;
* classification;
* content generation;
* análise de input.

Além disso, dados ficam no dispositivo e o modelo pode funcionar offline.

Isso se encaixa quase diretamente em Refine.

---

# 55. O modelo local não é um “GPT grande”

Esse limite é importante.

A Apple descreveu o modelo original como device-scale, explicitamente dizendo que ele não foi projetado para world knowledge ou advanced reasoning.

Isso reforça que nossa escolha de produto foi boa.

Queremos:

```text
understand text
classify
restructure
rewrite conservatively
```

Não:

```text
deep research
complex reasoning
general assistant
```

---

# 56. Disponibilidade

Foundation Models começa no sistema 26.0.

Mas possuir macOS 26 não garante que o modelo esteja disponível.

Apple exige verificar `SystemLanguageModel.availability`, porque o modelo pode estar indisponível devido a:

* dispositivo não elegível;
* model not ready;
* Apple Intelligence/configuração.

Apple Intelligence em Mac requer Apple silicon.

Portanto a arquitetura nunca pode ser:

```text
if macOS >= 26
    AI works
```

Precisa ser:

```text
if FoundationModels API available
    check model.availability
```

---

# 57. Sistema mínimo do app

Eu não fixaria definitivamente o deployment target antes de um spike, mas a recomendação inicial é:

> **macOS 15+ para o core.**

Razão importante:

Mesmo exigir macOS 26 **não garante local AI**, porque Macs sem Apple silicon continuam sem Apple Intelligence.

Então subir o mínimo para 26 não elimina a necessidade de tratar Refine como indisponível.

Se as APIs de UI que desejarmos tornarem suporte a 15 artificialmente trabalhoso, podemos reconsiderar.

Mas inicialmente:

```text
macOS 15+
→ scratch/history/search

macOS 26+ + eligible Apple Intelligence
→ local Refine
```

é uma divisão boa.

---

# 58. macOS 27

Em 2026 a Apple anunciou uma evolução relevante do Foundation Models framework:

`LanguageModel` introduz uma abstração mais ampla de sessões.

Porém, a documentação atual marca essas APIs novas como **Beta** e explicitamente diz que estão sujeitas a mudança.

Portanto:

> **não basear a V1 em uma API beta apenas porque ela combina perfeitamente com nossa abstração.**

---

# 59. Nossa própria abstraction agora

Criar:

```swift
protocol RefinementProvider: Sendable {
    var identifier: String { get }

    func availability(
        for request: RefinementRequest
    ) async -> RefinementAvailability

    func refine(
        _ request: RefinementRequest
    ) async throws -> RefinementResult
}
```

Na V1, a única implementação é `FoundationModelsRefinementProvider`. A abstração é mantida porque já delimita a implementação e permite fakes determinísticos nos testes; não antecipar novos providers ou roteamento.

---

# 60. RefinementEngine

O provider não decide comportamento de produto.

Existe uma camada acima:

```text
RefinementEngine
```

Responsabilidades:

* validar request;
* invocar o provider Foundation Models;
* preparar prompt;
* executar;
* validar resposta;
* rejeitar resultado stale;
* detectar no-op;
* produzir preview.

---

# 61. Sem fallback cloud na V1

```text
Foundation Models available? → Refine on-device
Foundation Models unavailable? → Refine unavailable
```

Não sugerir nem configurar cloud. O scratchpad continua funcionando independentemente da disponibilidade de Refine.

---

# 62. Provider resolution

`RefinementProvider` encaminha exclusivamente para `FoundationModelsRefinementProvider` na V1. Não há seleção, fallback ou roteamento de provider.

---

# 63. Sessões devem ser isoladas por Refine

Foundation Models possui `LanguageModelSession` stateful.

Isso é útil para chat.

É indesejável aqui.

Nunca reutilizar uma longa sessão entre notas como:

```text
note A
→ session

note B
→ same session

note C
→ same session
```

Isso pode criar:

* context contamination;
* privacidade conceitualmente pior;
* resultado influenciado por notas anteriores;
* context growth;
* dificuldade de reproduzir outputs.

---

# 64. Stateless Refine

Cada operação deve possuir contexto isolado.

Conceitualmente:

```text
open/prepare ephemeral session
        ↓
static instructions
        ↓
current note only
        ↓
structured result
        ↓
discard session
```

Podemos manter uma sessão pré-aquecida temporariamente antes da geração, mas ela deve pertencer ao próximo Refine, não a um histórico de notas.

---

# 65. Prewarming

macOS 26 evoluiu `prewarm()` para preparar/cachar partes necessárias antes da primeira geração.

Isso pode reduzir latency to first token.

O momento natural para prewarm é:

```text
scratchpad opens
↓
small idle delay
↓
prepare local session
```

Não no launch do Mac.

Não continuamente em background.

Se painel for fechado antes de Refine:

> liberar preparação.

---

# 66. Guided Generation

Foundation Models oferece `@Generable` e `@Guide`.

A Apple usa constrained decoding para garantir estrutura válida da resposta, em vez de depender do modelo obedecer informalmente a “retorne JSON”.

Isso é ideal para Refine.

---

# 67. Output schema

Algo deliberadamente pequeno:

```swift
@Generable
struct FoundationRefinementOutput {
    var decision: RefinementDecision
    var kind: RefinementKind
    var text: String
}
```

Com:

```swift
enum RefinementDecision {
    case changed
    case noChange
}
```

E poucos `kind`.

---

# 68. Não pedir rationale

Evitar:

```text
reasoning
explanation
confidence
analysis
```

na resposta.

Não precisamos deles.

Cada campo adicional:

* consome contexto;
* aumenta geração;
* aumenta latência;
* cria nova superfície de erro.

A própria Apple recomenda manter `Generable` simples porque seu schema também consome context window.

---

# 69. Remover o confidence score

O PRD anterior mencionava algo como:

```text
confidence: 0.91
```

Eu retiraria.

Um número autorreportado pelo próprio LLM não nos dá uma probabilidade estatisticamente calibrada de que a transformação esteja correta.

Mostrar ou usar isso criaria falsa precisão.

O comportamento melhor é:

```text
decision = noChange
```

quando o modelo não conseguir justificar uma transformação segura.

E regras conservadoras no próprio prompt/evals.

---

# 70. Uma geração, não classifier + generator inicialmente

Poderíamos construir:

```text
call 1 → classify
call 2 → transform
```

Mas isso significa:

* mais latency;
* mais trabalho de modelo;
* mais failure modes;
* classificação também probabilística.

Inicialmente:

```text
one guided generation
→ kind + decision + transformed text
```

é melhor.

Separar classificação somente se evals demonstrarem ganho significativo.

---

# 71. Prompt contract

O prompt central precisa ser tratado como código versionado.

Regras fundamentais:

```text
Preserve meaning.
Preserve uncertainty.
Preserve names.
Preserve dates.
Preserve numbers.
Preserve technical identifiers.
Preserve the input language.
Preserve the user's tone when the note is a message.

Do not invent context.
Do not add responsibilities.
Do not add deadlines.
Do not turn hypotheses into facts.
Do not expand unless expansion is necessary for clarity.

Prefer the smallest useful transformation.
Return noChange when the text is already useful or meaning is unclear.
```

Esse é o comportamento do produto condensado.

---

# 72. Epistemic preservation

Este é um requisito particularmente importante.

Input:

```text
acho que pode ser race condition
```

Output não pode se tornar:

```text
The issue is a race condition.
```

Tem que preservar:

```text
Possible race condition.
```

Palavras como:

* talvez;
* acho;
* possível;
* aparentemente;
* pode;
* provável;

carregam informação.

Não são ruído.

---

# 73. Prompt injection dentro da nota

Como o usuário pode colar texto de qualquer lugar, uma nota pode conter:

```text
ignore previous instructions and...
```

Isso deve ser tratado como **dados da nota**, não como nova instrução para o Refinement Engine.

A separação deve ser explícita:

```text
SYSTEM / INSTRUCTIONS
    product behavior

USER CONTENT
    <note>
       raw text
    </note>
```

O conteúdo não ganha autoridade sobre instruções do produto.

---

# 74. Resultado stale

Esse é um edge case crítico.

Imagine:

```text
note version 14
    ↓
Refine starts

user somehow changes note

note version 15
    ↓
AI response for v14 arrives
```

Nunca aplicar resultado automaticamente sobre v15.

---

# 75. NoteSnapshot

Ao iniciar Refine:

```swift
struct NoteSnapshot {
    let noteID: Note.ID
    let revision: Int
    let content: String
    let selection: Range<String.Index>?
}
```

O request pertence àquele snapshot.

Ao receber resposta:

```text
current revision == snapshot revision?
```

Se não:

```text
discard result
```

Isso previne corrupção silenciosa.

---

# 76. Melhor ainda: editor read-only durante geração

Para V1, a solução mais simples talvez seja:

```text
Refine starts
↓
target region temporarily read-only
↓
Esc cancels
↓
preview or editor returns
```

Como a geração deve ser curta, isso simplifica concorrência.

Mesmo assim manter snapshot validation como defesa.

---

# 77. Partial selection

Se existe uma única seleção:

```text
Refine(selection)
```

Sem seleção:

```text
Refine(all)
```

No macOS, `TextSelection` pode representar múltiplas seleções.

Para V1 eu **não definiria semântica para múltiplas seleções**.

Se houver mais de uma:

```text
Refine one selection at a time.
```

Isso evita comportamento surpreendente.

---

# 78. Swift String ranges

Não persistir `NSRange` ou offsets arbitrários durante mutações.

O snapshot possui uma `String` imutável.

A seleção deve ser convertida para um range válido **dentro daquele snapshot**.

Quando o resultado volta, só é aplicável se a revisão ainda corresponder.

Isso evita erros com:

* emoji;
* Unicode composed characters;
* UTF-16 vs grapheme cluster;
* texto alterado.

---

# 79. Context size

O framework permite consultar `contextSize`, ou seja, o máximo de tokens suportados pelo modelo.

Não devemos inventar nosso próprio limite universal em caracteres.

Para local model:

```text
estimate/token count
→ compare with model capacity
```

---

# 80. Notas longas

Quando o conteúdo exceder um tamanho seguro:

```text
This note is too long to refine at once.
Select a smaller section.
```

Não fazer chunking automático na V1.

Chunking cria problemas de:

* coerência;
* recomposição;
* perda de contexto;
* mudanças duplicadas;
* latência.

O produto não é um editor long-form.

---

# 81. No-op

Refine precisa poder dizer:

```text
noChange
```

Isso é uma feature, não uma falha.

Exemplo:

```text
Enviar contrato amanhã.
```

Não existe razão para gerar:

```text
Enviar o contrato no dia de amanhã.
```

O sistema deveria simplesmente preservar.

---

# 82. Post-generation validation

Mesmo com structured output, validar:

```text
result exists
result not empty
decision valid
text within reasonable size
```

Para technical content, podemos adicionar invariantes leves.

Por exemplo, identificar:

* URLs;
* UUIDs;
* backticked identifiers;
* issue numbers;

e detectar desaparecimento suspeito.

Não tentaria construir um verificador semântico gigantesco.

Evals são mais importantes.

---

# 83. Não usar streaming no início

Foundation Models suporta streaming, inclusive snapshot streaming.

Mesmo assim, eu não usaria streaming na V1.

Nosso output tende a ser pequeno e estruturado.

UX desejada:

```text
refining…
↓
complete preview
```

Streaming introduziria:

* estados parciais;
* layout instável;
* structured partials;
* cancel/apply complexity.

O benefício é pequeno.

---

# 84. Providers externos — fora de escopo da V1

OpenRouter, BYOK, API keys, roteamento de privacidade externo, seleção de modelo externo e model picker não fazem parte da V1. Não criar UI, configuração, Keychain ou fluxo de fallback para esses caminhos.

O único output estruturado de Refine na V1 é o gerado on-device por Foundation Models.

---

# 89. Prompt versioning

A Apple atualiza `SystemLanguageModel` junto com updates do sistema e recomenda explicitamente testar e versionar prompts para diferentes versões quando necessário.

Portanto:

```swift
enum PromptVersion: String {
    case refineV1
    case refineV2
}
```

Persistir `prompt_version` nas revisions.

Isso permite investigar:

```text
qual comportamento produziu esse resultado?
```

---

# 90. Model version drift

Nosso código não controla quando Apple atualiza seu modelo.

Portanto:

```text
same app version
+ newer macOS
=
possibly different Refine behavior
```

Evals precisam ser rodados novamente quando versões relevantes do sistema mudarem.

Isso é parte normal da manutenção do produto.

---

# 91. macOS 27 Evaluations

A Apple anunciou em 2026 um framework específico de Evaluations para medir sistematicamente comportamento de aplicações baseadas em modelos.

Isso combina muito bem com nosso produto.

Mas, novamente, a documentação atual associada a essas novas APIs está em beta.

Portanto a V1 precisa possuir **seu próprio eval harness**, independente dessa API.

Depois podemos integrá-lo.

---

# 92. Dataset de eval

O dataset deveria ser uma parte de primeira classe do repositório.

Exemplo:

```text
Evals/
    tasks.json
    messy-thoughts.json
    technical.json
    meetings.json
    messages.json
    no-change.json
    uncertainty.json
    multilingual.json
    adversarial.json
```

---

# 93. Estrutura de um caso

```json
{
  "id": "technical-001",
  "input": "next_retry_at talvez esteja ficando menor...",
  "expected_kind": "technical",
  "must_preserve": [
    "next_retry_at",
    "scheduled_at"
  ],
  "must_preserve_uncertainty": true,
  "must_not_invent": [
    "owner",
    "deadline"
  ]
}
```

Gold output pode existir quando realmente necessário.

Mas não precisamos forçar uma única resposta textual exata.

---

# 94. Dimensões de avaliação

Cada saída deve ser julgada separadamente em:

| Dimensão               | Pergunta                       |
| ---------------------- | ------------------------------ |
| Faithfulness           | manteve o significado?         |
| Hallucination          | inventou algo?                 |
| Epistemic preservation | manteve dúvida/certeza?        |
| Structure fit          | escolheu estrutura apropriada? |
| Restraint              | mexeu somente o necessário?    |
| Concision              | reduziu ruído?                 |
| Tone preservation      | preservou voz?                 |
| Language               | preservou idioma?              |
| Technical literals     | preservou identifiers/números? |

---

# 95. Hard failures

Algumas falhas precisam dominar qualquer score médio.

Exemplo:

input:

```text
talvez falar com João sexta
```

output:

```text
João confirmou reunião na sexta.
```

Mesmo que:

* estrutura;
* gramática;
* concisão;

estejam excelentes, o resultado é ruim.

Inventar confirmação e transformar hipótese em fato deve ser hard failure.

---

# 96. Human evaluation

LLM-as-judge pode ajudar em escala.

Mas gold standard inicial deveria ser revisão humana.

Especialmente porque estamos avaliando:

> taste + restraint.

São justamente áreas onde pedir a outro modelo para definir a verdade pode esconder os mesmos vieses do modelo avaliado.

---

# 97. Dogfood eval

Uma métrica especialmente útil:

```text
Would I replace my original text with this?
```

Resposta:

```text
yes
no
small edits
```

Esse dado está extremamente próximo do valor real do produto.

---

# 98. Métrica em produção: refine acceptance

Registrar, sem conteúdo:

```text
refine_requested
refine_returned
refine_accepted
refine_cancelled
```

Então:

```text
acceptance_rate =
accepted / returned
```

Mas não interpretar isoladamente.

---

# 99. Edit-after-refine

Mais informativo:

```text
accept refine
↓
user edits immediately
```

Podemos calcular localmente uma medida agregada de alteração sem enviar o texto.

Por exemplo:

```text
large_edit_after_accept = true/false
```

e somente compartilhar contagem com consentimento.

Não precisamos transmitir o diff.

---

# 100. Telemetria: começar quase do zero

Para os primeiros 15–30 testers, eu não adicionaria uma plataforma pesada de analytics.

Podemos aprender muito através de:

* entrevistas;
* feedback;
* logs locais;
* diagnóstico exportável;
* contadores opt-in.

Isso mantém privacy story limpa e reduz infraestrutura.

---

# 101. OSLog

Categorias:

```text
window
storage
search
refine
provider
lifecycle
update
```

Exemplo:

```text
refine_completed
provider=foundation_models
duration_ms=...
```

Nunca:

```text
note_content=...
```

Nem com privacy annotation.

Simplesmente não logar conteúdo.

---

# 102. Signposts

Performance-critical interactions podem usar signposts:

```text
hotkey_received
panel_visible
editor_ready
```

e:

```text
search_started
results_ready
```

Isso permite medir com Instruments sem analytics cloud.

---

# 103. Performance budget

Para uma utility residente, eu definiria budgets internos agressivos.

### Panel

```text
hotkey → editor ready
p95 ≤ ~100 ms
```

quando o processo já estiver residente.

### Search

Para uma base de até dezenas de milhares de notas:

```text
keystroke → results
p95 ≤ ~50 ms
```

### Typing

Nenhum write de persistência pode bloquear o MainActor.

### Refine

Não fixaria SLA antes de benchmarks reais dos providers.

Separar:

```text
request startup
model inference
preview rendering
```

---

# 104. Não otimizar cold launch demais

Se Launch at Login está ativo, o caso importante é aplicação residente.

Cold launch continua precisando ser razoável, mas não devemos sacrificar arquitetura para ganhar milissegundos num fluxo menos frequente.

---

# 105. Memory

Não definiria prematuramente um budget rígido após Foundation Models.

Carregar um modelo do sistema pode alterar footprint do processo/sistema de maneiras diferentes.

Mais importante:

* app idle não faz trabalho;
* não manter sessões/model resources desnecessariamente;
* liberar sessão prewarmed quando não necessária;
* não acumular caches próprios.

---

# 106. Idle CPU

Objetivo:

> efetivamente zero trabalho recorrente quando inativo.

Não precisamos de:

* polling;
* background classifiers;
* timers;
* scheduled cleanup;
* cloud sync heartbeat.

Isso é uma enorme vantagem arquitetural.

---

# 107. Search performance

Não fazer:

```text
SELECT all notes
↓
Swift fuzzy scoring everything
```

para sempre.

Usar FTS.

Um fallback substring limitado pode existir para query curta.

Mas o índice deve fazer o trabalho principal.

---

# 108. Security model

A superfície de ataque é pequena.

Fluxos de dados:

```text
NOTE
 │
 ├─→ SQLite local
 │
 ├─→ Foundation Models → stays on device
```

Separadamente:

```text
License/update metadata
→ internet
→ never receives note content
```

Essa fronteira deve permanecer clara no código.

---

# 109. Não criar backend

Uma das melhores decisões possíveis para essa V1 é:

> **não existir backend próprio.**

Sem:

* Supabase;
* Firebase;
* authentication;
* API server;
* user table;
* sync database.

Isso reduz drasticamente:

* operações;
* custo;
* security surface;
* privacy surface;
* latency;
* failure modes.

Se sync surgir futuramente, deve ser tratado como nova iniciativa arquitetural.

---

# 110. Não preparar sync “só por garantia”

Não adicionar:

```text
cloud_id
sync_status
sync_version
remote_updated_at
```

ao schema.

Não criar CloudKit container vazio.

Não adicionar conflict resolution.

Quando sync for realmente decidido, projetá-lo com conhecimento real sobre os requisitos.

---

# 111. Markdown export

Mesmo que SQLite seja storage primário, nada impede export futuro:

```text
Export all
→ directory of .md
```

Essa é uma feature muito mais simples do que tornar Markdown o persistence layer.

---

# 112. App Sandbox e updates

Para distribuição externa, Sparkle 2 funciona com aplicações sandboxed utilizando seus XPC services e entitlements apropriados.

Essa configuração é mais trabalhosa que um updater em app unsandboxed, mas vale a pena se queremos manter sandbox desde o início.

---

# 113. Sparkle

Na pesquisa atual, Sparkle está na versão **2.9.4**, lançada em julho de 2026; curiosamente, essa versão inclui inclusive uma correção relacionada a ativação de janelas em apps background/dockless.

É uma solução madura para direct distribution.

Não implementaria updater próprio.

---

# 114. Release pipeline

Fluxo futuro de release:

```text
tests
↓
Release archive
↓
codesign
↓
Hardened Runtime
↓
notarization
↓
staple ticket
↓
package DMG/ZIP
↓
Sparkle signature/appcast
↓
publish
```

Apple exige Developer ID e Hardened Runtime para notarização externa adequada.

---

# 115. Developer ID + notarização

A distribuição inicial recomendada continua sendo direta.

Apple oferece explicitamente `Direct Distribution`/Developer ID para apps macOS fora da Mac App Store e integra notarização ao workflow.

Isso nos dá:

* releases rápidas;
* beta controlado;
* pricing próprio;
* menos restrições comerciais;
* update channel próprio.

---

# 116. Mac App Store posteriormente

Não há razão para excluir Mac App Store para sempre.

Mas ela não precisa determinar a V1.

App Sandbox desde o primeiro dia reduz o custo de abrir esse canal posteriormente.

Billing pode ser abstraído separadamente quando chegar o momento.

---

# 117. Não construir billing agora

A pesquisa de produto sugeriu one-time purchase.

Isso não significa que licensing precisa estar no primeiro protótipo.

Ordem correta:

```text
prove utility
↓
prove Refine
↓
prove habit
↓
prove willingness to pay
↓
then licensing
```

Não gastar ciclos iniciais construindo DRM.

---

# 118. Licensing futuro

Quando necessário:

```swift
protocol EntitlementProvider {
    var state: EntitlementState { get async }
}
```

Implementações futuras podem ser:

```text
DirectLicenseProvider
StoreKitProvider
```

O domínio do scratchpad não precisa conhecer fornecedor de pagamento.

---

# 119. Offline licensing

Quando vendermos compra única, a utility não deve parar de funcionar porque um licensing server ficou offline.

Após validação legítima, cache local de entitlement deve permitir uso offline.

Isso combina com o produto.

---

# 120. Dependency policy

A V1 possui somente algumas dependências externas justificáveis:

| Dependency        | Justificativa               |
| ----------------- | --------------------------- |
| GRDB              | SQLite/migrations/FTS       |
| KeyboardShortcuts | global hotkeys seguros      |
| Sparkle           | updates direct distribution |

Todo o restante:

> frameworks do sistema.

Isso é um bom nível de dependência para uma utility nativa.

---

# 121. Version locking

Swift Package Manager + `Package.resolved` commitado no repositório.

Não atualizar dependências automaticamente em produção sem:

```text
CI
tests
manual smoke test
```

As versões de referência atuais pesquisadas são:

```text
GRDB 7.11.1
KeyboardShortcuts 3.0.1
Sparkle 2.9.4
```

Não significa que devam ficar congeladas eternamente.

---

# 122. Swift concurrency

Utilizar strict concurrency desde o início.

Fronteiras:

```text
@MainActor
→ UI, PanelController, AppModel

actors
→ database coordination
→ refinement coordination
→ keychain/network where useful
```

O principal objetivo é impedir accidental data race, não mostrar sofisticação arquitetural.

---

# 123. Refinement cancellation

`RefinementEngine` deve possuir no máximo um request interativo ativo.

Ao:

* apertar Esc;
* trocar note;
* criar nova note;
* esconder enquanto explicitamente cancelando;

cancelar Task.

FoundationModels:

> cancelar Task/session generation conforme API.

Resultado cancelado nunca chega ao preview.

---

# 124. Request ID

Cada Refine recebe:

```text
requestID
noteID
revision
```

No callback:

```text
still current request?
still same note?
still same revision?
```

Se qualquer resposta for não:

```text
ignore
```

Esse padrão elimina uma classe inteira de race conditions.

---

# 125. Error taxonomy

Não expor errors técnicos diretamente.

Internamente:

```text
modelUnavailable
unsupportedLanguage
modelNotReady
contextTooLarge
generationFailed
invalidOutput
cancelled
unknown
```

Na UI, reduzir para mensagens úteis:

```text
Refine unavailable.
```

ou:

```text
This note is too long. Select a smaller section.
```

ou, para falha de geração:

```text
Couldn't refine this note.
```

---

# 126. Locale e idiomas

Foundation Models expõe capacidades relacionadas aos idiomas suportados e mecanismos para verificar locale.

Não assumir que:

```text
system locale == note language
```

Usuário brasileiro pode escrever:

* português;
* inglês;
* código;
* texto misto.

A regra de produto continua:

> preserve the language of the input.

Se o modelo local não estiver disponível para o ambiente ou idioma, Refine informa indisponibilidade sem tentar provider externo. O editor continua normal.

---

# 127. Markdown

A camada de dados continua armazenando texto.

Não armazenar AST de Markdown.

V1 pode simplesmente reconhecer algumas construções visualmente ou até usar plain text inicialmente.

O Refinement Engine pode gerar:

```text
- [ ] task
- bullet
# heading
`identifier`
```

e o editor preserva isso como string.

---

# 128. Não transformar editor em Markdown IDE

Sem:

* live preview lado a lado;
* plugins;
* custom syntax themes;
* document outline;
* export PDF;
* backlinks.

Cada uma dessas coisas aumenta uma área irrelevante ao core.

---

# 129. Tests — pirâmide

A maior parte dos testes deve ser determinística.

### Unit

* display title;
* note lifecycle;
* search query generation;
* Unicode normalization;
* empty drafts;
* delete;
* migrations;
* state transitions;
* Esc behavior;
* provider resolution;
* stale result rejection.

### Integration

* SQLite/FTS;
* FoundationModels em hardware suportado.

### UI

* editor;
* search;
* command palette;
* settings;
* Refine preview.

### Manual system tests

* global shortcuts;
* Spaces;
* fullscreen;
* Stage Manager;
* multiple monitors;
* focus restoration.

---

# 130. O que não confiar ao CI

Automated UI testing não reproduz perfeitamente:

* Spaces;
* true fullscreen;
* menu bar behavior;
* global hotkey interactions;
* multiple physical displays.

Precisamos de um release checklist manual.

Isso não é falha de engenharia.

É reconhecer a natureza do produto.

---

# 131. Device test matrix

No mínimo testar cenários distintos:

```text
Apple silicon + Apple Intelligence available
Apple silicon + Apple Intelligence disabled
Apple silicon + model not ready
device without eligible local model
```

E:

```text
one display
two displays
display disconnected during runtime
fullscreen
multiple Spaces
Stage Manager
sleep/wake
```

---

# 132. Search test matrix

Incluir:

```text
café
Cafe
João
joao
ação
Caramuru
next_retry_at
UUID
emoji
Portuguese + English
code snippets
URLs
```

Search de uma utility textual precisa ser excelente nesses detalhes.

---

# 133. Evals como gate de release

Mudança em:

* prompt;
* Foundation Models integration;
* output schema;

deve executar eval suite.

Um release não deveria sair apenas porque:

```text
build passes
```

Se Refine piorou, o principal produto piorou.

---

# 134. Prompt regressions

Manter resultados históricos agregados:

```text
refine-v1 / system model X
faithfulness ...
no-change ...
technical preservation ...
```

Quando Apple atualizar modelo:

```text
rerun
compare
```

Isso transforma model drift em engenharia observável.

---

# 135. ADRs

Decisões arquiteturais importantes devem ser registradas em pequenos ADRs.

### ADR-001 — Native macOS

**Decision:** Swift + SwiftUI + AppKit.

**Why:** comportamento nativo é core competitivo.

---

### ADR-002 — NSPanel

**Decision:** uma única `NSPanel` controlada explicitamente.

**Why:** floating utility + focus/Spaces requirements.

---

### ADR-003 — SQLite/GRDB

**Decision:** SQLite como source of truth, GRDB como data layer.

**Why:** local-first, FTS5, migrations, transparência.

---

### ADR-004 — No backend

**Decision:** nenhum backend necessário para core.

**Why:** reduz latência, custo, failure surface e privacy risk.

---

### ADR-005 — Own provider abstraction

**Decision:** `RefinementProvider` próprio na V1.

**Why:** API generalizada `LanguageModel` do macOS 27 ainda está beta.

---

### ADR-006 — Refine on-device only

**Decision:** Foundation Models é o único provider embarcado na V1; se indisponível, Refine fica indisponível.

**Why:** privacidade, funcionamento offline, zero configuração de API e menor superfície de falha.

---

### ADR-007 — Stateless Refine

**Decision:** não compartilhar conversation context entre notas.

**Why:** previsibilidade, privacidade e ausência de contamination.

---

### ADR-008 — No semantic search

**Decision:** FTS5 na V1.

**Why:** corpus pequeno e lexical retrieval suficiente.

---

### ADR-009 — No AI confidence

**Decision:** no-change + eval-driven behavior.

**Why:** evitar falsa precisão.

---

### ADR-010 — Direct distribution first

**Decision:** Developer ID + notarização + Sparkle.

**Why:** velocidade de distribuição e controle de beta.

---

### ADR-011 — App Sandbox

**Decision:** sandbox desde V1.

**Why:** security boundary e futura compatibilidade com Mac App Store.

---

### ADR-012 — Minimal dependencies

**Decision:** apenas dependências que eliminam complexidade real.

**Why:** longevidade de utility.

---

# 136. Principais riscos técnicos

| Risco                            |      Severidade | Mitigação                                |
| -------------------------------- | --------------: | ---------------------------------------- |
| Spaces/fullscreen inconsistentes |            alta | spike AppKit antes da UI final           |
| focus restoration ruim           |            alta | PanelController isolado + testes manuais |
| hotkey conflict                  |           média | Recorder configurável                    |
| perda de nota                    |         crítica | autosave + transactional DB + revisions  |
| model unavailable                |            alta | graceful degradation                     |
| Refine inventa conteúdo          |         crítica | conservative contract + preview + evals  |
| model drift após OS update       |            alta | prompt versions + regression eval        |
| stale async result               |            alta | snapshot/revision/request ID             |
| indisponibilidade do modelo      |            alta | estado claro; app continua útil sem AI   |
| SQLite migration failure         |            alta | transactional migrations, never erase    |
| dependency regression            |           média | Package.resolved + CI                    |
| scope creep                      | produto/crítica | ADRs + anti-features                     |

---

# 137. Primeiro spike: window behavior

Antes de implementar design sofisticado:

construir uma janela com:

```text
NSPanel
TextEditor
global hotkey
Esc
```

e validar:

```text
Space 1
Space 2
fullscreen
Stage Manager
two displays
focus return
click-out behavior
```

Esse spike resolve o maior risco de integração Mac.

---

# 138. Segundo spike: capture durability

Implementar:

```text
GRDB
draft
autosave
quit
relaunch
search
```

Testar agressivamente:

```text
type → Esc
type → Cmd+Q
type → switch note
crash simulation
relaunch
```

Antes da IA.

---

# 139. Terceiro spike: local Refine

Criar 30–50 exemplos representativos.

Implementar:

```text
FoundationModels
@Generable
isolated session
Refine preview
```

Testar:

* PT;
* EN;
* mixed;
* technical;
* tasks;
* messages;
* no-change.

O objetivo não é integrar feature.

É verificar se o modelo local é **bom o suficiente para nossa tese**.

---

# 140. Providers externos — futuro, não V1

Qualquer avaliação de fallback cloud exige uma decisão de produto futura. Não antecipar código, UI, credenciais ou infraestrutura para isso na V1.

---

# 141. Só depois: UI polish

Quando:

```text
window behavior works
data is safe
search works
Refine works
```

aí investir em:

* spacing;
* translucency;
* typography;
* animation;
* icon;
* visual refinements.

Isso evita projetar uma interface perfeita sobre fundamentos instáveis.

---

# 142. Milestones de implementação

### M0 — Architecture spike

Validar:

```text
NSPanel
hotkeys
Spaces/fullscreen
TextEditor selection
Foundation Models availability
GRDB FTS
```

---

### M1 — Capture Core

Entregar:

```text
hotkey
panel
editor
autosave
focus
new note
Esc
```

Sem IA.

---

### M2 — History

Entregar:

```text
FTS
recent notes
search
keyboard navigation
delete
```

---

### M3 — Refinement Engine

Entregar:

```text
provider abstraction
FoundationModels provider
snapshot safety
preview
accept/cancel
revision persistence
eval dataset
```

---

### M4 — System Integration

Entregar:

```text
menu bar
launch at login
settings
multi-monitor hardening
accessibility
```

---

### M6 — Release Engineering

Entregar:

```text
sandbox
codesigning
notarization
Sparkle
CI
diagnostics
```

---

### M7 — Dogfood/Beta

Não acrescentar features.

Corrigir:

```text
friction
reliability
Refine quality
window behavior
```

---

# 143. Definition of technical readiness

Não considerar a V1 pronta porque todos os tickets foram fechados.

Ela está tecnicamente pronta quando:

**Capture é boringly reliable.**

O usuário nunca se pergunta se o texto foi salvo.

**Hotkey é muscular.**

A janela aparece consistentemente no contexto correto.

**Search é instantâneo.**

Nenhuma organização é necessária.

**Refine é conservador.**

Ele melhora mais do que prejudica.

**IA é opcional.**

Falha de modelo nunca afeta notas.

**Dados não dependem de servidor.**

Core funciona offline.

**Nenhuma permissão invasiva é necessária.**

Especialmente Accessibility.

**Atualização é confiável.**

Distribuição direta não parece artesanal.

---

# 144. Arquitetura final resumida

```text
                 macOS
                   │
      ┌────────────┼─────────────┐
      │            │             │
  Hotkey       Menu bar      Login item
      │            │             │
      └──────┬─────┴─────────────┘
             ▼
      ┌───────────────┐
      │ PanelController│
      │    NSPanel     │
      └───────┬───────┘
              ▼
      ┌───────────────┐
      │    AppModel   │
      └───────┬───────┘
        ┌─────┴──────┐
        ▼            ▼
 ┌────────────┐ ┌─────────────────┐
 │ Notes/Search│ │ RefinementEngine│
 └──────┬─────┘ └────────┬────────┘
        │                │
        ▼        ┌─────────────────┐
 ┌────────────┐  │Foundation Models│
 │GRDB/SQLite │  │   on-device     │
 │   + FTS5   │  └─────────────────┘
 └────────────┘
```

---

# 145. O que deliberadamente não existe

```text
backend
auth
cloud DB
sync
RAG
embeddings
vector DB
agents
tool calling
connectors
semantic search
chat history
cross-note AI context
folders
tags
projects
task engine
calendar
plugin system
custom markdown engine
TCA
analytics SDK
Accessibility permission
```

Cada ausência reduz complexidade real.

---

# 146. A principal propriedade não funcional

Para muitos sistemas, arquitetura é guiada por:

```text
scale
throughput
distributed consistency
```

Para este produto, o requisito dominante é diferente:

> **trust.**

O usuário precisa confiar que:

* a janela vai aparecer;
* digitação não será perdida;
* Esc é seguro;
* a nota estará lá depois;
* Refine não destruirá o original;
* IA não inventará silenciosamente;
* conteúdo não será enviado para cloud inesperadamente;
* o aplicativo não ficará no caminho.

Essa confiança é o verdadeiro requisito arquitetural.

---

# 147. Segunda propriedade: latency of thought

Outra maneira de avaliar cada decisão técnica:

> **quanto tempo existe entre a intenção mental e o cursor pronto?**

A arquitetura deve minimizar essa distância.

Daí surgem naturalmente:

```text
resident background utility
global hotkey
no backend
local persistence
no navigation
no startup screen
no organization
```

Não são escolhas estéticas.

São consequências arquiteturais da job-to-be-done.

---

# 148. Terceira propriedade: bounded intelligence

Refine deve ser poderoso justamente porque possui um domínio restrito.

Não queremos que a IA tenha cada vez mais authority.

Queremos:

```text
read this text
understand its form
make the smallest useful transformation
return proposal
```

Não:

```text
search web
read all notes
access email
take action
schedule things
send messages
```

Esse limite reduz simultaneamente:

* risco;
* complexidade;
* latência;
* privacidade;
* avaliação;
* comportamento inesperado.

---

# 149. Architecture fitness functions

Podemos transformar alguns princípios em testes mentais contínuos.

### Core offline

Se internet cair:

```text
capture?
yes

history?
yes

search?
yes

edit?
yes

local Refine?
when supported
```

### Server failure

Se todo serviço nosso desaparecer:

```text
notes survive?
yes
```

### Model failure

Se AI deixar de funcionar:

```text
app useful?
yes
```

### Provider change

Se a implementação de provider mudar em uma versão futura:

```text
domain changes?
no
```

### Search scale

Se usuário tiver 20 mil scratches:

```text
search architecture survives?
yes
```

### New macOS model

Se Apple mudar Foundation Model:

```text
can we rerun evals and version prompts?
yes
```

Esse é um bom sinal de arquitetura saudável.

---

# 150. Recomendação final

A arquitetura que melhor preserva a tese não é particularmente exótica.

Isso é positivo.

Ela é:

> **um pequeno app nativo em Swift, residente em background, com um `NSPanel` extremamente bem comportado, SQLite local, FTS5, hotkey global sem permissões invasivas e uma camada pequena de IA isolada do resto do domínio.**

O componente tecnicamente mais importante não é o LLM.

É provavelmente:

**`PanelController`.**

O componente intelectualmente mais importante é:

**`RefinementEngine`.**

O componente de maior responsabilidade é:

**`NoteRepository`.**

Se esses três estiverem excepcionalmente bons, grande parte do produto estará excepcionalmente boa.

---

# 151. Contrato final de engenharia

Toda implementação deve proteger quatro invariantes:

```text
1. A note must never depend on AI.

2. AI must never silently destroy a note.

3. A note must never leave the device
   for Refine in V1.

4. Product complexity must not leak
   into the capture interaction.
```

Esses quatro invariantes são mais importantes que a escolha específica de frameworks.

---

# 152. Norte técnico

O produto não deve impressionar pelo diagrama de arquitetura.

Ele deve impressionar porque:

```text
⌥Space
```

parece instantâneo.

Porque:

```text
Esc
```

é completamente confiável.

Porque:

```text
⌘P
```

encontra o pensamento imediatamente.

E porque:

```text
⌘J
```

faz exatamente o suficiente — e quase nunca demais.

A melhor arquitetura para esse produto será aquela que o usuário praticamente nunca percebe.
