[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $PSCommandPath
$Installer = Join-Path $ScriptDir "install-agent-pack.ps1"
$Template = Join-Path (Split-Path -Parent $ScriptDir) "repo-template"
$TempRoot = Join-Path ([IO.Path]::GetTempPath()) ("dotnet-agents-pack-" + [Guid]::NewGuid().ToString("N"))
$Repo = Join-Path $TempRoot "target"

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

try {
    New-Item -ItemType Directory -Force -Path $Repo | Out-Null
    & git -C $Repo init -q
    Assert-True ($LASTEXITCODE -eq 0) "Unable to initialize temporary Git repository."

    & $Installer -RepoPath $Repo -DryRun -Confirm:$false
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $Repo "AGENTS.md"))) "Dry-run wrote AGENTS.md."

    & $Installer -RepoPath $Repo -Confirm:$false
    Assert-True (Test-Path -LiteralPath (Join-Path $Repo "AGENTS.md")) "Core AGENTS.md was not installed."
    Assert-True (Test-Path -LiteralPath (Join-Path $Repo ".agents\skills\bootstrap-dotnet-repo\SKILL.md")) "Bootstrap skill was not installed."
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $Repo ".codex\agents\frontend-web.toml"))) "Web profile was installed unexpectedly."

    & $Installer -RepoPath $Repo -Confirm:$false
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $Repo "AGENTS.md.agent-pack.new"))) "Idempotent install created a sidecar."

    & $Installer -RepoPath $Repo -Profile web,sqlserver,quality -Confirm:$false
    Assert-True (Test-Path -LiteralPath (Join-Path $Repo ".codex\agents\frontend-web.toml")) "Web profile was not installed."
    Assert-True (Test-Path -LiteralPath (Join-Path $Repo ".agents\skills\db-change-sqlserver\SKILL.md")) "SQL Server profile was not installed."
    Assert-True (Test-Path -LiteralPath (Join-Path $Repo ".agents\skills\security-review-dotnet\SKILL.md")) "Quality profile was not installed."

    Add-Content -LiteralPath (Join-Path $Repo "AGENTS.md") -Value "# local change"
    & $Installer -RepoPath $Repo -Confirm:$false
    Assert-True (Test-Path -LiteralPath (Join-Path $Repo "AGENTS.md.agent-pack.new")) "Conflict sidecar was not created."

    & $Installer -RepoPath $Repo -Force -Confirm:$false
    Assert-True ((Get-Content -LiteralPath (Join-Path $Repo "AGENTS.md") -Raw) -eq (Get-Content -LiteralPath (Join-Path $Template "AGENTS.md") -Raw)) "Force install did not replace modified file."
    Assert-True ((Get-ChildItem -LiteralPath $Repo -Filter "AGENTS.md.agent-pack.backup-*" -File).Count -gt 0) "Force install did not preserve a backup."

    $previousCodexHome = $env:CODEX_HOME
    try {
        $env:CODEX_HOME = Join-Path $TempRoot "custom-codex-home"
        & $Installer -RepoPath $Repo -InstallGlobal -Confirm:$false
        Assert-True (Test-Path -LiteralPath (Join-Path $env:CODEX_HOME "AGENTS.md")) "InstallGlobal did not honor CODEX_HOME."
    }
    finally {
        $env:CODEX_HOME = $previousCodexHome
    }

    Write-Host "Installer smoke test passed."
}
finally {
    if (Test-Path -LiteralPath $TempRoot) { Remove-Item -LiteralPath $TempRoot -Recurse -Force }
}
