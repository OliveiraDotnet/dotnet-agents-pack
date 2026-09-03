# .NET Agents Pack adoption guide

English operating docs for 1.6.0 are in `README.md` and `MANUAL_DE_USO.md`. This file keeps the deeper adoption notes; prefer those two documents for install, upgrade, and daily use.

# Guia de adoção do .NET Agents Pack

## Objetivo

O pack reduz o tempo de entendimento de repositórios .NET sem substituir evidência por regras genéricas. Ele atende projetos SDK-style, .NET Framework clássico e soluções mistas; a stack real sempre vem de arquivos do repositório, CI, scripts e testes existentes.

O pack não executa build, restore, migration, banco ou deploy automaticamente. Cada uma dessas ações depende de um comando confirmado e da autorização aplicável.

O Codex é a integração padrão e o plano de controle. Claude Code pode ser acrescentado como compatibilidade opt-in; Grok Build pode ser acrescentado como plano de execução opt-in para paralelismo, velocidade e isolamento por worktree. As integrações são independentes e podem coexistir.

## Como o contexto é distribuído

| Camada | Deve conter | Não deve conter |
|---|---|---|
| `AGENTS.md` | Fatos e regras curtas sempre relevantes. | Teoria genérica, comandos não verificados ou catálogos de agentes. |
| `CLAUDE.md` | Bridge para `AGENTS.md` e adaptações estritamente necessárias ao Claude Code. | Cópia divergente das regras compartilhadas do projeto. |
| `.grok/` | Configuração mínima do projeto, agentes e skills necessários ao Grok Build. | Worktrees, sessões, transcrições, autenticação ou preferências da máquina. |
| `docs/ai/` | Mapa, arquitetura, persistência, domínio e runbook confirmados. | Segredos, dados pessoais ou inventários completos. |
| Skills | Workflow sob demanda. | Contexto de um projeto específico. |
| Subagentes | Trabalho independente e delimitado. | Fan-out por padrão. |
| Prompts | Dados do pedido. | Repetição do workflow da skill. |

O Codex usa a cadeia de `AGENTS.md` da raiz do projeto até o diretório de trabalho atual. Um `AGENTS.override.md` aninhado só entra na cadeia quando a tarefa inicia naquele diretório ou abaixo dele. Não use overrides aninhados como se fossem acionados pelo arquivo que está sendo editado.

Quando `IncludeClaude` está habilitado, o `CLAUDE.md` da raiz importa `AGENTS.md`, evitando duas fontes de regras persistentes. As skills continuam canônicas em `.agents/skills` e são espelhadas em `.claude/skills` para descoberta nativa pelo Claude Code. Os agentes equivalentes ficam em `.codex/agents` e `.claude/agents`, cada um no formato exigido pela respectiva ferramenta.

Quando `IncludeGrokBuild` está habilitado, o Grok lê `AGENTS.md` diretamente. Skills compartilhadas são espelhadas de `.agents/skills` para `.grok/skills`, e os agentes Markdown equivalentes ficam em `.grok/agents`. Não existe `GROK.md` no pack.

A configuração `.grok/config.toml` nega commit, push, reset destrutivo e limpeza destrutiva. Configurações pessoais, autenticação, sandbox, sessões e worktrees pertencem ao diretório do usuário; não devem ser versionadas nem redirecionadas para dentro do projeto.

## Uso eficiente de contexto e tokens

Eficiência de tokens significa reduzir trabalho redundante, não reduzir diligência. Todo agente que usar o pack deve:

- começar com busca por nomes, símbolos e caminhos antes de abrir arquivos completos;
- ler somente arquivos e trechos relevantes, expandindo o contexto quando houver dependências, risco ou incerteza;
- reutilizar fatos confirmados em `docs/ai` e evitar repetir descoberta já válida;
- resumir logs, diffs e saídas extensas, preservando as linhas que sustentam a decisão;
- delegar apenas perguntas independentes cujo paralelismo compense o contexto adicional;
- executar a validação proporcional ao impacto, sem omitir verificações necessárias para economizar tokens.

Respostas devem ser diretas e referenciar arquivos ou evidências, sem reproduzir conteúdo grande que já esteja disponível no repositório. Se o contexto mínimo não for suficiente para uma decisão segura, o agente deve ampliá-lo explicitamente.

## Instalação

Por padrão, o instalador exige que `RepoPath` seja exatamente a raiz Git. Isso impede instalação acidental em uma subpasta, no próprio pack ou em uma árvore aninhada. Em uma pasta sem Git, use a opção explícita `AllowNonGit`.

```powershell
# Núcleo somente
.\scripts\install-agent-pack.ps1 -RepoPath "C:\src\MeuSistema"

# Núcleo e perfis detectados ou conhecidos
.\scripts\install-agent-pack.ps1 -RepoPath "C:\src" -DiscoverOnly
.\scripts\install-agent-pack.ps1 -RepoPath "C:\src\MySystem" -Profile web,sqlserver,quality

# Inspecionar sem escrever
.\scripts\install-agent-pack.ps1 -RepoPath "C:\src\MeuSistema" -Profile web -DryRun

# Acrescentar Claude Code à instalação padrão do Codex
.\scripts\install-agent-pack.ps1 -RepoPath "C:\src\MeuSistema" -Profile web,quality -IncludeClaude

# Acrescentar Grok Build como plano de execução do Codex
.\scripts\install-agent-pack.ps1 -RepoPath "C:\src\MeuSistema" -Profile web,quality -IncludeGrokBuild
```

```bash
bash ./scripts/install-agent-pack.sh /src/meu-sistema
bash ./scripts/install-agent-pack.sh /src --discover-only
bash ./scripts/install-agent-pack.sh /src/my-system --profile web,sqlserver,quality
bash ./scripts/install-agent-pack.sh /src/meu-sistema --profile web --dry-run
bash ./scripts/install-agent-pack.sh /src/meu-sistema --profile web,quality --include-claude
bash ./scripts/install-agent-pack.sh /src/meu-sistema --profile web,quality --include-grok-build
```

Componentes disponíveis:

- `core`: sempre instalado; contém o bootstrap e os agentes principais.
- `web`: Razor, MVC, Blazor e JavaScript.
- `sqlserver`: SQL Server e workflow de alteração de dados.
- `quality`: security, performance, and release review. Never auto-selected.
- Flutter was removed in 1.6.0. Unchanged 1.5.0 Flutter artifacts matching the compatibility catalog are retired on update.

`IncludeClaude`/`--include-claude` e `IncludeGrokBuild`/`--include-grok-build` não são perfis funcionais. Cada opção acrescenta o adaptador correspondente somente para o núcleo e os perfis já selecionados. Sem a flag, nenhum arquivo específico daquela ferramenta é instalado. As duas opções podem ser usadas juntas.

O manifesto usa `componente|origem|destino`. O destino é opcional; quando omitido, o arquivo é copiado para o mesmo caminho relativo da origem. Esse terceiro campo permite instalar uma skill canônica de `.agents/skills` também em `.claude/skills` ou `.grok/skills` sem manter implementações divergentes.

O instalador compara conteúdo. Arquivo idêntico é ignorado; arquivo diferente recebe `.agent-pack.new`; um sidecar existente e divergente é preservado como conflito. `Force` cria backup com timestamp antes de substituir.

`InstallGlobal` é opcional e instala apenas um exemplo neutro de orientação pessoal do Codex. Ele usa `CODEX_HOME` quando definido e, caso contrário, `~/.codex`. Essa opção não instala configuração global do Claude Code ou do Grok Build; as flags de integração atuam somente no repositório de destino.

## Atualização de uma instalação existente

O instalador permanece responsável pela primeira cópia. Para evoluir um repositório que já recebeu o pack, use o reconciliador:

```powershell
# Gerar o plano sem escrever
.\scripts\update-agent-pack.ps1 -RepoPath "C:\src\MeuSistema" -Check

# Aplicar um plano sem conflitos
.\scripts\update-agent-pack.ps1 -RepoPath "C:\src\MeuSistema" -Apply
```


# Migrar de Claude para Codex + Grok, preservando a escolha no estado
.\scripts\update-agent-pack.ps1 -RepoPath "C:\src\MeuSistema" -Check -Integration codex,grok
.\scripts\update-agent-pack.ps1 -RepoPath "C:\src\MeuSistema" -Apply -Integration codex,grok
```bash
bash ./scripts/update-agent-pack.sh /src/meu-sistema --check
bash ./scripts/update-agent-pack.sh /src/meu-sistema --apply
bash ./scripts/update-agent-pack.sh /src/meu-sistema --check --integration codex,grok
bash ./scripts/update-agent-pack.sh /src/meu-sistema --apply --integration codex,grok
```

Na primeira atualização, o reconciliador compara os arquivos existentes com fingerprints em `compat/releases/` e adota automaticamente somente conteúdo atribuível a uma versão confiável. Depois da aplicação, `.agent-pack/state.txt` registra versão, perfis, integrações, IDs e baselines, sem caminhos absolutos ou dados da máquina. Lock, backups e artefatos aposentados ficam em `.agent-pack/.runtime`, protegido por um `.gitignore` próprio.

As políticas de `pack-artifacts.txt` são:

| Propriedade | Exemplos | Comportamento |
|---|---|---|
| `managed` | Skills, agentes e prompts. | Atualiza ou remove somente quando o arquivo ainda corresponde ao baseline conhecido. |
| `merge` | `AGENTS.md`, `CLAUDE.md` e `.grok/config.toml`. | Conteúdo adaptado pelo projeto exige revisão e resolução explícita. |
| `seed` | `docs/ai/*`. | Cria se estiver ausente; nunca atualiza nem remove automaticamente. |

Conflitos interrompem a transação antes de qualquer escrita. Resolva um ID por vez com `-AcceptMerge`, `-AcceptPack` ou `-KeepLocal`; no shell, use `--accept-merge`, `--accept-pack` ou `--keep-local`. `KeepLocal` destaca aquele artefato de atualizações gerenciadas. Não use o `Force` global do instalador como estratégia de atualização.

O reconciliador preserva os perfis e integrações registrados no estado ou inferidos da instalação legada. Um perfil recém-adicionado ao catálogo não entra em todos os repositórios automaticamente; sua ativação futura deverá partir da inspeção tecnológica do repositório e de uma seleção explícita.

`Integration`/`--integration` substitui explicitamente a seleção de ferramentas e sempre exige `codex`. Use `codex,grok` para retirar Claude de modo durável; o atualizador então aposenta apenas artefatos Claude cujo ownership é comprovado. O prompt `prompts/09-migrate-claude-to-codex-grok.md` exige migrar orientação útil antes da remoção.

No Codex, invoque `$update-agent-pack`; no Claude Code, `/update-agent-pack`. A skill deve preservar fatos específicos do projeto, revisar o diff e iniciar uma nova tarefa ou sessão depois que instruções persistentes mudarem.

## Verificação de UTF-8 e mojibake

A skill `check-text-encoding` é parte do núcleo e deve rodar depois de alterações em código, documentação, prompts, rules ou skills. Por padrão, ela verifica arquivos alterados e não rastreados; use a varredura total apenas para auditoria:

```powershell
.\.agents\skills\check-text-encoding\scripts\check-mojibake.ps1
.\.agents\skills\check-text-encoding\scripts\check-mojibake.ps1 -All
```

```bash
bash ./.agents/skills/check-text-encoding/scripts/check-mojibake.sh
bash ./.agents/skills/check-text-encoding/scripts/check-mojibake.sh --all
```

Os verificadores são somente leitura. Eles detectam UTF-8 inválido, o caractere de substituição e assinaturas de texto UTF-8 decodificado incorretamente. Cada ocorrência precisa ser confirmada no contexto; não transcodifique um arquivo inteiro nem remova acentos para esconder o problema. Dados de teste intencionais podem usar `agent-pack:allow-mojibake` na mesma linha, com justificativa curta.

## Bootstrap obrigatório por repositório

Após instalar, abra o repositório no agente escolhido e cole `prompts/00-bootstrap-repo.md`. No Codex, invoque `$bootstrap-dotnet-repo`; no Claude Code, invoque `/bootstrap-dotnet-repo`.

A skill executa uma inspeção somente leitura para encontrar:

- forma do workspace e raiz Git;
- `.sln`, `.slnx`, `.csproj`, `.fsproj`, `.vbproj`, `global.json` e `Directory.Build.*`;
- SDK-style, projetos clássicos e `packages.config`;
- frameworks alvo, pacotes e projetos de teste;
- sinais de web, legado e SQL Server;
- CI e scripts que podem conter comandos confirmados.

O resultado é uma hipótese estruturada. Confirme os comandos de build, teste e execução em CI, scripts ou documentação antes de registrá-los no `project-map.md`. Para .NET Framework, os comandos podem envolver MSBuild, NuGet, Visual Studio workloads ou VSTest; o pack nunca deve inserir `dotnet build` por suposição.

O bootstrap pode atualizar `AGENTS.md` e `docs/ai`, mas as instruções novas passam a valer plenamente em uma nova tarefa do Codex ou uma nova sessão do Claude Code. Não altere código de produção nesse fluxo.

## Fluxos de trabalho

| Necessidade | Prompt | Codex | Claude Code |
|---|---|---|---|
| Mapear repositório | `prompts/00-bootstrap-repo.md` | `$bootstrap-dotnet-repo` | `/bootstrap-dotnet-repo` |
| Corrigir bug | `prompts/01-bugfix.md` | `$bugfix-dotnet` | `/bugfix-dotnet` |
| Implementar feature | `prompts/02-feature-slice.md` | `$feature-slice-dotnet` | `/feature-slice-dotnet` |
| Alterar SQL Server | `prompts/03-db-change.md` | `$db-change-sqlserver` | `/db-change-sqlserver` |
| Revisar estrutura SQL Server | — | `$sqlserver-structure-review` | `/sqlserver-structure-review` |
| Testar .NET com xUnit | — | `$dotnet-xunit-tests` | `/dotnet-xunit-tests` |
| .NET web UI | — | `$web-dotnet` | `/web-dotnet` |
| Understand SQL Server | — | `$sqlserver-structure-review` | `/sqlserver-structure-review` |
| Revisar mudança | `prompts/04-pr-review.md` | `$pr-review-dotnet` | `/pr-review-dotnet` |
| Refatorar legado | `prompts/05-refactor-legado.md` | `$legacy-refactor-dotnet` | `/legacy-refactor-dotnet` |
| Atualizar memória | `prompts/06-update-agent-memory.md` | `$maintain-agent-memory` | `/maintain-agent-memory` |
| Investigar sem alterar | `prompts/07-investigate-only.md` | `repo_explorer`, se necessário | `repo-explorer`, se necessário |
| Atualizar o Agent Pack | `prompts/08-update-agent-pack.md` | `$update-agent-pack` | `/update-agent-pack` |

O prefixo `$` é a forma de invocação explícita de skills no Codex. No Claude Code, a mesma skill instalada em `.claude/skills` é invocada com `/`. O conteúdo do workflow é compartilhado; apenas a descoberta e a sintaxe de chamada variam.

## Colaboração entre Codex e Grok Build

A integração não trata os dois agentes como pares sem coordenação. O usuário é a única autoridade decisória. O Codex é responsável por raciocínio técnico, desenho, critérios, julgamento de risco, delegação, review e recomendação. O Grok Build é responsável por execução delimitada, paralelismo de subtarefas independentes e isolamento mecânico em worktrees nativos.

| Etapa | Responsável | Saída |
|---|---|---|
| Descoberta e design | Codex | Evidências, estratégia, escopo, riscos e critérios de aceite. |
| Implementação paralela | Grok Build | Mudanças e validações em worktree isolado, sem commit ou push. |
| Review e recomendação | Codex | Review do diff real, validação independente e recomendação: validar manualmente, revisar, descartar ou decidir. |
| Decisão final | Usuário | Aprovação manual e autorização explícita para qualquer commit, push, merge, deploy, release, migration de produção ou alteração de dados. |

A skill `delegate-to-grok-build`, instalada em `.agents/skills`, formaliza a delegação. A skill `execute-codex-work-order`, instalada em `.grok/skills`, obriga o Grok a executar somente a ordem recebida e a usar subagentes paralelos apenas quando as tarefas forem realmente independentes; subagentes que alteram arquivos devem usar `isolation: worktree`.

O fluxo possui dois gates. No Gate 1, o Codex apresenta evidências, escopo, arquivos prováveis, riscos e estratégia de validação; implementação ou delegação não trivial só começa após aprovação explícita. O plano aprovado torna-se o envelope de execução. Escolhas mecânicas triviais são permitidas dentro dele, mas qualquer desvio material deve voltar ao usuário.

Cada ordem de trabalho deve informar:

- objetivo, contexto e resultado observável;
- conteúdo real do escopo aprovado pelo usuário e não objetivos;
- ref base e áreas permitidas separadamente para leitura e modificação;
- invariantes de arquitetura, contratos que não podem mudar e critérios de aceite;
- comandos de validação confirmados;
- ações proibidas, limites decisórios e condições de escalação;
- contrato de retorno estruturado.

Grok pode questionar premissas, mas deve retornar `BLOCKED_BY_DECISION` antes de alterar materialmente escopo, comportamento, arquitetura, contratos públicos, dependências de produção, segurança, semântica de dados ou a estratégia de validação. Esse retorno inclui evidências, restrição afetada, decisão necessária, alternativas, trade-offs, recomendação e confirmação de que a mudança material não foi executada.

A invocação headless recomendada é:

```text
grok --no-auto-update --worktree=<task-label> --ref <base-ref> -p "<work-order>" --output-format json
```

Depois da execução, o Codex inspeciona o worktree real, revisa o diff, verifica independentemente as alegações e executa novamente as validações relevantes no destino. No Gate 2, apresenta ao usuário a recomendação e um roteiro de validação manual. Somente o usuário pode autorizar commit, push, merge, deploy, release, migration de produção ou alteração de dados. O repositório não recebe diretórios de sessão, transcript, coordenação ou worktree; o runtime nativo permanece em `~/.grok`.

O fluxo padrão não usa `--yolo`. Qualquer permissão adicional deve ser explícita, temporária e limitada ao comando necessário.

## Roteamento de agentes

O agente principal deve fazer a mudança. Delegue apenas uma pergunta independente:

- `repo_explorer`: fluxo, metadados e impacto antes da alteração;
- `dotnet_implementer`: uma implementação delimitada depois do mapeamento;
- `test_guardian`: descoberta ou implementação de validação;
- `change_reviewer`: revisão principal baseada no diff;
- agentes de perfis: somente quando o stack ou o diff os justificar.

Os identificadores dos agentes seguem a convenção nativa de cada ferramenta. O Codex usa `snake_case` nos arquivos TOML; Claude Code e Grok Build usam os arquivos Markdown correspondentes em `kebab-case`:

| Codex | Claude Code / Grok Build |
|---|---|
| `repo_explorer` | `repo-explorer` |
| `dotnet_implementer` | `dotnet-implementer` |
| `test_guardian` | `test-guardian` |
| `change_reviewer` | `change-reviewer` |
| `frontend_web` | `frontend-web` |
| `database_sqlserver` | `database-sqlserver` |
| `security_reviewer` | `security-reviewer` |
| `performance_reviewer` | `performance-reviewer` |
| `release_reviewer` | `release-reviewer` |

Em geral, use zero a dois subagentes. Uma revisão que toca banco, autenticação e caminho de alta carga pode justificar três especialistas; bootstrap e PR comuns não justificam uma bateria fixa de revisores.

## Memória técnica

Registre fatos uma vez, com fonte e data de verificação. Use `AGENTS.md` apenas para regras curtas e duráveis. Use `docs/ai` para detalhes. Não transforme log de incidentes, hipótese ou dados sensíveis em instrução persistente.

## Regras de segurança

- Nunca registre secrets, tokens, chaves privadas, connection strings, payloads ou dados pessoais reais.
- Não conecte em banco, execute migrations ou scripts contra ambiente algum sem solicitação explícita.
- Em revisão de segurança ou performance, separe evidência de hipótese e informe a validação necessária.
- Mudança de contrato, schema, permissão ou configuração exige impacto e rollback quando aplicável.

## Evolução do pack

Mantenha uma mudança por vez: primeiro atualize workflow ou componente que falhou em uso real, depois acrescente perfil quando houver recorrência. Não crie agentes por framework ou versão. A escala vem de descoberta, perfis opcionais, manifest e testes de instalação.

Antes de alterar, renomear ou remover artefatos de uma versão já publicada, congele seus hashes normalizados em `compat/releases/<versão>.txt`. Preserve o mesmo `artifact_id` em renames, nunca reescreva um catálogo publicado e mantenha correspondência um-para-um entre destinos de `pack-manifest.txt` e `pack-artifacts.txt`. Depois, incremente `pack-version.txt` e o cabeçalho do manifesto.

Antes de publicar uma versão, execute:

```powershell
.\scripts\validate-pack.ps1
.\scripts\test-install-agent-pack.ps1
.\scripts\test-inspect-dotnet-repo.ps1
.\scripts\test-update-agent-pack.ps1
.\scripts\test-check-text-encoding.ps1
```

```bash
bash ./scripts/validate-pack.sh
bash ./scripts/test-install-agent-pack.sh
bash ./scripts/test-inspect-dotnet-repo.sh
bash ./scripts/test-update-agent-pack.sh
bash ./scripts/test-check-text-encoding.sh
```

O pack não prescreve um provedor de CI. Integre esses scripts ao pipeline que a organização já utiliza.

Consulte as [fontes oficiais do Codex](FONTES_OFICIAIS_CODEX.md), as [fontes oficiais do Claude Code](FONTES_OFICIAIS_CLAUDE.md) e as [fontes oficiais do Grok Build](FONTES_OFICIAIS_GROK_BUILD.md) ao evoluir formatos, caminhos ou regras específicos de uma ferramenta.
