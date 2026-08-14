# Atualizar o Agent Pack deste repositório

Use `$update-agent-pack` no Codex, `/update-agent-pack` no Claude Code ou a skill nativa `update-agent-pack` no Grok Build.

Se o objetivo for retirar Claude e adotar Codex+Grok, use primeiro `prompts/09-migrate-claude-to-codex-grok.md`.

## Origem confiável

- Caminho do Agent Pack atualizado ou variável `AGENT_PACK_HOME`:
- Integrações desejadas, se houver mudança explícita (exemplo: `codex,grok`):

## Objetivo

1. Gerar e explicar o plano antes de escrever.
2. Preservar regras, fatos, comandos e customizações específicas deste repositório.
3. Adicionar, atualizar, renomear ou aposentar somente artefatos cuja propriedade seja comprovada pelo estado ou catálogo de compatibilidade.
4. Resolver conflitos por artefato; não usar substituição forçada global.
5. Validar o diff e verificar UTF-8/mojibake antes de concluir.
6. Persistir a seleção de integrações no estado para que um provider removido não reapareça na próxima atualização.

Não altere código de produção durante esta atualização.
