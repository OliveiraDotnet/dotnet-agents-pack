# Fontes oficiais do Claude Code

Fontes verificadas em 2026-07-22 para orientar a compatibilidade deste pack com o Claude Code:

- [CLAUDE.md, imports, AGENTS.md e memória](https://code.claude.com/docs/en/memory)
- [Estrutura do diretório .claude](https://code.claude.com/docs/en/claude-directory)
- [Skills e comandos](https://code.claude.com/docs/en/slash-commands)
- [Subagentes e modos de permissão](https://code.claude.com/docs/en/sub-agents)
- [Configuração, escopos e precedência](https://code.claude.com/docs/en/settings)
- [Criação de plugins](https://code.claude.com/docs/en/plugins)
- [Referência de plugins](https://code.claude.com/docs/en/plugins-reference)

Princípios aplicados:

1. O `AGENTS.md` permanece como fonte canônica e o `CLAUDE.md` o importa sem duplicar instruções.
2. Skills seguem o padrão Agent Skills e usam `/nome-da-skill` no Claude Code.
3. Subagentes de projeto ficam em `.claude/agents/` e usam nomes em kebab-case.
4. Apenas agentes originalmente read-only recebem `permissionMode: plan`.
5. Configurações de permissão permanecem sob controle do usuário ou da organização.
