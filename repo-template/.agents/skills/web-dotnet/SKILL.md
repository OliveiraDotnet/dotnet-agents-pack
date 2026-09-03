---
name: web-dotnet
description: Implement or fix UI in a .NET web app (Razor Pages, MVC, Blazor, Web Forms, .aspx, and app JavaScript). Use when the change lives in the .NET web project itself. Do not use for Angular/React SPAs, API-only work, or SQL schema changes.
---

# .NET web UI

Use only when the `web` profile is installed. Follow the repository's existing UI stack; do not introduce Blazor, a SPA, or a new JS framework.

1. Confirm the UI stack from project files: ASP.NET Core 3.1+ (Razor Pages, MVC, Blazor) or .NET Framework (Web Forms, MVC 5, `web.config`).
2. Read the closest existing screen or endpoint and copy its layout, binding names, validation, and error/empty/loading states.
3. Keep server-side validation. Client validation may assist; it must not replace server checks.
4. Preserve model-binding field names, routes, partials, components, antiforgery tokens, and shared scripts.
5. Do not duplicate domain rules in the UI. Do not change public API contracts unless the request includes them.
6. Read `references/web-dotnet-checklist.md` before touching Web Forms ViewState, `web.config`, or a mixed Framework/Core solution.
7. Validate with confirmed repository commands only. Provide a short manual scenario when UI automation is unavailable.

Return stack detected, files changed, preserved contracts, validation, and residual risk.
