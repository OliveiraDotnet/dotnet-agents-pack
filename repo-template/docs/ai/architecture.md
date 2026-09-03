# Architecture notes

> Source commit: `[UNVERIFIED]`  
> Last verified: `[UNVERIFIED]`  
> Confidence: `[UNVERIFIED]`

## Observed architecture

Describe the architecture found in the repository, not a desired architecture. Separate facts, inferences, and debt.

- Type:
- Layers:
- Dominant pattern:
- Mixed patterns:

## Observed dependencies

```text
[example]
Web -> Application -> Domain
Web -> Infrastructure
Infrastructure -> Database
```

## Patterns found

- Controllers/PageModels:
- Services:
- Repositories:
- Validation:
- DTOs/ViewModels:
- Logging:
- Error handling:

## Implementation rules

- Where a new business rule belongs:
- Where a new endpoint belongs:
- Where a new screen/component belongs:
- Where a new query/repository belongs:
- Where validation belongs:

## Relevant technical debt

| Debt | Impact | Risk | Recommendation |
|---|---|---|---|
| [description] | [impact] | [low/medium/high] | [action] |

## Known decisions

Record architectural decisions already made, including source and verification date when available.

- ...

## Do not

- Do not move layers without a plan.
- Do not standardize everything inside a small feature.
- Do not introduce a new framework without a strong reason.
- Do not break existing contracts without a migration plan.
