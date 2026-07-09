# Fontes oficiais do Codex

Fontes verificadas em 2026-07-09 para orientar a estrutura deste pack:

- [AGENTS.md e precedência](https://developers.openai.com/codex/guides/agents-md)
- [Subagentes](https://developers.openai.com/codex/subagents)
- [Skills](https://developers.openai.com/codex/skills)
- [Configuração e precedência](https://developers.openai.com/codex/config-basic)
- [Referência completa de configuração](https://developers.openai.com/codex/config-reference)
- [Sandbox](https://developers.openai.com/codex/concepts/sandboxing)
- [Approvals e segurança](https://developers.openai.com/codex/agent-approvals-security)

Princípios aplicados:

1. O `AGENTS.md` contém somente regras persistentes do repositório.
2. Skills guardam workflows e carregam detalhes sob demanda.
3. Subagentes são acionados apenas para trabalho independente e delimitado.
4. Configurações de permissão permanecem sob controle do usuário ou da organização.
5. O template não depende de camadas locais `.codex/` quando o projeto estiver não confiável.
