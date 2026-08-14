---
name: maintain-agent-memory
description: Update durable repository guidance after a verified lesson, recurring bug, command discovery, or architecture decision. Use when a coding agent needs to keep AGENTS.md or docs/ai accurate without changing production code.
---

# Maintain repository memory

1. Classify the information as a persistent rule, project fact, recurring defect, architecture decision, data rule or temporary observation.
2. Require evidence: source file, test, issue, commit, CI result or human confirmation. Mark uncertain information as such instead of promoting it to a rule.
3. Store each fact once:
   - `AGENTS.md` for short always-relevant operating rules.
   - `docs/ai/project-map.md` for confirmed navigation and commands.
   - `architecture.md`, `database.md`, `domain-glossary.md` or `recurring-bugs.md` for their respective durable details.
4. Record last verification and source where the template provides fields.
5. Do not change production code or duplicate existing guidance.

End with the file changed, evidence, reason for placement and any expiration or revalidation need.
