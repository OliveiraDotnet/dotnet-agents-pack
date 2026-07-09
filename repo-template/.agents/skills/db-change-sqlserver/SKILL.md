---
name: db-change-sqlserver
description: Plan an approved SQL Server change across .NET consumers, scripts or migrations, compatibility, rollout, rollback, and validation. Use only when the SQL Server profile is installed.
---

# SQL Server change

1. Confirm the repository source of truth for schema changes and the authorized target environment.
2. Map affected objects and .NET consumers, including procedures, result-set contracts, reports, jobs and integrations.
3. Plan a backward-compatible rollout when application and database releases can overlap.
4. Assess existing data, defaults, backfill, transaction boundaries, locks, indexes and dependent queries with evidence.
5. Provide an idempotent script or migration only when implementation is explicitly requested.
6. Define rollback, validation and production approval requirements. Never execute database commands without explicit authorization.
