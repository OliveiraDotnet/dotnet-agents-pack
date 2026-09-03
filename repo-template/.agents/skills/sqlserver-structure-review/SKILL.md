---
name: sqlserver-structure-review
description: Read-only SQL Server review that reconstructs system behavior from schema, procedures, and .NET data access. Use to understand or review the database. Do not use to write migrations, DROP objects, or execute schema changes; use db-change-sqlserver after an approved plan.
---

# SQL Server structure review

Use only when the `sqlserver` profile is installed. Stay read-only.

1. Read applicable `AGENTS.md` and confirmed database notes in `docs/ai`.
2. Identify the schema source of truth and whether static files are enough.
3. Map tables, constraints, indexes, procs, views, functions, triggers, and C# consumers. Use `scripts/find-sqlserver-references.ps1` when the tree is large.
4. Reconstruct runtime behavior from the database: tenancy, audit, status, jobs, reports, and overlapping app versions. Read `references/sqlserver-system-understanding.md`.
5. If live metadata is required, use `scripts/sqlserver-access-preflight.ps1` once, then give the user `scripts/sqlserver-metadata-map.sql`. Do not ask for secrets or connect to production unless explicitly instructed.
6. Classify findings with evidence type (static, metadata-backed, runtime-backed) using `references/sqlserver-review-checklist.md` and `references/sqlserver-risk-patterns.md`.
7. Recommend the smallest safe next step. Do not emit destructive SQL. Hand approved change work to `db-change-sqlserver`.

Return scope, system map, dependency map, findings, application impact, validation still needed, and assumptions.
