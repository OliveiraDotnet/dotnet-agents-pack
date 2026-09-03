# SQL Server change gates

Do not write SQL, migrations, or database commands until the plan is approved. Never execute against a real database in the same turn as the plan.

## Classify every object change

- **Additive:** new nullable column, new table unused by current app, new index that does not enforce uniqueness on existing dirty data.
- **Compatible:** expand-only type change, new proc version, backfill that keeps old readers working.
- **Destructive:** `DROP` of table/column/index/constraint, shortening a type, `NOT NULL` without default and backfill, unique index on unclean data, rename, `UPDATE`/`DELETE` of production-like data.

Destructive work requires an impact map and explicit user approval of that plan. Stop otherwise.

## Plan contents (required)

- Source of truth for schema (SQL project, EF migrations, scripts, mixed).
- Target environment (local/dev/test only unless production is explicitly authorized).
- Objects touched and .NET consumers (Dapper, EF, `FromSql*`, reports, jobs).
- Existing data, defaults, backfill, and expand/contract sequence.
- Locks, index rebuilds, and rollback.
- Validation in a non-production environment.

## Forbidden without a cited approved plan

- `DROP`, `TRUNCATE`, `ALTER` that removes or narrows a column.
- Dropping or disabling an index, trigger, or constraint.
- Running the script against any database.
- Combining a refactor of C# mapping with an unapproved schema drop.

## After approval

- Implement only the approved objects.
- Prefer idempotent scripts (`IF EXISTS` / `CREATE OR ALTER`) when the repository already uses them.
- Do not add `NOLOCK` or speculative indexes.
- Return the script or migration, consumer updates, rollback, and the exact validation still required.
