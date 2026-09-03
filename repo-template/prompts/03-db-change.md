# SQL Server change

> Requires the `sqlserver` profile.

Use `$db-change-sqlserver` for the requirement below.

[describe the requirement]

Do not drop columns, indexes, or tables, and do not run SQL against a database, until a plan is approved.

## Expected output

- Diagnosis and consumer map.
- Additive vs compatible vs destructive classification.
- Plan for approval (no execution in that turn).
- After approval: script or migration, data impact, application impact, rollback, and validation.
