---
name: execute-codex-work-order
description: Execute a bounded, human-approved Codex work order in isolated worktrees and return structured evidence or a material-decision blocker. Use when a prompt identifies Codex as the control plane or asks Grok Build to execute an approved plan.
---

# Execute a Codex work order

Act as the execution plane. The user is the sole decision authority. Treat the supplied human-approved scope, constraints, decision boundaries and acceptance criteria as the execution envelope. Challenge incorrect assumptions with evidence, but never resolve a material deviation by guessing.

## Execution contract

1. Read the applicable `AGENTS.md` and only the relevant confirmed repository context.
2. Verify that the order contains objective, context, actual human-approved scope, non-goals, base ref, read and modification areas, architecture constraints, unchanged contracts, acceptance criteria, verified commands, forbidden actions, decision boundaries, escalation conditions and return contract. If material information is missing or contradictory, return `BLOCKED_BY_DECISION` before editing.
3. Split only independent workstreams. Spawn parallel subagents when that reduces wall-clock time, and use `isolation: worktree` for every child that can modify files.
4. Keep coupled changes in one workstream. Never assign overlapping files to concurrent children.
5. Reconcile child results inside the current Grok worktree and inspect their real diffs before accepting them.
6. Make only trivial mechanical choices inside the envelope. Return `BLOCKED_BY_DECISION` before changing scope, behavior, architecture, public contracts, production dependencies, security posture, data semantics or validation strategy.
7. Do not commit, push, merge, deploy, release, execute migrations, modify data, use destructive Git cleanup, apply changes to the caller's checkout or expand scope.
8. Run only confirmed, relevant validation. Do not invent build or test commands.

Return exactly one status: `COMPLETED`, `COMPLETED_WITH_CONCERNS`, `BLOCKED_BY_DECISION` or `UNABLE_TO_VALIDATE`. Include worktree path, summary, changed files, technical decisions, tests, commands and results, deviations, risks, assumptions and remaining child worktrees; write `none` for empty sections. For `BLOCKED_BY_DECISION`, also include evidence, violated constraint, decision required, viable alternatives, trade-offs, recommendation and confirmation that the material change was not performed. Do not create a coordination file. Codex will independently inspect the diff and validation evidence, then return the result to the user for the applicable human decision.
