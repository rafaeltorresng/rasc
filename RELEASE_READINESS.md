# Rasc — Release Readiness

Auditoria de 8 de outubro de 2026. Repositórios: `rasc` e `../rasc-web`.
Base local: Rasc `d7cfd69`, Web `87450ed`, mais as alterações não commitadas desta
auditoria. Ambiente: Apple silicon, macOS 26.5.1, Xcode 26.2/SDK 26.2, Swift 6;
Node 24.11.0/npm 11.6.1. Nenhum commit, push, tag, release, alteração de visibilidade
ou deployment foi feito. Evidências locais ficam em `build/readiness/` (ignorado).

## 1. Executive summary

**Verdict: CLOSE TO READY.** O núcleo do produto funciona e passou nos checks
finais. Foram corrigidos um salvamento que podia reportar sucesso sem gravar e
um consumo material de CPU causado pelo Orb com a janela escondida. App e landing
não precisam de novas features para o v0.1.

O que separa este estado de um lançamento público é: aceitação nativa restante,
certificado Developer ID/notarização, teste do pacote final em instalação limpa,
liberação do conteúdo para GitHub público e publicação coordenada do artefato/site.
A falta de certificado é uma pendência de distribuição nesta máquina, não um
problema de compilação do produto. Não existe ainda um binário público aprovado.

Resultado final: **314 testes nativos em 28 suítes**, **281 testes no runner
alternativo**, Debug, Release e análise estática passaram. Web: instalação limpa,
lint, typecheck e builds de produção passaram; `npm audit` sem vulnerabilidades.
A landing existente está online, mas ainda serve a revisão anterior e o beta.3.

## 2. What Rasc is today

Um scratchpad nativo de menu bar para pensamentos que ainda não merecem uma
estrutura de notas: lembretes, rascunhos de mensagens, hipóteses e observações de
trabalho. Público provável: pessoas que usam Mac e querem capturar algo sem
interromper o trabalho nem escolher título/pasta. O diferencial é a pequena
interrupção, com persistência local e uma revisão de texto opcional.

**Core loop:** invocar → escrever → Refine opcional → Keep → voltar ao trabalho.
Esc esconde e continua o mesmo rascunho depois; Keep guarda e começa um novo.

| Área | Implementação constatada |
| --- | --- |
| Captura | `NSPanel` + SwiftUI, atalho global `⌥\`, editor proporcional, autosave com debounce de 200 ms |
| Ciclo da nota | New Scratch, Keep/Unkeep, Copy/Share, Discard lógico e Undo de sessão |
| Home | Grupos Kept/temporais, acesso a todos os Kept, cartões, navegação e busca |
| Search | FTS5 local, prefixos, normalização de diacríticos, snippets; 12 resultados rápidos / 500 em Home, com indicação de limite |
| Refine | Foundation Models local, requisição nova por operação; nota inteira/seleção, Suggested/Original, Accept/Cancel, Undo e revisão transacional |
| Preferências | Tema, atalho de captura, login item via `SMAppService`, idioma do Refine |
| Primeiro uso | Onboarding persistido com opção de pular; não exige conta nem IA |
| Integração nativa | Menu bar, foco, geometria persistida, retorno ao app anterior, Settings, materiais com fallback |

Arquitetura simples: AppDelegate/Bootstrap coordenam a aplicação; controllers
AppKit apresentam janelas; sessões `@MainActor`/`@Observable` mantêm estado de UI;
`NoteRepository` é um actor e GRDB/SQLite é a fonte de verdade. O banco abre fora
do main thread no bootstrap. Providers separam a geração de texto da sessão.
GRDB 7.11.1 e KeyboardShortcuts 3.0.1 estão fixados; ThinkingOrbsKit é vendorizado.
Sparkle não está integrado. Não há cloud provider ou integração com a ilustração
ChatGPT do site.

Limitações reais: sem export/backup embutido, sync, Trash ou histórico de revisões
navegável; Undo não é recuperação após reinício; banco sem criptografia própria;
interface em inglês; primeiro pacote auditado é arm64. Refine depende de macOS 26,
hardware/região elegíveis e modelo habilitado/pronto. A qualidade do modelo varia.
Captura, Home e busca independem dessa disponibilidade.

## 3. Proposed v0.1 scope

### Included

- Captura rápida, autosave confiável, Esc/New Scratch/Keep e recuperação local.
- Home, busca textual, Copy/Share, Unkeep e Discard com Undo durante a sessão.
- Onboarding pequeno, tema/atalho e preferência de login já existentes.
- Refine **opcional**, local e reversível, com comparação antes de aceitar e
  comunicação explícita de indisponibilidade/possíveis erros.
- Apple silicon/macOS 14+; Refine macOS 26+ quando disponível.
- Distribuição direta por DMG assinado/notarizado; código MIT no GitHub; landing
  curta com requisitos e download verificáveis.

### Explicitly postponed

Sparkle/auto-update, Mac App Store, pacote Intel/universal, localização completa,
export/backup dentro do app, Trash/histórico navegável e novos refinamentos de IA.
Não transformar essas ausências em blockers. Folders, tags, sync, chat, agentes,
colaboração e busca semântica continuam fora do produto, não são backlog de v0.1.

### Removed/disabled

- O beta.3 sem notarização foi retirado do CTA principal; seus bytes históricos
  foram preservados. A landing mostra status de preparação até existir release.
- Claims de fonte pública e links de source são suspensos enquanto o repo é privado.
- Não foram removidos fluxos funcionais do app. Eval CLI e experimentos rejeitados
  já estavam desabilitados no caminho Release; isso foi verificado no binário.

## 4. Work completed during this audit

1. **Persistência (P0):** `NoteRepository.update` agora falha ao tentar salvar uma
   nota ausente/descartada, em vez de retornar sucesso. O texto permanece na sessão
   e o erro impede esconder/encerrar como se tivesse salvo. Três testes reproduziram
   a falha antes da correção e passaram depois; conteúdo descartado não é alterado.
2. **Energia (P1):** Orb agora observa visibilidade/oclusão real de `NSWindow` e
   pausa renderização quando invisível. Perfil identificou TimelineView/Canvas
   continuando em segundo plano. Em intervalos locais de 5 s, CPU caiu de **34,98%
   para 0,20% de um núcleo**. Dois testes nativos cobrem hide/show/reopen/detach.
   Os primeiros testes expuseram a necessidade de observar `isVisible` além de
   oclusão; fixtures foram isoladas da sobreposição de outras suítes nativas.
3. **Consistência (P2):** menu bar passa a dizer “Search thoughts”, como os demais
   pontos do produto. Editor ilustrado do site usa texto proporcional de 16px.
4. **Release (P1/P2):** scripts não apagam o diretório de RC/beta anterior nem
   sobrescrevem DMG existente; verificação exige Developer ID, Team ID, runtime,
   sandbox, ausência de network/debug/data/test artifacts, versão/build corretos,
   Gatekeeper e ticket. Cleanup desmonta DMG mesmo em falha. Notarização recusa ZIP
   antes de chamar a Apple; workflow escolhido é DMG. Archive fixa arm64.
5. **Web (P1):** Vite 7.2.4 → 7.3.7 e source-map-js corrigem as duas dependências
   vulneráveis. Instalação limpa reproduz lockfile; auditoria final tem zero findings.
6. **Entrega pública (P1):** estado de release/source fiel aos repos privados,
   CTA de preparação, sem orientação para contornar bloqueio do sistema; metadata
   canonical/OG/Twitter absoluta e compatível com `/rasc-web/`; CI inclui lint/types.
7. **Evidência/Docs (P2):** screenshot nativa com texto sintético e banco separado;
   divulgação da diferença entre captura e ilustrações; README Web refeito, MIT
   para código original do site, `.gitignore` e instruções antigas reconciliados.
   README app, guia de dados/backup e workflow de release atualizados; release notes
   v0.1 criadas como draft, sem afirmar publicação.

## 5. Remaining blockers

São gates de publicação, não uma lista de novas features.

| Problema | Impacto / localização | Solução recomendada | Esforço |
| --- | --- | --- | --- |
| **P0 — falta artefato confiável** | `security find-identity` retornou 0 identidades válidas. Release local é ad-hoc; não serve como certificado de distribuição. `Scripts/release/`, Keychain e build final. | Instalar Developer ID, configurar perfil notarytool, assinar/notarizar/staple/verificar o DMG final. | médio, depende da conta Apple |
| **P0 — aceitação do pacote/nativo incompleta** | Sem teste do binário final via download/Gatekeeper em Mac limpo, upgrade real beta.3, macOS 14/15, atalho físico e matriz de foco/fullscreen. `docs/NATIVE-UI-VALIDATION.md`. | Executar checklist focada no ciclo principal e distribuição, registrar ambiente/resultados; corrigir somente falhas concretas. Se não validar o mínimo anunciado, restringir honestamente a compatibilidade. | médio |
| **P0 — liberação para publicação de source/assets** | Ambos os repos privados; fixtures legadas de Evals não têm autorização humana estabelecida por este scan. Web inclui wallpaper/marks exportados de sistemas/apps com origem documentada, mas sem permissão de redistribuição comprovada aqui. | Maintainer revisar os inputs legados e direitos dos assets; esclarecer/remover/substituir o que não for publicável. Preservar histórico privado se necessário; não reescrever Git automaticamente. | pequeno a médio |
| **P0 — coordenação da publicação** | Sem GitHub Release; fonte beta.4/build 5, download arquivado beta.3/build 4, landing online ainda antiga. `project.pbxproj`, release notes, `../rasc-web/src/content/launch.ts`, Pages. | Congelar 0.1.0/build 6+, publicar fonte/tag/DMG/checksum/notes e depois ativar/deployar a landing com os mesmos fatos/bytes. | pequeno após gates anteriores |

Não foi encontrado blocker de compilação, migration quebrada, transmissão silenciosa
ou substituição stale de Refine remanescente nos checks executados. Isso não é uma
prova de ausência de todos os defeitos.

## 6. Important non-blockers

- **P1 — qualidade semântica do Refine:** uma geração local removeu “maybe” de
  “maybe ask …”. Original permaneceu íntegro, comparação/cancelamento funcionaram.
  Não prometer preservação semântica perfeita. Proposta opcional e revisão humana
  são parte do escopo; não usar os relatórios antigos como score do modelo atual.
- **P2 — backup/retention:** sem export interno, soft delete e originais de Refine
  continuam em SQLite. Está documentado; vault, secure erase e recovery UI ficam fora.
- **P2 — limites de escala:** testes até 1.000 notas passaram; Home ainda carrega
  todas as notas não descartadas. Não há evidência atual para refactor/paginação nova.
- **P2 — manutenção:** sessões e guardas de Refine são extensas; muitos docs/scripts
  são históricos. Índices distinguem o atual. Não reestruturar tudo para lançar.
- **P2 — web:** sem suíte dedicada, Lighthouse, Safari/Firefox ou screen-reader QA
  completo. Checks de teclado/render foram feitos; reduced motion/transparência
  foram lidos no código, não certificados com tecnologia assistiva.
- **P3:** Intel/universal, auto-update, localização e ferramentas extras de recuperação.

Segunda passagem externa: o **usuário** agora vê requisitos e estado honesto, mas
precisa do download confiável; o **desenvolvedor** tem requisitos/comandos/licença e
uma captura real, com documentação atual destacada; o **engenheiro** encontra
persistência transacional, isolamento/concurrency e regressões relevantes, mas deve
ver como limitações explícitas a complexidade de Refine e a matriz manual pendente.

## 7. Technical health

| Área | Avaliação e limite da evidência |
| --- | --- |
| Architecture | Separação clara entre AppKit/SwiftUI, sessão, actor de persistência e provider; sem backend/infra especulativa. Não houve refactor amplo. |
| Data | Cinco migrations ordenadas; criação, schemas antigos, FTS/reindex, Keep e revisões validados por testes. UUID/content/dates/soft delete em notes. Revisão e texto aceito gravados na mesma transação. Sem reset como recovery. |
| Reliability | Autosave/flush e erro de escrita, descarte/Undo, switching, cancelamento/resultados tardios e stale acceptance cobertos. Falha de abertura preserva dados e informa erro; diagnóstico não inclui texto. |
| Tests | Debug clean inicial; suíte final 314/28 e fallback 281/22; Release e `analyze` passaram. Testes AppKit exercitam janelas, mas não provam comportamento físico em todos os desktops. |
| Performance | Em 1.000 notas: bootstrap ~7,6 ms, search ~1,7 ms, switching de sessão ~0,4 ms no baseline local; thresholds passaram. Perfil revelou/correção reduziu CPU oculta a ~0,2%. Não houve profiling de bateria prolongado. |
| Security/privacy | Release sandbox sem rede, Foundation Models default local, sem analytics/client de cloud/keys. Scan de padrões em 665 blobs históricos app + 159 web, sem matches de tokens/chaves conhecidas. Não é detecção universal nem autorização dos inputs. Banco não é criptografado pelo app. |
| Maintainability | Dependencies fixadas, notices embutidos, CI/checks e documentação de release. Material histórico mantido e separado de certificação atual. Nenhum TODO/FIXME/HACK de produção foi tomado como evidência de feature pronta. |

Evidências: `native-verified.log`, `release-orb-final.log`, `domain-complete.log`,
`idle-before/after.json`, `idle-before.sample`, scans JSON e `bundle-final.log`.
Warning de AppIntents sem dependência é inofensivo neste projeto; mensagens do
serviço Apple `linkd.autoShortcut` apareceram no runner sem falhar os testes.
Não foram ocultadas como sucesso de distribuição.

Runtime real: onboarding/skip, Home vazio, captura/edição, autosave em sandbox vazio, geração
local, comparação Original, Cancel, Keep e Search foram exercitados com fixtures.
O painel corrigido reabriu após pausar, com foco no editor; Home vazio abriu com foco em Search.
Quit encerrou normalmente e o SQLite manteve a nota Kept. A retomada via UI do
utilitário sem janelas encontrou limitações de captura do automation tool; restore
entre sessões/repositórios foi verificado por testes, sem certificar o atalho físico.
Os smokes e fixtures descritos usaram bancos separados e texto sintético; nenhuma nota/banco pessoal foi capturado ou copiado. Release ad-hoc com bundle ID temporário não
substitui teste de instalação do binário final com o bundle ID definitivo.

## 8. macOS distribution

| Item | Estado |
| --- | --- |
| Bundle ID | `com.rafaeltorres.rasc`; não alterar para o release real |
| Versioning | Fonte fixada em 0.1.0/build 6; DMG público ainda depende de Developer ID/notarização |
| Compatibility | Mach-O arm64, minOS 14.0, SDK 26.2; FoundationModels é `LC_LOAD_WEAK_DYLIB` e protegido por availability. macOS antigos ainda precisam de teste real. |
| Icon | AppIcon e menu-bar assets existem e compilam; screenshot real atual incluída. Inspeção Finder/DMG final ainda faz parte da aceitação. |
| Sandbox/runtime | Configuração Release correta; builds Xcode ad-hoc podem desabilitar runtime/adicionar debug entitlement. Não confundir setting com assinatura pública efetiva. |
| Signing/notarization | 0 Developer ID identities locais; nenhum ticket novo emitido. Verificador recusa o app ad-hoc como esperado. |
| Packaging | DMG local final gerado, checksum criado; DMG montado/estrutura app+Applications e assinatura estrita conferidas em smoke anterior. Artefato final continua de auditoria, não release aprovado. |
| Auto-update | Ausente e adiado; atualização manual por novo DMG |

**Recomendação:** distribuição direta Developer ID + DMG notarizado + GitHub Release.
Usa a infraestrutura já existente. App Store implicaria outro processo de revisão e
metadata/distribuição, sem benefício necessário para validar este primeiro produto.
ZIP é possível em geral, mas o workflow deste v0.1 escolhe DMG para instalar e staple.
[Developer ID](https://developer.apple.com/developer-id/) e
[workflow de notarização Apple](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
fundamentam esse caminho; não houve submissão à Apple nesta auditoria.

Passos técnicos restantes, após congelar versão e testes:

```sh
# Com Developer ID instalado; substituir pelo Team ID real.
export RASC_DEVELOPMENT_TEAM="YOURTEAMID"
xcrun notarytool store-credentials "RASC_NOTARY" # prompts interativos; sem senha na linha
./Scripts/release/build-distributable.sh
./Scripts/release/notarize.sh build/Rasc.dmg
./Scripts/release/verify-release.sh build/Rasc.dmg
mkdir -p build/releases
# Não substituir um artefato previamente publicado com o mesmo nome.
cp -n build/Rasc.dmg build/releases/Rasc-0.1.0.dmg
(cd build/releases && shasum -a 256 Rasc-0.1.0.dmg > Rasc-0.1.0.dmg.sha256)
```

Conferir que `cp` não reutilizou um arquivo antigo e que checksum corresponde aos
bytes **após** stapling. Registrar revision, versão/build, SHA256, macOS/hardware e
resultados de instalação/upgrade. O roteiro completo está em `docs/RELEASE.md`.
Scripts foram verificados por `bash -n`, recusa de sobrescrita com checksum intacto,
recusa de ZIP e fixtures controladas de assinatura/ticket/sandbox/rede/debug.
Fixtures positivas não são validação real de Developer ID; esse caminho permanece
pendente por falta de certificado. Não contornar Gatekeeper para marcar o teste.

Artefato local final: `build/readiness/Rasc-0.1.0-beta.4-readiness-final.dmg` e sidecar.
**Não publicar esse DMG como 0.1.0 notarizado.** A versão pública precisa de novo build.

## 9. Open-source readiness

App já tem MIT, README, CONTRIBUTING, SECURITY, CODE_OF_CONDUCT, scheme compartilhado,
CI e notices. Web ganhou MIT e README atual. `.gitignore` preserva databases, outputs,
credenciais locais e caches fora do versionamento. Não há bancos/keys pessoais
rastreados no estado inspecionado; o DMG beta.3 do site é um asset histórico intencional.

Scan percorreu blobs de todos os refs locais para private keys, tokens GitHub/OpenAI/
Slack, AWS access IDs e URLs com credenciais; zero matches. Ele não cobre toda forma
de segredo/PII, refs ausentes do clone ou consentimento. Nome/email público do maintainer
em LICENSE/feedback/security são intencionais, não credenciais de autenticação.

Antes de alterar visibility, revisar `Evals/Refine`/fixtures legadas e direitos dos
assets Web indicados na seção 5. Não remover research/history indiscriminadamente nem
reescrever Git sem autorização. Se algum dado real aparecer, manter o repo privado
até remediar e avaliar seu histórico. Fazer source links funcionarem anonimamente.

## 10. Rasc Web readiness

Proposta é coerente: capturar antes de organizar, Refine opcional, Keep/retomar.
Conteúdo não promete folders/account/sync/cloud. Screenshot nova é real e atual;
hero/Home/Search são ilustrações identificadas, sem chamadas de IA ou dados pessoais.
A imagem real está numa disclosure pequena, sem ampliar a landing em uma feature grid.

Production preview foi inspecionado a 390, 768, 1024 e 1440 px: sem overflow horizontal,
imagens carregadas quebradas ou anchors internos ausentes. Tabs respondem a teclado;
Accept e Keep permanecem distintos. Console da preview correta sem warnings/errors.
Root/Pages builds, lint/types e instalação limpa passaram. JS ~247 KB/~78 KB gzip;
CSS ~44 KB/~10 KB gzip. Não há evidência de problema material de bundle/performance;
não foi produzido score Lighthouse. Acessibilidade completa/reduced-motion rendering
não foram certificados. Um primeiro preview tinha base errada e foi corrigido no
ambiente e no comando documentado.

Domínio existente: `https://rafaeltorres.dev/rasc-web/`, HTTP 200. Configuração Pages
publica `dist/`; canonical/social image URLs agora apontam para o target real. Não
há analytics do produto no código. Logs de acesso do host não foram auditados.

Falta: substituir metadata/URLs pelo artefato final, liberar source, rever direitos
dos assets, ativar as flags verdadeiras e deployar. O site online ainda não contém
estas correções locais. Relatório específico: `../rasc-web/docs/RELEASE-AUDIT-2026-10-08.md`.

## 11. Final release checklist

- [x] Escopo v0.1 definido, sem novas features P3.
- [x] Debug clean build e suíte nativa final.
- [x] Release build e análise estática.
- [x] Regressões de dados, migrations, search, Refine e lifecycle.
- [x] Falha silenciosa de persistência corrigida.
- [x] CPU de animação escondida corrigida e medida.
- [x] Smoke do núcleo com dados sintéticos isolados.
- [x] Packaging local e verificações negativas de distribuição.
- [x] README/contribuição/privacidade/licenças de código e release workflow.
- [x] Screenshot real atual; exemplos ilustrados identificados.
- [x] Web clean install, lint, typecheck, produção root/Pages, auditoria de dependencies.
- [x] Render mobile/tablet/desktop e checks de teclado/anchors/imagens.
- [x] Scan de padrões de credenciais no histórico local.
- [ ] Aceitação nativa física: foco/atalhos, macOS mínimo, fullscreen/Spaces e acessibilidade essencial.
- [ ] Clearance de inputs históricos e assets de terceiros para publicação.
- [x] Fixar versão 0.1.0/build 6 e release notes (metadados do binário após staple).
- [ ] Revisar/commitar alterações dos dois repos, por ação autorizada do maintainer.
- [ ] Developer ID e hardened runtime reais no app exportado.
- [ ] Notarization accepted, staple e Gatekeeper no DMG final.
- [ ] Artefato imutável final, checksum pós-staple e registro de source/versão/build.
- [ ] Teste de instalação limpa a partir do download, sem bypass do Gatekeeper.
- [ ] Upgrade do beta.3 retido com DB sintético representativo e verificação de notas/FTS/Kept.
- [ ] GitHub repository público e links anônimos funcionando.
- [ ] Tag e GitHub Release com notes, DMG e checksum corretos.
- [ ] Landing com dados do mesmo release, download válido e flags verificadas.
- [ ] Deploy final de `dist/`, social metadata e download/checksum conferidos no site vivo.
- [ ] Publicação do v0.1.

## 12. Recommended next actions

1. Revisar os diffs desta auditoria e liberar inputs legados/assets para publicação;
   substituir/remover somente o material cuja publicação não puder ser autorizada.
2. Executar a aceitação nativa essencial com teclado físico e macOS anunciado,
   incluindo foco/fullscreen e acessibilidade. Corrigir apenas falhas reproduzidas.
3. Fixar 0.1.0/build 6+, atualizar README/current-product/release docs e completar
   o draft `docs/RELEASE-NOTES-v0.1.md` com o escopo final.
4. Rodar novamente Debug/tests/Release/analyze e checks Web; revisar e commitar o
   candidato por ação do maintainer. Manter outputs e bancos fora do Git.
5. Instalar Developer ID e salvar perfil notarytool em Keychain com os prompts;
   configurar Team ID. Não colocar senhas em scripts/terminal history/repositório.
6. Gerar archive/export/DMG, notarizar/staple/verificar e reter arquivo versionado,
   checksum pós-staple e source revision. Não substituir o beta.3 congelado.
7. Testar o artefato exato numa instalação limpa e upgrade do beta.3; registrar
   Gatekeeper, autosave/relaunch/search/Refine disponível e indisponível.
8. Tornar os repositórios públicos quando liberados; criar tag e GitHub Release
   com os bytes, checksum e notes aprovados. Conferir acesso sem autenticação.
9. Atualizar `rasc-web/src/content/launch.ts` com o release real, `notarized`,
   `sourcePublic` e `publicReleaseReady`; validar link/requirements e checks, commitar.
10. Deployar pelo workflow Pages, conferir site/download/social cards anonimamente
    e publicar o v0.1. Só então mudar o verdict para READY FOR v0.1.
