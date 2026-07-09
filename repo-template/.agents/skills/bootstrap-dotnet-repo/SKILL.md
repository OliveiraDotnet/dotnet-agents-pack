---
name: bootstrap-dotnet-repo
description: Inspect and bootstrap a .NET repository without changing production code. Use when Codex needs to discover repository shape, SDK-style or classic projects, confirmed commands, tests, data access, and applicable pack profiles before work begins.
---

# Bootstrap a .NET repository

1. Read applicable `AGENTS.md` files and classify the workspace: one repository, monorepo, multiple repositories, or non-Git folder.
2. Run the local inspection script without build, restore, test, database, network, or code changes:
   - Windows: `powershell -ExecutionPolicy Bypass -File .agents/skills/bootstrap-dotnet-repo/scripts/inspect-dotnet-repo.ps1`
   - Linux/macOS: `bash .agents/skills/bootstrap-dotnet-repo/scripts/inspect-dotnet-repo.sh`
3. Verify the reported facts against solution/project files, CI, scripts, README and existing tests. Treat detection as evidence, not proof.
4. Update `docs/ai/project-map.md`, `architecture.md`, `database.md`, `domain-glossary.md` and `runbook.md` only with confirmed facts. Include source path, commit or date, and confidence.
5. Replace `[UNVERIFIED]` items in the root `AGENTS.md` only with durable, always-relevant project rules. Do not add generic theory or commands inferred by guesswork.
6. Recommend optional profiles only when their evidence exists: `web`, `sqlserver`, or `quality`.
7. End without changing production code. Ask the user to start a new task so the updated instructions load.

Use one `repo_explorer` only when the initial evidence leaves a bounded question unanswered. Do not fan out reviewers during bootstrap.
