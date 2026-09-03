---
name: agents-md-generator
description: Create or improve a short pack-format AGENTS.md from repository evidence. Use when the user wants AGENTS.md created or rewritten. Do not use for full bootstrap, docs/ai memory, or inventing commands; use bootstrap-dotnet-repo and maintain-agent-memory for those.
---

# AGENTS.md Generator

## Overview

Create or improve `AGENTS.md` files from the actual repository shape. Inspect first, preserve useful project-specific guidance, and avoid inventing commands or architecture.

## Workflow

1. Read any existing `AGENTS.md` and `AGENTS.override.md` files that apply to the target path.
2. Inspect the workspace before writing: Git roots, `README*`, `docs/`, solution/project files, package manifests, CI files, Docker files, and major folders.
3. Classify the workspace as one repository, a monorepo, multiple independent repositories, or a normal folder without Git metadata.
4. Infer stack, architecture, commands, conventions, and dominant documentation language only from real files.
5. Decide the target: root `AGENTS.md` for one repository, root plus selective nested files for monorepos, per-repository files for multiple independent repositories, or no write until the user confirms a target.
6. Propose the action before editing when the target is ambiguous or multiple repositories are detected.
7. Write a concise, practical `AGENTS.md` with TODO markers where facts cannot be confirmed.
8. Report workspace detection, existing status, proposed action, files changed, assumptions or TODOs, and final summary.

For the detailed inspection checklist, read `references/agents-md-checklist.md` before creating or materially rewriting an `AGENTS.md`.

## Workspace Detection

Use repository evidence, not folder names alone.

- Use `.git` directories or `git rev-parse --show-toplevel` to identify repository boundaries.
- Treat a root with one `.git` plus several apps/packages as a possible monorepo.
- Treat a folder containing multiple child `.git` directories as multiple independent repositories.
- Treat a folder without Git metadata as a normal folder unless another clear workspace signal exists.

Do not create a parent-level `AGENTS.md` for multiple independent repositories unless the user explicitly requests parent-folder guidance.

## Existing AGENTS.md Handling

When `AGENTS.md` exists:

- Read it completely before editing.
- Preserve useful instructions, project-specific rules, and known commands.
- Remove or rewrite duplicated, vague, obsolete, unsafe, or contradictory guidance.
- Avoid deleting project rules unless clearly wrong, duplicated, or unsafe.
- Explain what changed and why.

When `AGENTS.md` does not exist:

- Create a focused file based on inspected repository facts.
- Include TODO markers for unknown commands, unclear conventions, or unverified architecture.
- Keep generic best-practice filler out.

## Content Standard

Match the installed Agent Pack `AGENTS.md` template. Keep the file short and always-relevant:

- Facts to confirm, or confirmed facts after bootstrap
- Working rules
- Context and delegation
- Codex and Grok Build collaboration when that integration is present
- Definition of done

Put architecture, commands, database notes, and domain vocabulary in `docs/ai`, not in long `AGENTS.md` sections. Do not add generic coding-standards filler. Include database rules in `AGENTS.md` only when they are durable operating constraints confirmed by the repository.

## Safety Rules

- Do not modify application source code while creating or improving `AGENTS.md`.
- Do not add dependencies.
- Do not modify CI/CD unless explicitly requested.
- Do not include secrets, tokens, real connection strings, private keys, or personal data.
- Do not invent commands. Use TODO markers when commands are not confirmed by docs, scripts, project files, or CI.
- Keep public contracts stable unless the user explicitly asks to change them.

## Language

Write `AGENTS.md` in the dominant language used by existing technical documentation. Prefer English for English documentation, Portuguese for Portuguese documentation, and the language used by existing technical docs when the repository is mixed.

## Output

After work, report:

1. Workspace detection
2. Existing `AGENTS.md` status
3. Proposed or completed action
4. Files created or changed
5. Important assumptions or TODOs
6. Final `AGENTS.md` summary
