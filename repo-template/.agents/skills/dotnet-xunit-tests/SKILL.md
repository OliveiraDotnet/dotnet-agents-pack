---
name: dotnet-xunit-tests
description: Create, improve, or repair the xUnit test layer for a .NET solution, including test projects, fixtures, and behavior coverage. Use when the work is the test architecture or a set of tests. Do not use for a single regression inside a bugfix; use test_guardian for that.
---

# .NET xUnit tests

1. Read applicable `AGENTS.md` and confirmed test commands.
2. Locate existing test projects, naming, assertions, mocks, and fixtures. Follow them.
3. State the test strategy: target, type, scenarios, files, and dependencies.
4. Add or repair tests in the correct project. Prefer public behavior over private implementation.
5. Read `references/xunit-test-checklist.md` before creating a new test project, adding integration/API tests, or changing test architecture.
6. Run the narrowest confirmed test command. If none exists, say so; do not invent a command as fact.
7. Report files, coverage intent, commands, results, and gaps.
