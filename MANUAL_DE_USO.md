# Manual completo do .NET Agents Pack

## 1. Propósito e modelo operacional

O .NET Agents Pack instala orientação, agentes especializados, skills, prompts e memória técnica para que ferramentas de IA trabalhem em repositórios .NET modernos, legados ou mistos sem inventar arquitetura, comandos ou regras do projeto.

O Codex é a integração obrigatória e o plano de controle: investiga, raciocina, desenha a solução, avalia riscos, propõe planos, delega, revisa o diff real e valida de forma independente. Grok Build é um plano de execução opcional: implementa trabalho delimitado com velocidade, paralelismo e isolamento por worktree. Claude Code continua disponível como compatibilidade opcional e independente.

O usuário é a única autoridade decisória:

1. **Gate 1:** trabalho não trivial só começa depois que o usuário aprova explicitamente o plano, seu escopo, riscos e validações.
2. O plano aprovado vira o **envelope de execução**. Decisões mecânicas triviais são permitidas; desvios materiais voltam ao usuário.
3. **Gate 2:** depois da execução, o Codex revisa o worktree e o diff, repete validações e entrega um roteiro manual. Commit, push, merge, deploy, release, migration de produção e alteração de dados exigem autorização explícita do usuário.

## 2. O que o pack instala

O manifesto `pack-manifest.txt` é a fonte de verdade. Os principais destinos são:

| Caminho | Finalidade | Deve ser versionado? |
|---|---|---|
| `AGENTS.md` | Regras curtas e persistentes compartilhadas. | Sim. |
| `.codex/agents/` | Agentes especializados no formato nativo do Codex. | Sim. |
| `.agents/skills/` | Skills canônicas compartilhadas. | Sim. |
| `prompts/` | Entradas prontas para workflows frequentes. | Sim. |
| `docs/ai/` | Memória técnica confirmada do projeto. | Sim, sem segredos. |
| `CLAUDE.md`, `.claude/` | Bridge, agentes e skills do Claude, somente quando solicitado. | Sim, se Claude fizer parte do projeto. |
| `.grok/config.toml`, `.grok/agents/`, `.grok/skills/` | Política, agentes e adapters do Grok, somente quando solicitado. | Sim. |
| `.agent-pack/state.txt` | Estado reconciliável da versão, perfis, integrações e baselines. | Sim. |
| `.agent-pack/.runtime/` | Lock, backups e temporários do atualizador. | Não; o pack instala ignore próprio. |

Não versione worktrees, sessões, transcripts, autenticação, credenciais, caches, arquivos de coordenação ou configuração pessoal. O pack não cria `.ai-collab/` ou `GROK.md`, e o runtime nativo do Grok permanece fora do repositório.

## 3. Pré-requisitos

- Um checkout confiável deste Agent Pack.
- PowerShell no Windows, ou Bash em Linux/macOS/Git Bash.
- Git para a instalação normal. Use o modo sem Git apenas quando isso for intencional.
- Codex configurado para operar no repositório.
- Para Codex + Grok: Grok Build instalado, autenticado e acessível por `grok`.

Execute os comandos do pack a partir da raiz deste checkout e informe sempre a raiz Git exata do repositório de destino.

## 4. Instalação em repositório sem o Agent Pack

### 4.1 Inspecione antes de escolher perfis

Identifique a stack real pelo `.sln`, `.slnx`, projetos, scripts, CI e testes. Se ainda não houver certeza, instale somente o núcleo. Perfis disponíveis:

- `core`: sempre incluído; descoberta, implementação, testes, review, memória e segurança operacional.
- `web`: Razor, MVC, Blazor e JavaScript.
- `sqlserver`: SQL Server, EF, Dapper, scripts e migrations.
- `quality`: segurança, performance e revisão de release.

Claude e Grok são integrações, não perfis.

### 4.2 Faça primeiro um dry-run

PowerShell:

```powershell
.\scripts\install-agent-pack.ps1 `
  -RepoPath "C:\src\MeuSistema" `
  -Profile web,sqlserver,quality `
  -IncludeGrokBuild `
  -DryRun
```

Bash:

```bash
bash ./scripts/install-agent-pack.sh /src/meu-sistema \
  --profile web,sqlserver,quality \
  --include-grok-build \
  --dry-run
```

Revise destinos, conflitos e perfis. Para Codex apenas, remova a opção Grok. Para manter Claude também, acrescente `-IncludeClaude` ou `--include-claude`.

### 4.3 Instale

Repita o comando sem `-DryRun` ou `--dry-run`. Não use `Force` como padrão. Se um destino já existir e divergir, o instalador preserva o arquivo e cria um sidecar `.agent-pack.new` para revisão.

Em uma pasta intencionalmente sem Git, acrescente `-AllowNonGit` ou `--allow-non-git`. `-InstallGlobal`/`--install-global` é opcional e instala somente o exemplo neutro de orientação pessoal do Codex.

### 4.4 Faça o bootstrap

1. Abra o repositório instalado no Codex.
2. Use o prompt `prompts/00-bootstrap-repo.md` ou invoque `$bootstrap-dotnet-repo`.
3. Revise os fatos encontrados antes de aceitar atualizações em `AGENTS.md` ou `docs/ai`.
4. Rode a validação de encoding indicada pela skill.
5. Inicie uma nova tarefa para que as instruções persistentes atualizadas sejam recarregadas.

O bootstrap é somente leitura durante a descoberta e não deve inventar `dotnet build`, restore, testes, migration ou deploy.

## 5. Verificação quando o repositório pode ter um Agent Pack antigo

Não execute novamente o instalador com `Force`. Use o reconciliador, que distingue conteúdo gerenciado, customizado e pertencente ao projeto.

### 5.1 Inventário somente leitura

Verifique:

- `AGENTS.md`, `CLAUDE.md`, `.codex/`, `.agents/`, `.claude/`, `.grok/` e `prompts/`;
- `.agent-pack/state.txt`, quando presente;
- alterações locais com `git status`;
- regras únicas do projeto que não podem ser perdidas;
- sidecars `.agent-pack.new` de instalações anteriores.

### 5.2 Gere o plano de atualização

PowerShell:

```powershell
.\scripts\update-agent-pack.ps1 -RepoPath "C:\src\MeuSistema" -Check
```

Bash:

```bash
bash ./scripts/update-agent-pack.sh /src/meu-sistema --check
```

O modo check não escreve. Ele usa o estado local e fingerprints de releases confiáveis para classificar cada ação como criação, atualização, conflito, preservação ou aposentadoria.

### 5.3 Resolva conflitos por artefato

- `AcceptMerge`/`--accept-merge`: confirme uma mesclagem manual já revisada em arquivo de ownership `merge`.
- `AcceptPack`/`--accept-pack`: substitua ou aposente especificamente aquele artefato quando isso for intencional.
- `KeepLocal`/`--keep-local`: preserve e destaque um artefato customizado de atualizações futuras.

Nunca forneça uma resolução global. Preserve fatos, comandos e regras específicos do projeto.

### 5.4 Aplique somente um plano sem conflitos

PowerShell:

```powershell
.\scripts\update-agent-pack.ps1 -RepoPath "C:\src\MeuSistema" -Apply
```

Bash:

```bash
bash ./scripts/update-agent-pack.sh /src/meu-sistema --apply
```

Repita no apply as resoluções por ID que foram revisadas no check. Depois, revise o diff, rode as validações propostas e abra uma nova tarefa do agente.

### 5.5 Migrar de Claude para Codex + Grok

Use `prompts/09-migrate-claude-to-codex-grok.md`. Primeiro inventarie e migre regras, skills, agentes ou configuração útil do Claude. Depois torne a seleção durável:

```powershell
.\scripts\update-agent-pack.ps1 -RepoPath "C:\src\MeuSistema" -Check -Integration codex,grok
.\scripts\update-agent-pack.ps1 -RepoPath "C:\src\MeuSistema" -Apply -Integration codex,grok
```

```bash
bash ./scripts/update-agent-pack.sh /src/meu-sistema --check --integration codex,grok
bash ./scripts/update-agent-pack.sh /src/meu-sistema --apply --integration codex,grok
```

Remova `CLAUDE.md` e `.claude/` somente quando o ownership for comprovado e todo conteúdo útil tiver sido migrado ou explicitamente descartado. Não remova arquivos apenas porque o nome contém “Claude”.

## 6. Uso correto do Agent Pack

### 6.1 Inicie cada tarefa com contexto suficiente

O agente deve identificar a raiz, ler a cadeia aplicável de `AGENTS.md`, consultar somente a memória relevante em `docs/ai`, localizar comandos confirmados e entender o caminho afetado. `[UNVERIFIED]` não é fato.

Use os prompts e skills conforme o trabalho:

| Trabalho | Prompt | Skill Codex |
|---|---|---|
| Bootstrap | `00-bootstrap-repo.md` | `$bootstrap-dotnet-repo` |
| Bugfix | `01-bugfix.md` | `$bugfix-dotnet` |
| Feature | `02-feature-slice.md` | `$feature-slice-dotnet` |
| SQL Server | `03-db-change.md` | `$db-change-sqlserver` |
| Review | `04-pr-review.md` | `$pr-review-dotnet` |
| Refatoração legada | `05-refactor-legado.md` | `$legacy-refactor-dotnet` |
| Memória técnica | `06-update-agent-memory.md` | `$maintain-agent-memory` |
| Investigação somente leitura | `07-investigate-only.md` | agente `repo_explorer` quando necessário |
| Atualização do pack | `08-update-agent-pack.md` | `$update-agent-pack` |
| Remover Claude e habilitar Codex + Grok | `09-migrate-claude-to-codex-grok.md` | `$update-agent-pack` + `$delegate-to-grok-build` |

### 6.2 Gate 1: planeje e obtenha aprovação

Para trabalho não trivial, peça ao Codex que apresente:

- evidências e entendimento do problema;
- escopo e não objetivos;
- arquivos ou subsistemas prováveis;
- contratos e invariantes preservados;
- riscos e pontos de decisão;
- testes e comandos confirmados;
- estratégia de validação manual.

Só depois de sua aprovação o Codex pode implementar ou delegar. A aprovação vale para o conteúdo real do plano, não para uma declaração genérica de que existe aprovação.

### 6.3 Delegação Codex → Grok Build

Invoque `$delegate-to-grok-build` ou peça explicitamente a colaboração. O Codex deve enviar um Work Order com objetivo, contexto, escopo humano aprovado, não objetivos, base ref, áreas de leitura e modificação, restrições arquiteturais, contratos preservados, aceite, comandos verificados, proibições, limites decisórios, condições de escalação e contrato de retorno.

O Grok trabalha em worktree isolado. Ele pode paralelizar somente workstreams independentes e nunca deve permitir sobreposição de arquivos entre filhos modificadores.

Se encontrar uma premissa incorreta, Grok deve apresentar evidência. Se a correção exigir desvio material, retorna `BLOCKED_BY_DECISION`; não improvisa, não expande o escopo e não cria arquivo de handoff no repositório.

### 6.4 Contrato de retorno do Grok

Espere um dos estados:

- `COMPLETED`: escopo atendido e validação executada.
- `COMPLETED_WITH_CONCERNS`: implementado, mas há desvios ou riscos que exigem atenção.
- `BLOCKED_BY_DECISION`: uma decisão material pertence ao usuário.
- `UNABLE_TO_VALIDATE`: a implementação pode existir, mas a validação necessária não pôde ser concluída.

O relatório inclui worktree, resumo, arquivos, decisões técnicas, testes, comandos/resultados, desvios, riscos, premissas e worktrees filhos restantes. Um bloqueio inclui evidência, restrição, decisão, alternativas, trade-offs, recomendação e confirmação do que não foi feito.

### 6.5 Review independente do Codex

O Codex deve verificar `git status`, diff completo, arquivos novos, `git diff --check`, contratos, segurança e resultados. Em seguida, repete validações relevantes no destino. O resumo do Grok nunca substitui o diff.

O Codex entrega somente uma recomendação:

- `READY_FOR_MANUAL_VALIDATION`;
- `REVISE`;
- `DISCARD`;
- `USER_DECISION_REQUIRED`.

### 6.6 Gate 2: valide manualmente e autorize

Execute o cenário manual fornecido pelo Codex, conferindo entrada, ação e resultado esperado. Só então autorize explicitamente a ação desejada. Aprovar a implementação não autoriza automaticamente commit, push, merge, deploy, release, migration ou alteração de dados.

## 7. Higiene e segurança

- Nunca coloque tokens, senhas, connection strings, chaves, dados pessoais ou produção em prompts, memória ou logs.
- Não use `--yolo` ou aprovação irrestrita como fluxo padrão do Grok.
- Não invente comandos de build ou teste.
- Não delegue decisões ambíguas, mudanças arquiteturais materiais ou julgamento final.
- Não use duas worktrees para modificar os mesmos arquivos ou contratos acoplados.
- Não versione runtime, worktrees, transcripts, caches ou temporários.
- Rode a skill `check-text-encoding` após alterações em texto.
- Atualize `docs/ai` apenas com conhecimento durável, confirmado, datado e sem segredos.

## 8. Checklist operacional

### Instalação nova

- [ ] Confirmar raiz Git e perfis reais.
- [ ] Rodar dry-run.
- [ ] Revisar os destinos.
- [ ] Instalar Codex e integrações desejadas.
- [ ] Executar bootstrap.
- [ ] Revisar diff e encoding.
- [ ] Iniciar nova tarefa.

### Repositório antigo

- [ ] Inventariar arquivos e estado sem escrever.
- [ ] Rodar update em `check`.
- [ ] Preservar customizações por artefato.
- [ ] Aplicar apenas plano sem conflitos.
- [ ] Revisar diff e validações.
- [ ] Iniciar nova tarefa.

### Codex + Grok

- [ ] Usuário aprovou o plano no Gate 1.
- [ ] Work Order contém o escopo aprovado real e todos os limites.
- [ ] Grok usou worktree isolado e não fez commit/push.
- [ ] Codex revisou o diff real e validou independentemente.
- [ ] Usuário executou a validação manual do Gate 2.
- [ ] Qualquer ação posterior recebeu autorização explícita.

## 9. Por que o Agent Pack é importante

O pack transforma colaboração com IA em um processo repetível e auditável. Ele reduz redescoberta por meio de memória técnica, mantém workflows especializados sob demanda, impede que provedores criem regras divergentes e combina a capacidade de julgamento do Codex com a execução paralela e isolada do Grok. Os dois agentes continuam subordinados às decisões humanas, a mudanças verificáveis e às regras reais de cada repositório.

Esse modelo reduz três riscos comuns: agentes inventando contexto, paralelismo causando colisões e automação ultrapassando a autorização do desenvolvedor. O resultado esperado não é apenas mais velocidade, mas desenvolvimento mais seguro, revisável e sustentável.
