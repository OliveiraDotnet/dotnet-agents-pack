# Understand the system from SQL Server

Read-only. Build an application picture from schema, programmable objects, and .NET consumers. Do not emit `ALTER`, `DROP`, or data-changing SQL.

## What to reconstruct

- Bounded contexts implied by schemas, table prefixes, and ownership.
- Aggregate-like clusters: tables that always change together (orders/items, person/address).
- Status, tenant/company, audit, and soft-delete columns that shape runtime behavior.
- Stored-procedure contracts: parameters, result sets, side effects, and C# callers.
- Jobs, reports, views, and integrations that read the same tables.
- Overlap between current app version and older readers still on the database.

## Evidence order

1. Repository SQL, SSDT, EF model, Dapper queries, and `FromSql*` strings.
2. User-supplied sanitized metadata from `scripts/sqlserver-metadata-map.sql`.
3. Execution plans or Query Store only when provided.

If live metadata is required, run `scripts/sqlserver-access-preflight.ps1` at most once, then give the user the read-only script. Do not retry VPN/DNS failures.

## Output

- Domain map (tables → behavior).
- Dependency map (SQL object ↔ C# consumer).
- Risks labeled static, metadata-backed, or runtime-backed.
- Gaps that need a human (unknown jobs, undocumented result sets).
- Optional `docs/ai/database.md` update **proposed** through `maintain-agent-memory` only; do not edit production code.
