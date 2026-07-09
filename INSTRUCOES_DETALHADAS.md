# Guia de adoção do .NET Agents Pack

## Objetivo

O pack reduz o tempo de entendimento de repositórios .NET sem substituir evidência por regras genéricas. Ele atende projetos SDK-style, .NET Framework clássico e soluções mistas; a stack real sempre vem de arquivos do repositório, CI, scripts e testes existentes.

O pack não executa build, restore, migration, banco ou deploy automaticamente. Cada uma dessas ações depende de um comando confirmado e da autorização aplicável.

## Como o contexto é distribuído

| Camada | Deve conter | Não deve conter |
|---|---|---|
| `AGENTS.md` | Fatos e regras curtas sempre relevantes. | Teoria genérica, comandos não verificados ou catálogos de agentes. |
| `docs/ai/` | Mapa, arquitetura, persistência, domínio e runbook confirmados. | Segredos, dados pessoais ou inventários completos. |
| Skills | Workflow sob demanda. | Contexto de um projeto específico. |
| Subagentes | Trabalho independente e delimitado. | Fan-out por padrão. |
| Prompts | Dados do pedido. | Repetição do workflow da skill. |

O Codex usa a cadeia de `AGENTS.md` da raiz do projeto até o diretório de trabalho atual. Um `AGENTS.override.md` aninhado só entra na cadeia quando a tarefa inicia naquele diretório ou abaixo dele. Não use overrides aninhados como se fossem acionados pelo arquivo que está sendo editado.

## Instalação

Por padrão, o instalador exige que `RepoPath` seja exatamente a raiz Git. Isso impede instalação acidental em uma subpasta, no próprio pack ou em uma árvore aninhada. Em uma pasta sem Git, use a opção explícita `AllowNonGit`.

```powershell
# Núcleo somente
.\scripts\install-agent-pack.ps1 -RepoPath "C:\src\MeuSistema"

# Núcleo e perfis detectados ou conhecidos
.\scripts\install-agent-pack.ps1 -RepoPath "C:\src\MeuSistema" -Profile web,sqlserver,quality

# Inspecionar sem escrever
.\scripts\install-agent-pack.ps1 -RepoPath "C:\src\MeuSistema" -Profile web -DryRun
```

```bash
bash ./scripts/install-agent-pack.sh /src/meu-sistema
bash ./scripts/install-agent-pack.sh /src/meu-sistema --profile web,sqlserver,quality
bash ./scripts/install-agent-pack.sh /src/meu-sistema --profile web --dry-run
```

Componentes disponíveis:

- `core`: sempre instalado; contém o bootstrap e os agentes principais.
- `web`: Razor, MVC, Blazor e JavaScript.
- `sqlserver`: SQL Server e workflow de alteração de dados.
- `quality`: revisão de segurança, performance e release.

O instalador compara conteúdo. Arquivo idêntico é ignorado; arquivo diferente recebe `.agent-pack.new`; um sidecar existente e divergente é preservado como conflito. `Force` cria backup com timestamp antes de substituir.

`InstallGlobal` é opcional e instala apenas um exemplo neutro de orientação pessoal. Ele usa `CODEX_HOME` quando definido e, caso contrário, `~/.codex`.

## Bootstrap obrigatório por repositório

Após instalar, abra o repositório no Codex e cole `prompts/00-bootstrap-repo.md` ou invoque `$bootstrap-dotnet-repo`.

A skill executa uma inspeção somente leitura para encontrar:

- forma do workspace e raiz Git;
- `.sln`, `.slnx`, `.csproj`, `.fsproj`, `.vbproj`, `global.json` e `Directory.Build.*`;
- SDK-style, projetos clássicos e `packages.config`;
- frameworks alvo, pacotes e projetos de teste;
- sinais de web, legado e SQL Server;
- CI e scripts que podem conter comandos confirmados.

O resultado é uma hipótese estruturada. Confirme os comandos de build, teste e execução em CI, scripts ou documentação antes de registrá-los no `project-map.md`. Para .NET Framework, os comandos podem envolver MSBuild, NuGet, Visual Studio workloads ou VSTest; o pack nunca deve inserir `dotnet build` por suposição.

O bootstrap pode atualizar `AGENTS.md` e `docs/ai`, mas as instruções novas passam a valer plenamente em uma nova tarefa. Não altere código de produção nesse fluxo.

## Fluxos de trabalho

| Necessidade | Prompt | Skill |
|---|---|---|
| Mapear repositório | `prompts/00-bootstrap-repo.md` | `$bootstrap-dotnet-repo` |
| Corrigir bug | `prompts/01-bugfix.md` | `$bugfix-dotnet` |
| Implementar feature | `prompts/02-feature-slice.md` | `$feature-slice-dotnet` |
| Alterar SQL Server | `prompts/03-db-change.md` | `$db-change-sqlserver` |
| Revisar mudança | `prompts/04-pr-review.md` | `$pr-review-dotnet` |
| Refatorar legado | `prompts/05-refactor-legado.md` | `$legacy-refactor-dotnet` |
| Atualizar memória | `prompts/06-update-agent-memory.md` | `$maintain-agent-memory` |
| Investigar sem alterar | `prompts/07-investigate-only.md` | `repo_explorer`, se necessário |

## Roteamento de agentes

O agente principal deve fazer a mudança. Delegue apenas uma pergunta independente:

- `repo_explorer`: fluxo, metadados e impacto antes da alteração;
- `dotnet_implementer`: uma implementação delimitada depois do mapeamento;
- `test_guardian`: descoberta ou implementação de validação;
- `change_reviewer`: revisão principal baseada no diff;
- agentes de perfis: somente quando o stack ou o diff os justificar.

Em geral, use zero a dois subagentes. Uma revisão que toca banco, autenticação e caminho de alta carga pode justificar três especialistas; bootstrap e PR comuns não justificam uma bateria fixa de revisores.

## Memória técnica

Registre fatos uma vez, com fonte e data de verificação. Use `AGENTS.md` apenas para regras curtas e duráveis. Use `docs/ai` para detalhes. Não transforme log de incidentes, hipótese ou dados sensíveis em instrução persistente.

## Regras de segurança

- Nunca registre secrets, tokens, chaves privadas, connection strings, payloads ou dados pessoais reais.
- Não conecte em banco, execute migrations ou scripts contra ambiente algum sem solicitação explícita.
- Em revisão de segurança ou performance, separe evidência de hipótese e informe a validação necessária.
- Mudança de contrato, schema, permissão ou configuração exige impacto e rollback quando aplicável.

## Evolução do pack

Mantenha uma mudança por vez: primeiro atualize workflow ou componente que falhou em uso real, depois acrescente perfil quando houver recorrência. Não crie agentes por framework ou versão. A escala vem de descoberta, perfis opcionais, manifest e testes de instalação.

Antes de publicar uma versão, execute:

```powershell
.\scripts\validate-pack.ps1
.\scripts\test-install-agent-pack.ps1
.\scripts\test-inspect-dotnet-repo.ps1
```

```bash
bash ./scripts/validate-pack.sh
bash ./scripts/test-install-agent-pack.sh
bash ./scripts/test-inspect-dotnet-repo.sh
```

O pack não prescreve um provedor de CI. Integre esses scripts ao pipeline que a organização já utiliza.
