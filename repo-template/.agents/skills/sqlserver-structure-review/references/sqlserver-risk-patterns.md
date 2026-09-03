# SQL Server Risk Patterns

## SELECT Star

`SELECT *` in views and procedures creates unstable contracts, unnecessary IO, and breaking-change risk when columns are added, removed, or reordered.

## NOLOCK Misuse

`NOLOCK` can read uncommitted, duplicated, missing, or inconsistent rows. Treat it as a correctness risk, not a default performance optimization.

## Dynamic SQL Injection

String-concatenated SQL with user or application input can permit SQL injection. Prefer parameterized `sp_executesql`; use `QUOTENAME` for object names when dynamic object names are unavoidable.

## Implicit Conversions

Comparing mismatched data types can force conversions, disable useful index seeks, and produce wrong cardinality estimates.

## Functions on Indexed Columns

Applying functions to columns in `WHERE` or `JOIN` predicates can make predicates non-SARGable and cause scans.

## Scalar UDF Performance Risk

Scalar functions can run row-by-row and hide expensive logic. SQL Server versions with scalar UDF inlining reduce some risks, but do not assume it applies.

## Multi-Statement TVF Cardinality Risk

Multi-statement table-valued functions often have poor cardinality estimates and can damage plan quality.

## Large Table Variables

Table variables can produce bad estimates for larger row counts. Temp tables with indexes/statistics may be safer for non-trivial data volumes.

## Cursors and RBAR

Cursor and row-by-row logic can be appropriate for rare administrative tasks, but it is often slow and blocking-prone in business workloads.

## Missing Foreign Keys

Missing foreign keys allow inconsistent data and can reduce optimizer knowledge. Confirm whether absence is intentional for ingestion, replication, or legacy reasons.

## Unclear Nullability

Nullable columns without business meaning complicate queries and validation. Prefer explicit required fields or documented null semantics.

## Weak Data Types

Use appropriate precision for money/decimal values, `datetime2` for new date/time columns, bounded string lengths, and consistent status/enum storage.

## TOP Without ORDER BY

`TOP` without deterministic `ORDER BY` returns arbitrary rows and can cause unstable behavior.

## MERGE Risks

`MERGE` has correctness and concurrency pitfalls. Prefer separate `INSERT`/`UPDATE` patterns unless `MERGE` is already validated and justified.

## Long Transactions

Long transactions increase blocking, deadlock risk, log growth, and deployment risk.

## Non-Idempotent Deployment Scripts

Deployment scripts that cannot be rerun safely increase failed-release risk. Use existence checks and repeatable patterns when the deployment model expects reruns.

## Breaking Procedure Result Sets

Changing procedure result columns, names, order, types, or nullability can break Dapper/ADO.NET mapping, reports, and API behavior.

## Drop and Recreate Objects

Dropping/recreating procedures, views, or functions can lose permissions, extended properties, dependencies, or deployment history. Prefer `CREATE OR ALTER` when supported and consistent.

## Duplicate or Overlapping Indexes

Indexes with identical or heavily overlapping keys/includes add write and storage cost. Confirm runtime usage before removal.

## Tenant or Company Filter Mistakes

Missing tenant/company predicates in queries, views, procs, or repositories can leak data across customers or business units.
