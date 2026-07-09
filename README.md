# .NET Agents Pack

Pack genérico para orientar o Codex em repositórios .NET modernos e legados sem impor arquitetura, comandos ou preferências pessoais.

Ele fornece um núcleo pequeno para bootstrap, bugfix, feature, refatorção e revisão; perfis opcionais acrescentam especialização para web, SQL Server e revisão de qualidade.

## Componentes

| Componente | Instalação | Uso |
|---|---|---|
| `core` | sempre | Contexto do repositório, descoberta .NET, agentes de exploração/implementação/teste/revisão e skills principais. |
| `web` | opcional | Razor, MVC, Blazor e JavaScript. |
| `sqlserver` | opcional | SQL Server, EF, Dapper, scripts e migrations. |
| `quality` | opcional | Revisão de segurança, performance e release baseada em evidência. |

O manifesto em `pack-manifest.txt` é a fonte de verdade dos arquivos instalados. O instalador nunca copia um perfil que não foi solicitado.

## Instalação

Execute na raiz do pack, apontando para a raiz Git do repositório de destino.

```powershell
# Windows PowerShell ou PowerShell 7
.\scripts\install-agent-pack.ps1 -RepoPath "C:\src\MeuSistema" -Profile web,sqlserver

# Visualizar as ações sem escrever arquivos
.\scripts\install-agent-pack.ps1 -RepoPath "C:\src\MeuSistema" -Profile quality -DryRun
```

```bash
# Linux, macOS ou Git Bash
bash ./scripts/install-agent-pack.sh /src/meu-sistema --profile web,sqlserver

# Visualizar as ações sem escrever arquivos
bash ./scripts/install-agent-pack.sh /src/meu-sistema --profile quality --dry-run
```

Use `-InstallGlobal` ou `--install-global` somente se quiser copiar o exemplo neutro de preferências pessoais. Ele respeita `CODEX_HOME` quando definido e não instala configuração global automaticamente.

Sem Git, use `-AllowNonGit` ou `--allow-non-git` conscientemente.

## Primeiro uso

Abra o repositório no Codex e execute o prompt `prompts/00-bootstrap-repo.md` ou invoque `$bootstrap-dotnet-repo`. A skill executa uma inspeção somente leitura e registra fatos confirmados antes de preencher a memória técnica.

Depois do bootstrap, inicie uma nova tarefa para que o Codex carregue o `AGENTS.md` atualizado.

## Garantias operacionais

- Não presume `dotnet build`, SQL Server, web ou arquitetura em camadas.
- Não executa restore, build, testes, migrations ou deploy durante a descoberta.
- Não sobrescreve arquivo existente sem `Force`; conflitos recebem um sidecar seguro.
- Não instala permissões de sandbox ou approval policy no repositório.
- Mantém instruções persistentes curtas; detalhes ficam em skills e `docs/ai`.

Consulte [as instruções detalhadas](INSTRUCOES_DETALHADAS.md), o [changelog](CHANGELOG.md) e as [fontes oficiais](FONTES_OFICIAIS_CODEX.md) antes de adotar o pack em escala.
