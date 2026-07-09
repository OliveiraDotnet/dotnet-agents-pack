---
name: security-review-dotnet
description: Perform an evidence-based security review of a .NET change or endpoint, including authorization boundaries, validation, sensitive data, and common web attack paths. Use only when the quality profile is installed and security scope is relevant.
---

# Security review .NET

1. Define the changed trust boundary, actor, resource and authorization rule.
2. Inspect the relevant diff, endpoint, configuration and existing control; never inspect or reveal secret values.
3. Verify only applicable risks: resource or tenant authorization, input validation, injection, XSS/CSRF, uploads, external requests, logging and data exposure.
4. Return evidence, precondition, severity, confidence, impacted boundary and safe validation for each finding.
5. Separate unverified hypotheses from findings.
