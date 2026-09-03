# .NET Agents Pack usage manual

## 1. Purpose

The pack installs guidance, specialized agents, skills, prompts, and technical memory so AI tools can work in modern, legacy, or mixed .NET repositories without inventing architecture, commands, or project rules.

Codex is required and is the control plane. Grok Build is an optional execution plane (bounded work, worktrees, parallelism). Claude Code remains optional compatibility.

You are the only decision authority:

1. **Gate 1:** non-trivial work starts only after you approve the plan, scope, risks, and validation.
2. The approved plan is the **execution envelope**.
3. **Gate 2:** after execution, Codex reviews the real diff. Commit, push, merge, deploy, release, production migration, and data changes need your explicit authorization.

## 2. What gets installed

| Path | Purpose | Version? |
|---|---|---|
| `AGENTS.md` | Short persistent rules. | Yes. |
| `.codex/agents/` | Codex specialists. | Yes. |
| `.agents/skills/` | Canonical skills. | Yes. |
| `prompts/` | Ready workflow prompts. | Yes. |
| `docs/ai/` | Confirmed project memory (seeds). | Yes, no secrets. |
| `CLAUDE.md`, `.claude/` | Claude bridge, only if requested. | Yes if Claude is in the project. |
| `.grok/` | Grok policy, agents, skills, only if requested. | Yes. |
| `.agent-pack/state.txt` | Version, profiles, integrations, baselines. | Yes. |

Do not version worktrees, sessions, transcripts, credentials, or caches.

## 3. Profiles

- `core`: always. Discovery, implementation, tests, review, memory, encoding checks.
- `web`: Razor, MVC, Blazor, Web Forms, .NET 3.1+ and classic Framework UI. Auto-selected when UI evidence exists.
- `sqlserver`: read-only system understanding, then planned DB changes after approval. Auto-selected when SQL evidence exists.
- `quality`: security, performance, release review. Never auto-selected.

Flutter was removed in 1.6.0. A later mobile pack can cover it. Unchanged 1.5.0 Flutter files that still match the catalog are retired on update.

## 4. New install

Point the installer at a Git root **or** a parent folder that contains Git repositories. It inspects first, then installs into each discovered root with the profiles that belong there.

```powershell
.\scripts\install-agent-pack.ps1 -RepoPath "C:\src" -DiscoverOnly
.\scripts\install-agent-pack.ps1 -RepoPath "C:\src"
.\scripts\install-agent-pack.ps1 -RepoPath "C:\src\MySystem" -Profile web,sqlserver -IncludeGrokBuild
```

```bash
bash ./scripts/install-agent-pack.sh /src --discover-only
bash ./scripts/install-agent-pack.sh /src
bash ./scripts/install-agent-pack.sh /src/my-system --profile web,sqlserver --include-grok-build
```

If `-Profile` / `--profile` is omitted, the installer uses existing `.agent-pack/state.txt` when present; otherwise it detects `web` and `sqlserver` from the repository. Quality, Claude, and Grok are never implied.

Then bootstrap with `prompts/00-bootstrap-repo.md` or `$bootstrap-dotnet-repo`. `[UNVERIFIED]` is not a fact.

## 5. Updating a 1.5.0 install

Do not re-run the installer with `Force`. Use the updater:

```powershell
.\scripts\update-agent-pack.ps1 -RepoPath "C:\src\MySystem" -Check
.\scripts\update-agent-pack.ps1 -RepoPath "C:\src\MySystem" -Apply
```

A conflict blocks the whole apply. Resolve per artifact with `AcceptMerge`, `AcceptPack`, or `KeepLocal`. `docs/ai` stays repository-owned. New profiles are not installed just because 1.6 contains them.

## 6. Daily skills

| Work | Prompt | Skill |
|---|---|---|
| Bootstrap / workspace inspect | `00-bootstrap-repo.md` | `$bootstrap-dotnet-repo` |
| Bugfix | `01-bugfix.md` | `$bugfix-dotnet` |
| Feature | `02-feature-slice.md` | `$feature-slice-dotnet` |
| Understand SQL Server | — | `$sqlserver-structure-review` |
| Change SQL Server | `03-db-change.md` | `$db-change-sqlserver` |
| .NET web UI | — | `$web-dotnet` |
| xUnit layer | — | `$dotnet-xunit-tests` |
| Review | `04-pr-review.md` | `$pr-review-dotnet` |
| Legacy refactor | `05-refactor-legado.md` | `$legacy-refactor-dotnet` |
| Memory | `06-update-agent-memory.md` | `$maintain-agent-memory` |
| Read-only investigation | `07-investigate-only.md` | `repo_explorer` |
| Pack update | `08-update-agent-pack.md` | `$update-agent-pack` |

`$sqlserver-structure-review` never writes the database. `$db-change-sqlserver` produces a plan first; destructive SQL waits for your approval; execution against a real database needs a named environment and explicit authorization.

## 7. Codex + Grok

Non-trivial work: plan → Gate 1 → work order → Grok worktree → Codex reviews the real diff → Gate 2. Grok must not commit, push, deploy, migrate, or apply onto the main checkout.

## 8. Hygiene

- No secrets in prompts, memory, or logs.
- Do not invent build or test commands.
- Run `check-text-encoding` after text edits.
- Update `docs/ai` only with durable, dated, secret-free facts.
