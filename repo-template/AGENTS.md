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
- Classify a change as trivial only when it stays in one area and does not change public contracts, data, authorization, production dependencies, or unconfirmed commands. Otherwise present a plan and wait for Gate 1 approval.
- Use `sqlserver-structure-review` for read-only database understanding and `db-change-sqlserver` only after an approved schema or data plan.
- Use `web-dotnet` / `frontend_web` for UI that lives in the .NET web project (Razor, MVC, Blazor, Web Forms, app JavaScript).
- Do not invent build, test, run or deployment commands. Record only commands confirmed by repository evidence.
- Preserve observed conventions and public behavior. Keep bugfixes and refactors separate.
- Keep changes limited to the requested scope; explain impacts to contracts, data, configuration and users.
- Do not expose secrets, connection strings, credentials, personal data or sensitive payloads.
- Do not run destructive commands, migrations, database changes or deploys without explicit authorization.
- Before completion, scan changed text files for invalid UTF-8 or likely mojibake with the installed `check-text-encoding` skill. Confirm suspicious text in context; never hide corruption by stripping accents or blindly transcoding a whole file.
- For a bug, reproduce or characterize the failure before the fix when viable, then add the smallest relevant regression coverage.
- If automation is unavailable, provide a controlled manual validation scenario with input, action and expected result.

## Context and delegation

- Use the smallest sufficient context: search before opening files, read only relevant sections, avoid rereading unchanged content and summarize large outputs instead of copying them into the conversation. Expand context when uncertainty or risk justifies it; never trade correctness, security or necessary validation for token savings.
- Read `docs/ai` only when it is relevant to the task. Treat documents without source and verification date, or whose solution/CI fingerprint changed, as hypotheses and revalidate with `maintain-agent-memory`.
- Use `repo_explorer` for bounded read-only mapping. Add at most the specialist justified by the detected stack or diff.
- Core agents: `repo_explorer`, `dotnet_implementer`, `test_guardian` and `change_reviewer`.
- Optional profiles add `frontend_web`, `database_sqlserver` or the quality reviewers. Do not request every reviewer by default.

## Codex and Grok Build collaboration

- The user is the sole decision authority. Codex and Grok Build may analyze, challenge assumptions, recommend and execute, but neither may approve material choices or final integration on the user's behalf.
- Codex is the control plane for requirements, architecture, design, risk analysis, review and validation. Grok Build is the execution plane for bounded work that benefits from parallelism.
- Gate 1: before non-trivial implementation or delegation, Codex must present a plan with scope, risks and validation and obtain explicit user approval. The approved plan is the execution envelope.
- Within that envelope, agents may make trivial mechanical choices. A material deviation in scope, behavior, architecture, contracts, dependencies, security, data or validation must stop and return to the user with evidence, options, trade-offs and a recommendation.
- Before delegating, Codex must issue the complete work order required by the installed `delegate-to-grok-build` skill, including the actual human-approved scope and decision boundaries.
- Use Grok Build subagents only for independent workstreams. Any subagent that edits files must use native `worktree` isolation; read-only exploration may share the parent context.
- Grok Build must not commit, push, deploy, run migrations, alter production data, apply worktree changes to the main checkout or broaden the agreed scope.
- Grok Build must return a structured status, worktree path, changed files, technical decisions, validation evidence, deviations and risks. `BLOCKED_BY_DECISION` is a normal return state, not a failure to hide or work around.
- Codex must inspect the complete worktree diff, check scope and security, and independently rerun relevant validation. A Grok summary is never a substitute for the actual diff.
- Gate 2: Codex may recommend `ready for manual validation`, `revise`, `discard` or `user decision required`. Commit, push, merge, deploy, release, production migration or data change requires the user's explicit manual approval and authorization.
- Keep transient handoff data, Grok sessions and worktrees outside the repository. Store only durable, verified project knowledge in tracked files.

## Definition of done

- Root cause or change motivation is identified.
- Scope, contracts, data and authorization impacts are assessed.
- Relevant confirmed validation command ran, or the precise blocker is documented.
- Changed text files pass the encoding check, or each remaining finding is documented as intentional.
- Remaining risks and manual validation are stated in the final response.
