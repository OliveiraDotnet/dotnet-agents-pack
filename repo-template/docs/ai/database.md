# Data and persistence notes

> Source commit: `[UNVERIFIED]`  
> Last verified: `[UNVERIFIED]`

## Confirmed persistence model

- Database engine or external data source:
- Data access technology:
- Source of truth for schema changes:
- Location of context, repositories, queries, migrations or scripts:
- Location of non-secret local configuration:

Never record connection strings, database credentials, production names or customer data.

## Consumers and contracts

| Object or contract | Consumers | Compatibility risk | Evidence |
|---|---|---|---|
| `[UNVERIFIED]` | | | |

## Change checklist

- Is the rollout backward compatible with the deployed application?
- Are existing records, backfill, defaults and rollback covered?
- Are queries, procedures, reports, jobs and integrations affected?
- Is there evidence for index, lock or cardinality risk?
- Is the target environment authorized and non-production unless explicitly approved?
