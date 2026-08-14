# Fontes oficiais do Grok Build

Este arquivo registra as decisões específicas do Grok Build usadas pelo Agent Pack. Consulte novamente as fontes antes de alterar caminhos, formatos ou políticas.

## Regras e contexto do projeto

- [Project rules](https://docs.x.ai/build/features/project-rules): o Grok Build lê `AGENTS.md` como instrução de projeto.
- O pack não cria `GROK.md`: `AGENTS.md` permanece a fonte compartilhada entre Codex e Grok Build.

## Skills, agentes e configuração

- [Skills, plugins and marketplaces](https://docs.x.ai/build/features/skills-plugins-marketplaces): skills locais do projeto usam `.grok/skills`.
- [Subagents](https://docs.x.ai/build/features/subagents): agentes personalizados usam arquivos Markdown em `.grok/agents`; subagentes podem executar em paralelo e usar isolamento por worktree.
- [Settings](https://docs.x.ai/build/settings): configuração de projeto usa `.grok/config.toml`.
- [Permissions](https://docs.x.ai/build/features/permissions): regras de permissão podem permitir, perguntar ou negar comandos específicos.

O pack instala em `.grok/config.toml` somente uma política mínima do projeto que nega commit, push e operações Git destrutivas. Autenticação, modelo, sandbox e preferências pessoais continuam sob responsabilidade da configuração do usuário.

## Worktrees e execução não interativa

- [Worktrees](https://docs.x.ai/build/features/worktrees): worktrees nativos ficam em `~/.grok/worktrees`, fora do repositório principal; sessões ficam em `~/.grok/sessions`.
- [CLI reference](https://docs.x.ai/build/cli/reference): `--worktree`, `--ref`, `--output-format` e `--no-auto-update` são opções oficiais.
- [Headless and scripting](https://docs.x.ai/build/cli/headless-scripting): `grok -p` permite execução headless e saída estruturada.
- [Grok Build overview](https://docs.x.ai/build/overview): visão geral do produto e instalação.
- [Official source: getting started](https://github.com/xai-org/grok-build/blob/main/crates/codegen/xai-grok-pager/docs/user-guide/01-getting-started.md): guia mantido no repositório oficial.
- [Official source: subagents](https://github.com/xai-org/grok-build/blob/main/crates/codegen/xai-grok-pager/docs/user-guide/16-subagents.md): detalhes de paralelismo e isolamento.
- [Announcement](https://x.ai/news/grok-build-cli): anúncio oficial do Grok Build.

O Agent Pack usa essas capacidades com a seguinte divisão:

1. Codex investiga, raciocina, projeta, define critérios e cria uma ordem de trabalho delimitada.
2. Grok Build executa trabalho mecânico ou paralelizável em worktree nativo.
3. Codex revisa o diff real, julga riscos, valida de forma independente e recomenda o próximo passo; o usuário decide e autoriza a integração.

## Decisões deliberadas do pack

- `IncludeGrokBuild` e `--include-grok-build` são opt-in e independentes de `IncludeClaude`.
- Skills compartilhadas continuam canônicas em `.agents/skills` e são espelhadas em `.grok/skills` apenas para descoberta nativa.
- Não se versionam worktrees, sessões, transcrições ou estado da máquina.
- Não se cria `.ai-collab`, `.grok-worktrees` ou outro diretório de coordenação no repositório.
- Não se ignora `.grok/` inteira: agentes, skills e configuração de projeto instalados ali são parte intencional e versionável da integração.
- A automação padrão não usa `--yolo`; permissões amplas exigem decisão explícita do usuário.
- Grok Build não recebe autorização para commit, push, deploy, migration ou aplicação direta na branch principal.
- O usuário é a única autoridade decisória; planos não triviais e ações de integração ou produção passam por gates humanos explícitos.
