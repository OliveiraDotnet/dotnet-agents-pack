# SQL Server Review Checklist

## Schema Review

- Identify source of truth: SQL project, EF Core migrations, SQL scripts, live metadata, or mixed.
- Check schema responsibilities and naming consistency.
- Review table responsibilities, normalization, justified denormalization, historical tables, lookup tables, temporal tables, and soft delete.
- Review primary keys, natural keys, surrogate keys, foreign keys, cascade behavior, unique constraints, check constraints, defaults, computed columns, and nullability.
- Review data types, precision/scale for money/decimal values, `datetime2` vs `datetime`, Unicode needs, max lengths, status columns, and tenant/company isolation.
- Review deployment safety for schema changes and backward compatibility.

## Access and VPN Checklist

- Decide early whether the task can be completed with static repository analysis.
- If live metadata is needed, state that SQL Server may be reachable only outside the sandbox through corporate VPN, private DNS, firewall rules, Windows authentication, or local company tooling.
- Confirm target environment before any direct attempt: local, dev, test, staging, or production.
- Confirm whether VPN is required and connected.
- Confirm available read-only access path: `sqlcmd`, SSMS, Azure Data Studio, PowerShell `SqlServer` module, `Microsoft.Data.SqlClient`, or user-run scripts.
- Use `scripts/sqlserver-access-preflight.ps1` for no-secret DNS/TCP checks when direct access may be possible but network reachability is uncertain.
- Do not request secrets or full connection strings.
- After one clear connection failure caused by DNS, routing, login, firewall, or sandbox isolation, stop retrying and switch to user-run metadata collection.
- Prefer generating read-only metadata queries for the user to execute from the VPN-enabled machine.
- Ask for sanitized outputs, execution plans, Query Store exports, or `STATISTICS IO/TIME` results when runtime evidence is needed.
- Clearly label findings as static-only when live database metadata is unavailable.

## Table Review

- Identify business responsibility and owner service/module.
- Check primary key and clustering choice.
- Check required foreign keys and indexes for joins.
- Check nullable columns for clear meaning.
- Check audit, created/updated/deleted fields, soft delete, and tenancy filters.
- Check application code references, queries, procs, views, triggers, and migrations.

## Stored Procedure Review

- Identify contract, parameters, output/result sets, callers, and deployment compatibility.
- Review transactions, `SET XACT_ABORT`, `TRY/CATCH`, `THROW`, isolation level, locks, idempotency, and concurrency.
- Review dynamic SQL, injection risk, `QUOTENAME`, parameterization, temp tables, table variables, cursors, loops, scalar UDFs, and multi-statement TVFs.
- Review SARGability, implicit conversions, functions on indexed columns, `SELECT *`, `TOP` without `ORDER BY`, pagination, `MERGE`, `@@ROWCOUNT`, `SCOPE_IDENTITY`, and `NOLOCK`.
- Map referenced tables/views/functions/procs and C# callers.

## View Review

- Identify purpose, base objects, callers, and security assumptions.
- Check joins, cardinality, nested views, computed columns, `SELECT *`, `DISTINCT`, `GROUP BY`, and `ORDER BY` misuse.
- Consider schema binding or indexed view only when justified.
- Check predicate pushdown, reporting usage, and breaking changes from column changes.

## Function Review

- Classify scalar, inline table-valued, or multi-statement table-valued.
- Review dependencies, determinism, schema binding, implicit conversions, SARGability, and use in `WHERE`, `JOIN`, or `SELECT`.
- Flag row-by-row scalar UDF and multi-statement TVF risks.
- Consider inline TVF, computed column, view, or application logic when safer.

## Trigger Review

- Identify event, affected table, side effects, and dependencies.
- Check recursion, nesting, multi-row correctness, transaction impact, audit implications, and hidden write behavior.
- Check performance and deployment risks.

## Index Review

- Review clustered index choice, nonclustered indexes, key order, included columns, filtered indexes, unique indexes, and foreign-key support.
- Identify duplicate or overlapping indexes when full metadata is available.
- Treat missing indexes from static SQL as candidates, not facts.
- Explain write overhead, storage, fragmentation/statistics needs, and deployment impact.

## Migration and Deployment Checklist

- Review deployment order, idempotency, `IF EXISTS`/`IF NOT EXISTS`, transaction scope, rollback, repeatability, and environment assumptions.
- Check long-running migration risk, table locks, data backfills, nullable-to-not-null transitions, default constraint naming, foreign keys with existing data, and index creation impact.
- Check pre/post deployment scripts, old app version compatibility, and zero-downtime concerns.

## SQL Server Security Checklist

- Search for dynamic SQL concatenation, unsafe `EXEC`, missing `QUOTENAME`, broad permissions, `db_owner`, `EXECUTE AS`, ownership chaining, and secrets.
- Check tenant/company filter bypass, row-level security, sensitive columns, audit trails, and sensitive parameter logging.
- Redact secrets in output.

## .NET Data-Access Checklist

- Review Dapper parameterization, stored procedure calls, raw SQL, `FromSqlRaw`, `FromSqlInterpolated`, `ExecuteSqlRaw`, `ExecuteSqlInterpolated`, `SqlCommand`, and `CommandType.StoredProcedure`.
- Check command timeout, cancellation token propagation, connection lifetime, transactions, retry policy, ambient transactions, N+1 queries, mapping, nullability, enum/status mapping, pagination, tenant filters, and repository boundaries.

## Performance Analysis Checklist

- Separate static, metadata-backed, and runtime-backed risks.
- Look for non-SARGable predicates, implicit conversions, leading wildcard `LIKE`, missing predicates, unnecessary `DISTINCT`, sorts, key lookups, spills, cardinality mismatch, parameter sniffing, RBAR, cursors, scalar UDFs, table variables, blocking, deadlocks, and over-indexing.
- Use execution plans, Query Store, `STATISTICS IO/TIME`, waits, and runtime metrics when provided.

## Dependency Analysis Checklist

- For tables, map views, procs, functions, triggers, foreign keys, migrations, and code.
- For procs, map touched objects, called procs, C# callers, result sets, and breaking changes.
- For views/functions, map base objects and callers.
- For indexes, map likely consumers and write overhead.
- Report confidence and unresolved dependencies.

## Validation Checklist

- Suggest unit/integration tests, SQL script validation, execution plan comparison, Query Store comparison, `STATISTICS IO/TIME`, deployment dry run, staging validation, and rollback checks as appropriate.
