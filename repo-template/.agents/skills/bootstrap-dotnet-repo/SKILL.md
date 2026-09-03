---
name: bootstrap-dotnet-repo
description: Inspect and bootstrap a .NET workspace without changing production code. Use for first-run discovery of one Git repository, a parent folder of independent repositories, or a monorepo. Do not use to rewrite an already bootstrapped AGENTS.md; use agents-md-generator for that short file only.
---

# Bootstrap a .NET repository

1. Classify the workspace from Git evidence: one repository, one Git root with multiple apps (monorepo), a parent folder of independent Git repositories, or a non-Git folder.
2. If independent repositories are found, list each Git root and inspect it separately. Do not write a parent-level `AGENTS.md` unless the user explicitly wants workspace-level notes.
3. Run the local inspection script without build, restore, test, database, network, or code changes:
   - Windows: `powershell -ExecutionPolicy Bypass -File .agents/skills/bootstrap-dotnet-repo/scripts/inspect-dotnet-repo.ps1`
   - Linux/macOS: `bash .agents/skills/bootstrap-dotnet-repo/scripts/inspect-dotnet-repo.sh`
4. Verify reported facts against project files, CI, scripts, README and tests. Treat detection as evidence, not proof.
5. Recommend only real pack profiles with evidence: `web` and `sqlserver`. Never invent `legacy-framework` or auto-select `quality`.
6. Update `docs/ai` and replace `[UNVERIFIED]` items in `AGENTS.md` only with confirmed, always-relevant rules. Keep `AGENTS.md` short; put details in `docs/ai`. Use `agents-md-generator` only for that short persistent shell.
7. End without changing production code. Ask the user to start a new task so updated instructions load.

Use one `repo_explorer` only when a bounded question remains. Do not fan out reviewers during bootstrap.
