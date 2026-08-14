# Changelog

## 1.4.0

- Define o usuário como única autoridade decisória na colaboração Codex + Grok Build.
- Introduz Gate 1 para aprovação explícita do plano antes de trabalho não trivial e Gate 2 para validação manual antes de ações de integração ou produção.
- Define o plano aprovado como envelope de execução e obriga escalação de desvios materiais com evidências, alternativas, trade-offs e recomendação.
- Padroniza o Work Order com escopo humano real, áreas de leitura/modificação, contratos preservados, limites decisórios e condições de escalação.
- Padroniza o retorno do Grok em `COMPLETED`, `COMPLETED_WITH_CONCERNS`, `BLOCKED_BY_DECISION` ou `UNABLE_TO_VALIDATE`.
- Adiciona `MANUAL_DE_USO.md` com instalação nova, verificação/atualização de pack antigo e operação correta do fluxo completo.
- Preserva a versão 1.3.0 no catálogo de compatibilidade para atualização reconciliada de instalações existentes.
- Amplia os validadores para proteger semanticamente os gates, a autoridade humana e os contratos Codex→Grok.

## 1.3.0

- Adiciona suporte opt-in ao Grok Build por `-IncludeGrokBuild` e `--include-grok-build`, mantendo Codex obrigatório e Claude Code independente.
- Define Codex como plano de controle para raciocínio, design, review e julgamento, e Grok Build como plano de execução para paralelismo, velocidade e isolamento por worktree.
- Instala configuração mínima em `.grok/config.toml`, agentes em `.grok/agents` e skills espelhadas em `.grok/skills`, sem criar `GROK.md`.
- Adiciona as skills complementares `delegate-to-grok-build` e `execute-codex-work-order`, com proibição de commit, push, deploy, migration e operações destrutivas.
- Adiciona o prompt `09-migrate-claude-to-codex-grok.md` para preservar orientação útil, remover artefatos Claude comprovadamente gerenciados e preparar o repositório.
- Adiciona `Integration codex,grok` e `--integration codex,grok` ao reconciliador para tornar a seleção durável e impedir a reinstalação futura do Claude.
- Mantém worktrees, sessões e estado operacional do Grok fora do repositório; somente regras, configuração, agentes e skills do projeto são versionados.
- Estende validadores, smoke tests e fontes oficiais para cobrir paridade de agentes/skills, perfis opcionais e política de segurança do Grok.

## 1.2.0

- Adiciona atualização reconciliada para repositórios que já possuem o Agent Pack, com plano somente leitura, estado local e aplicação bloqueada por conflitos.
- Introduz IDs estáveis e políticas `managed`, `merge` e `seed` em `pack-artifacts.txt`, além do catálogo de compatibilidade da versão 1.1.0.
- Preserva customizações do repositório e exige decisões explícitas por artefato para aceitar o pack, aceitar uma mesclagem manual ou manter a versão local.
- Adiciona a skill compartilhada `update-agent-pack` e o prompt operacional correspondente para Codex e Claude Code.
- Adiciona a skill `check-text-encoding`, com verificadores PowerShell e Bash para UTF-8 inválido, caractere de substituição e assinaturas prováveis de mojibake.
- Integra a verificação de texto às regras persistentes e à validação do próprio pack.
- Define disciplina de contexto e tokens: buscar antes de ler, carregar somente evidência relevante, evitar releituras e delegação redundante, sem reduzir segurança ou validação.

## 1.1.0

- Adiciona suporte opt-in ao Claude Code por `-IncludeClaude` e `--include-claude`, mantendo o Codex como integração padrão.
- Instala o bridge `CLAUDE.md`, agentes em `.claude/agents` e skills espelhadas em `.claude/skills` somente quando solicitado.
- Estende o manifesto com destino opcional para reutilizar uma origem canônica em caminhos específicos de cada ferramenta.
- Documenta a equivalência entre `$skill` no Codex e `/skill` no Claude Code, além do mapeamento de agentes de `snake_case` para `kebab-case`.
- Mantém `InstallGlobal` e `--install-global` exclusivos da orientação global do Codex.

## 1.0.0

- Generaliza o pack para repositórios .NET modernos e legados.
- Adiciona instalação por componentes, descoberta determinística e validações locais.
- Separa perfis opcionais de web, SQL Server e qualidade.
