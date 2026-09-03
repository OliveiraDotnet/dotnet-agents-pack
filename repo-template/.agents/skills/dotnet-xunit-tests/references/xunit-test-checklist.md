# xUnit Test Checklist

## Inspect

- Read applicable `AGENTS.md` and `AGENTS.override.md`.
- Read README and testing docs.
- Locate `.sln`, `.csproj`, `src/`, `tests/`, `test/`, and `spec/`.
- Identify whether xUnit is already used.
- Identify packages: `xunit`, `xunit.runner.visualstudio`, `Microsoft.NET.Test.Sdk`, `Moq`, `NSubstitute`, `FakeItEasy`, `FluentAssertions`, `Shouldly`, `Microsoft.AspNetCore.Mvc.Testing`, `Testcontainers`, and `coverlet.collector`.
- Identify naming conventions, folder conventions, assertion style, mock library, fixtures, builders, fakes, factories, `WebApplicationFactory`, and integration fixtures.

## Unit Test Rules

- Test behavior, not implementation details.
- Keep tests deterministic.
- Prefer clear Arrange/Act/Assert or the repository's existing convention.
- Avoid excessive mocking.
- Mock I/O, external services, clocks, queues, gateways, and nondeterministic collaborators.
- Keep domain tests close to domain rules.

## Integration Test Rules

- Use existing integration infrastructure when present.
- Avoid production databases and production secrets.
- Ensure test data isolation.
- Prefer realistic persistence tests when query behavior is the risk.
- Propose heavy dependencies such as Testcontainers before adding them when the repository does not already use them.

## API Test Rules

- Cover status codes and response contracts.
- Cover validation errors.
- Cover authentication and authorization.
- Distinguish unauthorized, forbidden, and not found.
- Cover tenant/company isolation when relevant.
- Cover invalid payloads, idempotency, and webhook safety when relevant.

## Regression Workflow

1. Reproduce the bug with a failing test.
2. Apply the minimal production fix.
3. Run the focused test.
4. Run broader relevant tests when the touched code has shared behavior.
5. Report any untested risk.

## Naming Examples

English:

- `CreatePayment_WhenAmountIsZero_ShouldReturnValidationError`
- `ProcessWebhook_WhenEventWasAlreadyProcessed_ShouldBeIdempotent`
- `GetUser_WhenUserBelongsToAnotherCompany_ShouldReturnNotFound`
- `CancelOrder_WhenOrderIsAlreadyShipped_ShouldFail`

Portuguese:

- `CriarPagamento_QuandoValorForZero_DeveRetornarErroDeValidacao`
- `ProcessarWebhook_QuandoEventoJaFoiProcessado_DeveSerIdempotente`
- `ObterUsuario_QuandoUsuarioForDeOutraEmpresa_DeveRetornarNaoEncontrado`
- `CancelarPedido_QuandoPedidoJaFoiEnviado_DeveFalhar`
