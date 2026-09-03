# AGENTS.md Checklist

## Inspect

- Check `.git` directories and `git rev-parse --show-toplevel`.
- Locate `AGENTS.md` and `AGENTS.override.md`.
- Locate `README*`, `docs/`, `.github/workflows/`, and pipeline files.
- Locate `.sln`, `.csproj`, `package.json`, Docker files, `global.json`, `Directory.Build.props`, `Directory.Packages.props`, and `.editorconfig`.
- Locate important folders: `src/`, `tests/`, `test/`, `spec/`, `infra/`, `frontend/`, `backend/`, `api/`, `web/`, and `mobile/`.
- Infer commands from docs, scripts, project files, and CI. Use TODO when not confirmed.

## Decide Placement

- One repository: create or improve root `AGENTS.md`.
- Monorepo: create or improve root `AGENTS.md`; add nested files only for areas with genuinely different rules.
- Multiple independent repositories: list repositories and ask for a target unless the user explicitly asked to apply to all.
- Normal folder: create guidance only if the user wants folder-level Codex instructions.

## Preserve Existing Guidance

- Keep accurate project-specific rules.
- Keep confirmed commands.
- Merge duplicated sections.
- Remove obsolete or unsafe instructions.
- Mark uncertainty explicitly.

## Include When Relevant

- Confirmed facts or `[UNVERIFIED]` placeholders.
- Short working rules that always apply.
- Context, delegation, and definition of done.
- Durable database or security operating constraints only when confirmed.

Put detailed maps, commands, and architecture in `docs/ai`. Do not generate a long coding-standards document as `AGENTS.md`.

## Avoid

- Generic best-practice filler.
- Invented commands.
- Unverified architecture claims.
- Secrets or personal data.
- Unrelated source, dependency, CI, or formatting changes.
