# Update the Agent Pack in this repository

Use `$update-agent-pack` in Codex, `/update-agent-pack` in Claude Code, or the native `update-agent-pack` skill in Grok Build.

If the goal is to remove Claude and adopt Codex + Grok, start with `prompts/09-migrate-claude-to-codex-grok.md`.

## Trusted source

- Path to the updated Agent Pack or `AGENT_PACK_HOME`:
- Desired integrations if they must change (example: `codex,grok`):

## Goal

1. Generate and explain the plan before writing.
2. Preserve this repository's rules, facts, commands, and customizations.
3. Add, update, rename, or retire only artifacts whose ownership is proven by state or the compatibility catalog.
4. Resolve conflicts per artifact; do not force a global replace.
5. Validate the diff and check UTF-8/mojibake before finishing.
6. Persist the integration selection in state so a removed provider does not return on the next update.

Do not change production code during this update.
