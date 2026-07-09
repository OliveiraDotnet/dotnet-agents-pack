# Project guidance

> Este arquivo é um template ativo. Texto marcado como `[UNVERIFIED]` não é fato do repositório e não deve orientar implementação. Execute `$bootstrap-dotnet-repo` antes da primeira alteração relevante e inicie uma nova tarefa depois dele.

## Facts to confirm

- Repository shape: `[UNVERIFIED]`
- Solution and project files: `[UNVERIFIED]`
- Target frameworks and toolchain: `[UNVERIFIED]`
- Confirmed build, test and run commands: `[UNVERIFIED]`
- Test strategy and CI evidence: `[UNVERIFIED]`
- Data access, external integrations and authorization boundaries: `[UNVERIFIED]`

Use `docs/ai/project-map.md` for the latest confirmed map. Prefer evidence in project files, CI, scripts and existing tests over this template.

## Working rules

- Inspect the repository shape and the affected execution path before changing code.
- Do not invent build, test, run or deployment commands. Record only commands confirmed by repository evidence.
- Preserve observed conventions and public behavior. Keep bugfixes and refactors separate.
- Keep changes limited to the requested scope; explain impacts to contracts, data, configuration and users.
- Do not expose secrets, connection strings, credentials, personal data or sensitive payloads.
- Do not run destructive commands, migrations, database changes or deploys without explicit authorization.
- For a bug, reproduce or characterize the failure before the fix when viable, then add the smallest relevant regression coverage.
- If automation is unavailable, provide a controlled manual validation scenario with input, action and expected result.

## Context and delegation

- Read `docs/ai` only when it is relevant to the task. Treat documents without source and verification date as hypotheses.
- Use `repo_explorer` for bounded read-only mapping. Add at most the specialist justified by the detected stack or diff.
- Core agents: `repo_explorer`, `dotnet_implementer`, `test_guardian` and `change_reviewer`.
- Optional profiles add `frontend_web`, `database_sqlserver` or the quality reviewers. Do not request every reviewer by default.

## Definition of done

- Root cause or change motivation is identified.
- Scope, contracts, data and authorization impacts are assessed.
- Relevant confirmed validation command ran, or the precise blocker is documented.
- Remaining risks and manual validation are stated in the final response.
