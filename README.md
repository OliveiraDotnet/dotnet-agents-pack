# .NET Agents Pack

Pack genérico para orientar agentes de código em repositórios .NET modernos e legados sem impor arquitetura, comandos ou preferências pessoais. O Codex permanece a integração padrão e o plano de controle; Claude Code e Grok Build são integrações opt-in independentes.

Ele fornece um núcleo pequeno para bootstrap, bugfix, feature, refatoração e revisão; perfis opcionais acrescentam especialização para web, SQL Server e revisão de qualidade.

## Componentes

| Componente | Instalação | Uso |
|---|---|---|
| `core` | sempre | Contexto do repositório, descoberta .NET, agentes de exploração/implementação/teste/revisão e skills principais. |
| `web` | opcional | Razor, MVC, Blazor e JavaScript. |
| `sqlserver` | opcional | SQL Server, EF, Dapper, scripts e migrations. |
| `quality` | opcional | Revisão de segurança, performance e release baseada em evidência. |

O manifesto em `pack-manifest.txt` é a fonte de verdade dos arquivos instalados. Cada entrada informa componente e origem, com um destino opcional para casos em que o mesmo conteúdo precisa ser exposto em outro caminho. Quando o destino é omitido, ele é igual à origem. O instalador nunca copia um perfil que não foi solicitado.

`pack-artifacts.txt` complementa o manifesto com um identificador estável e a política de propriedade de cada destino. `pack-version.txt` registra a versão do pack e `compat/releases/` mantém fingerprints confiáveis para a primeira atualização de instalações anteriores.

## Instalação

Execute na raiz do pack, apontando para a raiz Git do repositório de destino.

```powershell
# Windows PowerShell ou PowerShell 7
.\scripts\install-agent-pack.ps1 -RepoPath "C:\src\MeuSistema" -Profile web,sqlserver

# Visualizar as ações sem escrever arquivos
.\scripts\install-agent-pack.ps1 -RepoPath "C:\src\MeuSistema" -Profile quality -DryRun

# Codex e Claude Code no mesmo projeto
.\scripts\install-agent-pack.ps1 -RepoPath "C:\src\MeuSistema" -Profile web,quality -IncludeClaude

# Usuário aprova; Codex planeja e revisa; Grok Build executa em worktrees nativos
.\scripts\install-agent-pack.ps1 -RepoPath "C:\src\MeuSistema" -Profile web,quality -IncludeGrokBuild
```

```bash
# Linux, macOS ou Git Bash
bash ./scripts/install-agent-pack.sh /src/meu-sistema --profile web,sqlserver

# Visualizar as ações sem escrever arquivos
bash ./scripts/install-agent-pack.sh /src/meu-sistema --profile quality --dry-run

# Codex e Claude Code no mesmo projeto
bash ./scripts/install-agent-pack.sh /src/meu-sistema --profile web,quality --include-claude

# Usuário aprova; Codex planeja e revisa; Grok Build executa em worktrees nativos
bash ./scripts/install-agent-pack.sh /src/meu-sistema --profile web,quality --include-grok-build
```

Sem flags de integração, a instalação mantém o comportamento atual e instala somente o Codex. `IncludeClaude` acrescenta o bridge `CLAUDE.md`, agentes em `.claude/agents` e skills em `.claude/skills`. `IncludeGrokBuild` acrescenta a política mínima `.grok/config.toml`, agentes e skills nativos em `.grok`, a skill Codex `delegate-to-grok-build` e o prompt de migração. As duas flags podem coexistir.

Na colaboração Codex+Grok, o usuário é a única autoridade decisória. O Codex investiga, projeta, propõe o plano, delega dentro do escopo aprovado e revisa o diff; o Grok Build executa tarefas delimitadas com paralelismo e isolamento por worktree. Trabalho não trivial exige aprovação explícita do plano antes da execução e validação manual antes de qualquer autorização para commit, push, merge, deploy, release, migration de produção ou alteração de dados.

Use `-InstallGlobal` ou `--install-global` somente se quiser copiar o exemplo neutro de preferências pessoais do Codex. Ele respeita `CODEX_HOME` quando definido, não instala configuração global automaticamente e não instala orientação global do Claude Code.

Sem Git, use `-AllowNonGit` ou `--allow-non-git` conscientemente.

## Atualização segura de repositórios já instalados

Use o atualizador, não o `Force` do instalador, para evoluir um repositório que já recebeu o pack. A primeira execução reconhece arquivos idênticos de versões conhecidas; as seguintes usam `.agent-pack/state.txt` para distinguir conteúdo gerenciado pelo pack de conteúdo pertencente ao projeto.

```powershell
# Plano somente leitura
.\scripts\update-agent-pack.ps1 -RepoPath "C:\src\MeuSistema" -Check

# Aplicar somente quando o plano não tiver conflitos
.\scripts\update-agent-pack.ps1 -RepoPath "C:\src\MeuSistema" -Apply
```

```bash
bash ./scripts/update-agent-pack.sh /src/meu-sistema --check
bash ./scripts/update-agent-pack.sh /src/meu-sistema --apply
```

Para migrar uma instalação existente e tornar a escolha durável, use `-Integration codex,grok` no PowerShell ou `--integration codex,grok` no shell, primeiro com check e depois com apply. O prompt `prompts/09-migrate-claude-to-codex-grok.md` conduz a preservação de regras úteis, a remoção segura dos artefatos Claude e a validação final.

Skills, agentes e prompts são atualizados apenas quando a origem do arquivo é comprovada. A seleção de perfis e integrações já instalada é preservada; a mera existência de um perfil novo no pack não autoriza sua instalação. `AGENTS.md`, `CLAUDE.md` e `.grok/config.toml` exigem resolução explícita se tiverem sido adaptados pelo projeto. Arquivos em `docs/ai` são seeds: depois de criados, permanecem sob propriedade do repositório. Um conflito bloqueia toda a aplicação, e as decisões são fornecidas por artefato com `AcceptMerge`, `AcceptPack` ou `KeepLocal`.

No Codex, use `$update-agent-pack`; no Claude Code, `/update-agent-pack`. O prompt `prompts/08-update-agent-pack.md` orienta o mesmo fluxo.

## Primeiro uso

Abra o repositório no agente escolhido e execute o prompt `prompts/00-bootstrap-repo.md`. No Codex, invoque `$bootstrap-dotnet-repo`; no Claude Code, quando o suplemento estiver instalado, invoque `/bootstrap-dotnet-repo`. A skill executa uma inspeção somente leitura e registra fatos confirmados antes de preencher a memória técnica.

Codex e Grok Build carregam `AGENTS.md` diretamente. O bridge `CLAUDE.md` importa esse mesmo arquivo para o Claude Code. Depois do bootstrap, inicie uma nova tarefa ou sessão para recarregar instruções persistentes atualizadas.

## Garantias operacionais

- Não presume `dotnet build`, SQL Server, web ou arquitetura em camadas.
- Não executa restore, build, testes, migrations ou deploy durante a descoberta.
- O instalador não sobrescreve arquivo existente sem `Force`; o atualizador só substitui um artefato com baseline comprovado ou decisão explícita para aquele ID.
- Não instala arquivos do Claude Code sem `IncludeClaude` ou `--include-claude`.
- Não instala arquivos do Grok Build sem `IncludeGrokBuild` ou `--include-grok-build`.
- Mantém worktrees, sessões e estado operacional do Grok fora do repositório; somente regras, agentes, skills e configuração de projeto necessários são versionados.
- Não instala permissões de sandbox ou approval policy no repositório.
- Mantém instruções persistentes curtas; detalhes ficam em skills e `docs/ai`.
- Orienta o agente a começar pelo menor contexto suficiente, evitando releituras, saídas extensas e delegação redundante sem sacrificar correção ou validação.
- Verifica arquivos de texto alterados quanto a UTF-8 inválido e assinaturas prováveis de mojibake, sem reescrever ou remover acentos automaticamente.

Para adoção prática, consulte primeiro o [manual completo de uso](MANUAL_DE_USO.md). Consulte também [as instruções detalhadas](INSTRUCOES_DETALHADAS.md), o [changelog](CHANGELOG.md), as [fontes oficiais do Codex](FONTES_OFICIAIS_CODEX.md), as [fontes oficiais do Claude Code](FONTES_OFICIAIS_CLAUDE.md) e as [fontes oficiais do Grok Build](FONTES_OFICIAIS_GROK_BUILD.md) antes de adotar o pack em escala.
