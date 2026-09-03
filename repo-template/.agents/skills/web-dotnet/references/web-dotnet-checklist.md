# .NET web UI checklist

Use this checklist only for UI inside the .NET web project. Skip items that do not apply to the detected stack.

## Stack detection

- SDK-style `netcoreapp3.1` / `net5.0+` with `.cshtml` or `.razor`: ASP.NET Core Razor Pages, MVC, or Blazor.
- Classic `.csproj` with `.aspx`, `web.config`, or `packages.config`: Web Forms or MVC 5.
- Mixed solutions: change one project style at a time; do not "modernize" the other stack in the same change.

## ASP.NET Core (3.1+)

- Follow existing page models, controllers, tag helpers, and layout.
- Preserve route templates, antiforgery, `[Bind]` / `[BindRequired]`, and display names.
- Handle success, validation failure, empty list, and not-found states already used by the app.
- Keep authorization attributes and policy names unchanged unless the request covers auth.

## .NET Framework Web Forms / MVC 5

- Preserve `runat="server"` IDs, postback event names, and `ViewState` usage already present.
- Do not remove `ValidateRequest`, event validation, or antiforgery unless explicitly approved.
- Prefer existing user controls and master pages over new layout systems.
- Treat `web.config` as a compatibility surface: change only the keys required by the request.

## Forms and JavaScript

- Keep input `name` attributes aligned with server binding.
- Do not move business rules into JavaScript.
- Reuse existing JS files under `wwwroot`, `Scripts`, or the project's static folder.
- Do not add a SPA toolchain (Angular, React, Vite) from this skill.

## Accessibility and UX

- Labels, error messages, and submit buttons must remain understandable.
- Do not remove existing `alt`, `aria-*`, or validation summary markup.

## Validation

- Prefer the repository's confirmed test or play command.
- If none exists, give a manual path: URL or screen, input, action, expected result.
