---
name: performance-review-dotnet
description: Investigate a measurable .NET or SQL Server performance concern using a slow path, diff, trace, query plan, or workload evidence. Use only when the quality profile is installed and a performance question is in scope.
---

# Performance review .NET

1. Start from a concrete path, metric, trace, plan, diff or reproducible workload.
2. Inspect only relevant query shape, pagination, materialization, blocking I/O, repeated remote work, allocation and cache behavior.
3. Label observations and hypotheses separately. State the minimum measurement needed to confirm each hypothesis.
4. Recommend the smallest measurable intervention and comparison before/after.
