# SQL Server Database Context

## Source of Truth

State whether the schema appears to come from SQL Server Database Project, EF Core migrations, SQL scripts, live metadata, application model, or mixed sources.

## Database Overview

Summarize the detected database purpose and major business areas.

## Schemas

List schemas and their apparent responsibility.

## Tables

For each important table:

- Schema
- Name
- Apparent responsibility
- Key columns
- Primary key
- Foreign keys
- Important constraints
- Important indexes
- Row volume, if known
- Application code references, if known

## Views

For each view:

- Purpose
- Base objects
- Dependency risks
- `SELECT *` usage
- Aggregation/sorting
- Security implications
- Application references

## Stored Procedures

For each stored procedure:

- Purpose
- Parameters
- Tables/views/functions touched
- Transaction behavior
- Error handling
- Dynamic SQL usage
- Temp table/table variable usage
- Cursor/loop usage
- Result sets
- Application references
- Performance risks

## Functions

For each function:

- Scalar, inline table-valued, or multi-statement table-valued
- Purpose
- Dependencies
- Performance risks
- Determinism/schema binding, if relevant
- Application references

## Triggers

For each trigger:

- Event
- Affected table
- Side effects
- Recursion/nesting risks
- Performance and audit implications

## Indexes

Summarize clustered indexes, nonclustered indexes, unique indexes, filtered indexes, included columns, duplicate/overlapping candidates, missing obvious candidates, and over-indexing risks.

## Constraints and Data Integrity

Summarize primary keys, foreign keys, unique constraints, check constraints, defaults, nullable columns, computed columns, and cascade behavior.

## Security Model

Summarize schemas, permissions, ownership chaining risks, `EXECUTE AS`, dynamic SQL, SQL injection risks, and sensitive data columns when detectable.

## Application Integration

Map SQL objects to repositories, services, handlers, API endpoints, Razor Pages, background workers, jobs, and reports.

## Deployment Model

Summarize migration tool, deployment order, rollback strategy, pre/post deployment scripts, data migration risks, and zero-downtime concerns.

## Known Risks

List concrete risks with evidence.

## Unknowns

List what could not be determined.

## Recommended Next Actions

Prioritize actions by impact.
