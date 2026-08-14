---
name: update-agent-pack
description: Inspect and safely reconcile an existing repository installation with a newer Agent Pack, including added, changed, renamed, or retired skills, agents, prompts, and rules. Use when the user asks Codex, Claude, or Grok Build to check, update, migrate, synchronize, or repair an installed Agent Pack without losing repository-specific guidance or local customizations.
---

# Update Agent Pack

1. Confirm the repository root, read its applicable `AGENTS.md`, `CLAUDE.md`, `.grok/config.toml`, and `.agent-pack/state.txt` when present, then inspect `git status`. Do not modify production code.
2. Locate the latest trusted Agent Pack checkout from the user-provided path or `AGENT_PACK_HOME`. Do not download or guess a source.
3. Run the updater in check mode:
   - Windows: `powershell -ExecutionPolicy Bypass -File "$env:AGENT_PACK_HOME\scripts\update-agent-pack.ps1" -RepoPath . -Check`
   - Linux/macOS: `bash "$AGENT_PACK_HOME/scripts/update-agent-pack.sh" . --check`
   - When intentionally changing providers, pass `-Integration codex,grok` or `--integration codex,grok` (or the required explicit set). Codex is mandatory.
4. Review every planned action and its evidence. The deterministic updater owns file selection; do not invent extra files or profiles.
5. Resolve conflicts by artifact:
   - Preserve confirmed project facts, commands and rules.
   - For `merge` guidance, compare the installed baseline, the current repository file and the new pack source. Merge only the pack-owned change.
   - For a customized managed artifact, prefer an evidence-backed merge or detach it with `keep-local`. Use `accept-pack` only when replacing that specific artifact is intended.
   - Never delete a modified retired artifact until its useful local content has been migrated or explicitly discarded.
6. Rerun check mode with the explicit artifact resolutions. Apply only when the plan has no unresolved conflicts:
   - PowerShell: replace `-Check` with `-Apply`; pass `-AcceptMerge`, `-AcceptPack`, or `-KeepLocal` artifact IDs as needed. In a non-interactive agent shell, add `-Confirm:$false` only after the reviewed plan is conflict-free.
   - Shell: replace `--check` with `--apply`; repeat `--accept-merge`, `--accept-pack`, or `--keep-local` for the required IDs.
7. Inspect the resulting diff. Confirm that repository-owned files and production code were not changed unintentionally.
8. Run the pack validation requested by the plan and the installed `check-text-encoding` skill. Start a new Codex task, Claude session, or Grok session after persistent instructions change.

Never use the installer's broad force option as an update strategy. If the updater cannot prove ownership from state or a trusted compatibility catalog, preserve the file and report the required decision.
