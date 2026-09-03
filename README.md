# .NET Agents Pack

Generic pack that steers coding agents in modern and legacy .NET repositories without inventing architecture, commands, or personal preferences. Codex is the default integration and control plane. Claude Code and Grok Build are independent opt-in integrations.

It installs a small core for bootstrap, bugfix, feature work, refactoring, review, `AGENTS.md` generation, and xUnit tests. Optional profiles add web UI, SQL Server, and evidence-based quality review.

Version 1.6.0 inspects the workspace before it copies files: a Git root, a parent folder of independent repositories, or a non-Git folder. It suggests `web` and `sqlserver` from repository evidence. It does not install Flutter; a later mobile pack can cover that.

## Components

| Component | Install | Use |
|---|---|---|
| `core` | always | Repository context, .NET discovery, explore/implement/test/review agents, and core skills. |
| `web` | optional / auto when UI evidence exists | Razor, MVC, Blazor, Web Forms, and app JavaScript, including .NET 3.1+ and classic Framework. |
| `sqlserver` | optional / auto when SQL evidence exists | Read-only system understanding from SQL Server, then planned changes only after approval. |
| `quality` | optional, never auto | Evidence-based security, performance, and release review. |

`pack-manifest.txt` is the source of truth for installed files. `pack-artifacts.txt` records stable ids and ownership. `pack-version.txt` is the pack version. `compat/releases/` stores trusted fingerprints so 1.5.0 (and earlier) installs can update without losing project-owned files.

The installer never copies a profile that was not selected or detected. An upgrade never installs a profile that the destination did not already have.

## Install

Run from the pack root. Point at a Git root **or** a workspace folder that contains Git repositories.

```powershell
# Inspect a workspace with more than one repository, then install into each Git root
.\scripts\install-agent-pack.ps1 -RepoPath "C:\src" -DiscoverOnly
.\scripts\install-agent-pack.ps1 -RepoPath "C:\src"

# Explicit profiles (skips auto-detection)
.\scripts\install-agent-pack.ps1 -RepoPath "C:\src\MySystem" -Profile web,sqlserver

# Preview without writing
.\scripts\install-agent-pack.ps1 -RepoPath "C:\src\MySystem" -Profile quality -DryRun

# Codex + Grok Build
.\scripts\install-agent-pack.ps1 -RepoPath "C:\src\MySystem" -IncludeGrokBuild
```

```bash
bash ./scripts/install-agent-pack.sh /src --discover-only
bash ./scripts/install-agent-pack.sh /src
bash ./scripts/install-agent-pack.sh /src/my-system --profile web,sqlserver
bash ./scripts/install-agent-pack.sh /src/my-system --profile quality --dry-run
bash ./scripts/install-agent-pack.sh /src/my-system --include-grok-build
```

Without integration flags, only Codex is installed. `IncludeClaude` / `--include-claude` adds the Claude bridge. `IncludeGrokBuild` / `--include-grok-build` adds Grok project files. New installs write `.agent-pack/state.txt` so later updates do not depend only on fingerprints.

Use `-AllowNonGit` / `--allow-non-git` only for a folder that is intentionally not Git. `-InstallGlobal` / `--install-global` copies the optional personal Codex example; it is not installed by default.

## Safe update of an existing 1.5.0 install

Use the updater, not the installer's `Force` switch.

```powershell
.\scripts\update-agent-pack.ps1 -RepoPath "C:\src\MySystem" -Check
.\scripts\update-agent-pack.ps1 -RepoPath "C:\src\MySystem" -Apply
```

```bash
bash ./scripts/update-agent-pack.sh /src/my-system --check
bash ./scripts/update-agent-pack.sh /src/my-system --apply
```

Unchanged Flutter files from 1.5.0 are retired automatically when they still match the 1.5.0 catalog. Customized Flutter files require `AcceptPack` or `KeepLocal`. `docs/ai` stays repository-owned. `AGENTS.md` uses merge ownership.

## First use

Open the installed repository and run `prompts/00-bootstrap-repo.md` or `$bootstrap-dotnet-repo`. The skill inspects without changing production code, then fills confirmed facts. Start a new task afterward so persistent instructions reload.

For SQL Server, `$sqlserver-structure-review` is read-only. `$db-change-sqlserver` writes scripts only after you approve the plan. For .NET UI, use `$web-dotnet`.

See the [usage manual](MANUAL_DE_USO.md), [detailed instructions](INSTRUCOES_DETALHADAS.md), [changelog](CHANGELOG.md), and the official Codex, Claude, and Grok Build source notes before rolling the pack out widely.
