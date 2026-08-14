# Migrate this repository from Claude to Codex + Grok Build

Act as the migration coordinator. I am the sole decision authority. Codex is the control plane for discovery, design, review, judgment and independent validation; Grok Build is the execution plane for bounded parallel work in isolated native worktrees.

## Safety and scope

- Start with read-only inspection. Identify the Git root, applicable `AGENTS.md`, current Agent Pack version/state, selected profiles, `CLAUDE.md`, `.claude/`, `.grok/`, `.agents/skills`, `.codex/agents`, `.gitignore`, relevant docs and the current working-tree status.
- Treat existing files as project-owned until Agent Pack metadata or exact content proves otherwise. Do not delete custom Claude rules, skills, agents, hooks, MCP configuration or commands before preserving useful behavior in the native destination.
- Never expose secrets. Do not commit, push, deploy, run migrations, modify production data or perform destructive Git cleanup.
- Use `<AGENT_PACK_ROOT>` as the local Agent Pack checkout. If it cannot be resolved safely, stop and ask for its path.
- Gate 1 applies: after the read-only inventory, present the proposed migration scope, preserved content, removals, risks and validations. Do not modify or delegate until I explicitly approve that plan.

## Migration

1. Produce a concise inventory classifying each Claude artifact as Agent Pack-managed, custom and portable, local-only, obsolete or uncertain.
2. Merge unique durable repository guidance from `CLAUDE.md`, `.claude/rules/` and other instruction files into the applicable `AGENTS.md`. Remove duplication and Claude-only syntax. Preserve scoped rules in nested `AGENTS.md` files only when the repository structure justifies them.
3. Migrate custom reusable skills to `.grok/skills/`, custom agent definitions to `.grok/agents/`, and necessary project MCP or permission configuration to `.grok/config.toml`. Do not copy user credentials or machine-local settings into the repository.
4. Preview the Agent Pack reconciliation with the repository's actual profiles and integrations restricted to `codex,grok`:

   PowerShell:

   ```powershell
   & "<AGENT_PACK_ROOT>\scripts\update-agent-pack.ps1" -RepoPath . -Integration codex,grok -Check
   ```

   Git Bash / WSL:

   ```bash
   bash "<AGENT_PACK_ROOT>/scripts/update-agent-pack.sh" . --integration codex,grok --check
   ```

   For a fresh repository with no trusted Agent Pack installation, preview and then run the normal installer with `-IncludeGrokBuild` or `--include-grok-build` and the detected profiles instead.
5. Review every planned add, update, retirement and conflict. Resolve custom merge-owned content in `AGENTS.md` and `.grok/config.toml` deliberately. Treat the approved plan as the execution envelope and stop for my decision before any material deviation. Apply only after the preview is correct.
6. Remove remaining `CLAUDE.md`, `.claude/` content and Claude-specific ignore rules only after their useful behavior is migrated or explicitly rejected. Do not remove unrelated files merely because their names mention Claude.
7. Do not add `.ai-collab/`, `GROK.md`, repository-local worktree directories, session transcripts, credentials or broad `.grok/` ignore rules. Grok's native sessions and worktrees belong under the user's Grok home; tracked `.grok/agents`, `.grok/skills` and `.grok/config.toml` are intentional project configuration.

## Verification

- Run the Agent Pack validators or the repository's installed update check.
- If Grok Build is installed and authenticated, run `grok inspect` and verify that it finds `AGENTS.md`, expected `.grok/skills`, agents and project policy. Do not treat missing CLI authentication as a repository failure; report it precisely.
- Run relevant confirmed repository validation and the text-encoding check.
- Review the final Git diff and confirm there are no Claude artifacts, secrets, runtime sessions, worktrees, generated handoff files or unrelated changes.
- Gate 2 applies: present the reviewed result and a manual validation scenario. Do not commit, push, merge, deploy, release, run a production migration or alter data without my separate explicit authorization.

Return the inventory, approved scope, migrations performed, files removed, files added or changed, commands and results, unresolved conflicts, limitations, manual validation steps and the exact next command for the first Codex-to-Grok delegated task.
