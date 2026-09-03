---
name: db-change-sqlserver
description: Plan a SQL Server schema or data change with compatibility, rollback, and .NET consumer impact, then write scripts only after the user approves that plan. Use for requested database changes. Do not use for read-only understanding; use sqlserver-structure-review instead.
---

# SQL Server change

Use only when the `sqlserver` profile is installed.

1. Confirm the schema source of truth and the authorized target environment.
2. Map affected objects and .NET consumers before proposing SQL.
3. Classify each operation as additive, compatible, or destructive. Read `references/sqlserver-change-gates.md`.
4. Produce a plan only: objects, expand/contract sequence, data backfill, locks, rollback, and validation. Do not write `.sql`/migration files yet.
5. Stop for approval. Destructive operations (`DROP`, narrowing `ALTER`, unique indexes on dirty data, `NOT NULL` without backfill) require an explicit yes on that plan.
6. After approval, write the smallest idempotent script or migration the repository already uses. Do not execute it against any database unless the user names the environment and authorizes execution in this turn.
7. Update consumers only as required by the approved plan. Keep app and database overlapping versions compatible when releases can drift.

Return diagnosis, approved scope, script/migration (only after approval), data and application impact, rollback, and remaining validation.
