---
name: delegate-to-grok-build
description: Govern bounded implementation or validation delegated from Codex to Grok Build through human-approved plans, explicit work orders, isolated worktrees, structured escalation and independent diff review. Use when the user requests Codex and Grok Build collaboration, parallel implementation, or Grok worktree execution.
---

# Delegate to Grok Build

Use Codex as the control plane and Grok Build as an execution accelerator. The user is the sole decision authority. Codex owns analysis, design, delegation, review and recommendations; it never converts its recommendation into human approval.

## Human gates

1. **Gate 1 — plan approval:** Before non-trivial implementation or delegation, present a concise plan containing the evidence, proposed scope, likely files, material risks and validation strategy. Delegate only after explicit user approval.
2. Treat the approved plan as the execution envelope. Make trivial mechanical choices inside it, but do not infer approval for material changes.
3. **Gate 2 — manual approval:** After independent review, present the result and a controlled manual validation handoff. Commit, push, merge, deploy, release, production migration and data changes require explicit user authorization after that validation.

## Preconditions

1. Read the applicable `AGENTS.md` and inspect the affected repository path.
2. Confirm the repository is Git-backed and identify the base ref and current working-tree state.
3. Confirm `grok version` and `grok inspect` succeed. If the CLI or authentication is unavailable, stop with the exact blocker.
4. Do not send secrets, credentials, private keys, production data or unrelated repository content to Grok Build.
5. For write delegation, prefer a clean main checkout. If it is dirty, do not delegate overlapping files; explain the risk and obtain direction before changing the workflow.

## Decide whether to delegate

Delegate only work that is bounded and can be judged against explicit acceptance criteria, such as independent implementation slices, test additions, mechanical migrations or focused diagnostics. Keep ambiguous requirements, material architecture or security decisions and final review in Codex, and return material choices to the user.

Parallelize only independent workstreams. Do not assign two agents to the same files or tightly coupled contracts.

## Work order

Give Grok Build a self-contained work order with these exact fields:

- **Objective:** observable result to produce.
- **Context:** only relevant confirmed facts and evidence.
- **Human-approved scope:** the actual approved scope, quoted or faithfully summarized; never a boolean such as `approved: true`.
- **Non-goals:** behavior and areas intentionally excluded.
- **Base ref:** explicit clean ref used to create the isolated worktree.
- **Allowed read areas:** paths or subsystems Grok may inspect for necessary context.
- **Allowed modification areas:** exact paths or subsystems Grok may change.
- **Architecture constraints:** dependency direction and design invariants that must remain true.
- **Contracts unchanged:** APIs, schemas, behavior, configuration or other contracts that cannot change.
- **Acceptance criteria:** observable conditions for completion.
- **Verified commands:** exact validation commands confirmed from repository evidence; state `none confirmed` when applicable.
- **Forbidden actions:** no commit, push, merge, deploy, release, migration, production/data change, destructive cleanup, scope expansion or apply to the caller's checkout.
- **Decision boundaries:** material choices Grok must not make autonomously.
- **Escalation conditions:** events that require `BLOCKED_BY_DECISION`.
- **Return contract:** the structured result defined below.

Tell the Grok parent to use its native subagents in parallel only when tasks are independent, and to request `isolation: worktree` for every modifying child. The Grok parent may reconcile those children inside its own isolated checkout, but it must not land changes into the Codex checkout.

## Invocation

Prefer a named isolated session based on an explicit clean ref:

```text
grok --no-auto-update --worktree=<task-label> --ref <base-ref> -p "<work-order>" --output-format json
```

Use `--worktree=<name>` with `=` so the first prompt is not parsed as the worktree name. Do not use `--always-approve` or `--yolo` by default. For headless automation, use `dontAsk` with narrowly scoped `--allow` rules for the confirmed reads, edits and validation commands; retain explicit deny rules for commit, push and destructive Git operations. If safe permissions cannot be expressed, use the interactive TUI and keep human approval enabled.

## Review and landing

1. Resolve the returned worktree path from the result or `grok worktree list` / `grok worktree show`.
2. Inspect `git status`, the complete diff, `git diff --check`, new files and validation output inside that worktree. Never accept only the model summary.
3. Independently verify claims, decisions, commands and results. Reject or send back changes that exceed scope, weaken security, alter contracts without approval, skip required tests or include generated/runtime artifacts.
4. If applying the reviewed diff to the caller's checkout is within the approved execution envelope, use a preflighted temporary patch or another explicit reviewed mechanism; this does not authorize a commit or push.
5. Rerun relevant validation in the destination checkout and review its final diff.
6. Present one recommendation only: `READY_FOR_MANUAL_VALIDATION`, `REVISE`, `DISCARD` or `USER_DECISION_REQUIRED`. Include manual validation steps with input, action and expected result when applicable.
7. Wait for explicit Gate 2 approval before any human-authorized action. Never describe a Codex recommendation as a final decision.
8. Preview cleanup with `grok worktree rm <id> --dry-run`. Remove the worktree only after changes are safely applied, intentionally discarded or the user authorizes cleanup.

## Material decisions and escalation

Require Grok to challenge incorrect assumptions with evidence. It may resolve trivial implementation details inside the envelope, but must return `BLOCKED_BY_DECISION` before changing scope, externally visible behavior, architecture, public contracts, production dependencies, security posture, data semantics or the approved validation strategy.

For a blocker, require: evidence, violated constraint, decision required, viable alternatives, trade-offs, recommendation and explicit confirmation that the material change was not performed. Do not create a coordination file in the repository.

## Grok return contract

Require exactly one status:

- `COMPLETED`
- `COMPLETED_WITH_CONCERNS`
- `BLOCKED_BY_DECISION`
- `UNABLE_TO_VALIDATE`

Require these fields: status, worktree path, summary, changed files, technical decisions, tests, commands and results, deviations, risks, assumptions and remaining child worktrees. For `BLOCKED_BY_DECISION`, also require every blocker field from the escalation section. Empty sections must say `none`.

## Final report

Report what the user approved, what Grok executed, what Codex independently verified, worktrees used, files applied, validation results, rejected changes, residual risks, manual validation steps and the current recommendation. Clearly identify every action still awaiting user authorization.
