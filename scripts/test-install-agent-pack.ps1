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

    & $Installer -RepoPath $Repo -IncludeClaude -DryRun -Confirm:$false
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $Repo "CLAUDE.md"))) "Claude dry-run wrote CLAUDE.md."
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $Repo ".claude"))) "Claude dry-run created .claude."

    & $Installer -RepoPath $Repo -IncludeGrokBuild -DryRun -Confirm:$false
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $Repo ".grok"))) "Grok dry-run created .grok."
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $Repo ".agents\skills\delegate-to-grok-build"))) "Grok dry-run wrote the delegation skill."

    & $Installer -RepoPath $Repo -Confirm:$false
    Assert-True (Test-Path -LiteralPath (Join-Path $Repo "AGENTS.md")) "Core AGENTS.md was not installed."
    Assert-True (Test-Path -LiteralPath (Join-Path $Repo ".agents\skills\bootstrap-dotnet-repo\SKILL.md")) "Bootstrap skill was not installed."
    Assert-True (Test-Path -LiteralPath (Join-Path $Repo ".agents\skills\update-agent-pack\SKILL.md")) "Agent Pack update skill was not installed."
    Assert-True (Test-Path -LiteralPath (Join-Path $Repo ".agents\skills\check-text-encoding\scripts\check-mojibake.ps1")) "PowerShell text encoding checker was not installed."
    Assert-True (Test-Path -LiteralPath (Join-Path $Repo ".agents\skills\check-text-encoding\scripts\check-mojibake.sh")) "Shell text encoding checker was not installed."
    Assert-True (Test-Path -LiteralPath (Join-Path $Repo "prompts\08-update-agent-pack.md")) "Agent Pack update prompt was not installed."
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $Repo ".codex\agents\frontend-web.toml"))) "Web profile was installed unexpectedly."
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $Repo "CLAUDE.md"))) "Default install wrote CLAUDE.md."
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $Repo ".claude"))) "Default install created .claude."
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $Repo ".grok"))) "Default install created .grok."

    & $Installer -RepoPath $Repo -Confirm:$false
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $Repo "AGENTS.md.agent-pack.new"))) "Idempotent install created a sidecar."

    & $Installer -RepoPath $Repo -Profile web,sqlserver,quality -Confirm:$false
    Assert-True (Test-Path -LiteralPath (Join-Path $Repo ".codex\agents\frontend-web.toml")) "Web profile was not installed."
    Assert-True (Test-Path -LiteralPath (Join-Path $Repo ".agents\skills\db-change-sqlserver\SKILL.md")) "SQL Server profile was not installed."
    Assert-True (Test-Path -LiteralPath (Join-Path $Repo ".agents\skills\security-review-dotnet\SKILL.md")) "Quality profile was not installed."
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $Repo "CLAUDE.md"))) "Profiles installed Claude support without -IncludeClaude."
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $Repo ".grok"))) "Profiles installed Grok support without -IncludeGrokBuild."

    & $Installer -RepoPath $Repo -IncludeClaude -Confirm:$false
    Assert-True (Test-Path -LiteralPath (Join-Path $Repo "CLAUDE.md")) "Claude guidance bridge was not installed."
    Assert-True (Test-Path -LiteralPath (Join-Path $Repo ".claude\agents\repo-explorer.md")) "Core Claude agent was not installed."
    Assert-True (Test-Path -LiteralPath (Join-Path $Repo ".claude\skills\bootstrap-dotnet-repo\SKILL.md")) "Core Claude skill was not installed."
    Assert-True (Test-Path -LiteralPath (Join-Path $Repo ".claude\skills\bootstrap-dotnet-repo\scripts\inspect-dotnet-repo.ps1")) "Claude skill support script was not installed."
    Assert-True (Test-Path -LiteralPath (Join-Path $Repo ".claude\skills\update-agent-pack\SKILL.md")) "Claude Agent Pack update skill was not installed."
    Assert-True (Test-Path -LiteralPath (Join-Path $Repo ".claude\skills\check-text-encoding\scripts\check-mojibake.ps1")) "Claude PowerShell text encoding checker was not installed."
    Assert-True (Test-Path -LiteralPath (Join-Path $Repo ".claude\skills\check-text-encoding\scripts\check-mojibake.sh")) "Claude shell text encoding checker was not installed."
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $Repo ".claude\agents\frontend-web.md"))) "Claude web profile was installed unexpectedly."
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $Repo ".claude\agents\database-sqlserver.md"))) "Claude SQL Server profile was installed unexpectedly."
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $Repo ".claude\agents\security-reviewer.md"))) "Claude quality profile was installed unexpectedly."

    $canonicalBootstrapSkill = Join-Path $Repo ".agents\skills\bootstrap-dotnet-repo\SKILL.md"
    $claudeBootstrapSkill = Join-Path $Repo ".claude\skills\bootstrap-dotnet-repo\SKILL.md"
    Assert-True ((Get-FileHash -LiteralPath $canonicalBootstrapSkill -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $claudeBootstrapSkill -Algorithm SHA256).Hash) "Claude bootstrap skill diverged from its canonical source."

    & $Installer -RepoPath $Repo -IncludeGrokBuild -Confirm:$false
    Assert-True (Test-Path -LiteralPath (Join-Path $Repo ".grok\config.toml")) "Grok project config was not installed."
    Assert-True (Test-Path -LiteralPath (Join-Path $Repo ".grok\agents\repo-explorer.md")) "Core Grok agent was not installed."
    Assert-True (Test-Path -LiteralPath (Join-Path $Repo ".grok\skills\bootstrap-dotnet-repo\SKILL.md")) "Core Grok skill was not installed."
    Assert-True (Test-Path -LiteralPath (Join-Path $Repo ".agents\skills\delegate-to-grok-build\SKILL.md")) "Codex delegation skill was not installed."
    Assert-True (Test-Path -LiteralPath (Join-Path $Repo ".grok\skills\execute-codex-work-order\SKILL.md")) "Grok execution skill was not installed."
    Assert-True (Test-Path -LiteralPath (Join-Path $Repo "prompts\09-migrate-claude-to-codex-grok.md")) "Codex/Grok migration prompt was not installed."
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $Repo ".grok\agents\frontend-web.md"))) "Grok web profile was installed unexpectedly."
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $Repo ".grok\agents\database-sqlserver.md"))) "Grok SQL Server profile was installed unexpectedly."
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $Repo ".grok\agents\security-reviewer.md"))) "Grok quality profile was installed unexpectedly."

    $grokBootstrapSkill = Join-Path $Repo ".grok\skills\bootstrap-dotnet-repo\SKILL.md"
    Assert-True ((Get-FileHash -LiteralPath $canonicalBootstrapSkill -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $grokBootstrapSkill -Algorithm SHA256).Hash) "Grok bootstrap skill diverged from its canonical source."

    & $Installer -RepoPath $Repo -IncludeGrokBuild -Confirm:$false
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $Repo ".grok\config.toml.agent-pack.new"))) "Idempotent Grok install created a config sidecar."

    & $Installer -RepoPath $Repo -IncludeClaude -Confirm:$false
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $Repo "CLAUDE.md.agent-pack.new"))) "Idempotent Claude install created a sidecar."

    & $Installer -RepoPath $Repo -Profile web,sqlserver,quality -IncludeClaude -Confirm:$false
    Assert-True (Test-Path -LiteralPath (Join-Path $Repo ".claude\agents\frontend-web.md")) "Claude web profile was not installed."
    Assert-True (Test-Path -LiteralPath (Join-Path $Repo ".claude\agents\database-sqlserver.md")) "Claude SQL Server profile was not installed."
    Assert-True (Test-Path -LiteralPath (Join-Path $Repo ".claude\agents\security-reviewer.md")) "Claude quality profile was not installed."
    Assert-True (Test-Path -LiteralPath (Join-Path $Repo ".claude\skills\db-change-sqlserver\SKILL.md")) "Claude SQL Server skill was not installed."
    Assert-True (Test-Path -LiteralPath (Join-Path $Repo ".claude\skills\security-review-dotnet\SKILL.md")) "Claude quality skill was not installed."

    & $Installer -RepoPath $Repo -Profile web,sqlserver,quality -IncludeGrokBuild -Confirm:$false
    Assert-True (Test-Path -LiteralPath (Join-Path $Repo ".grok\agents\frontend-web.md")) "Grok web profile was not installed."
    Assert-True (Test-Path -LiteralPath (Join-Path $Repo ".grok\agents\database-sqlserver.md")) "Grok SQL Server profile was not installed."
    Assert-True (Test-Path -LiteralPath (Join-Path $Repo ".grok\agents\security-reviewer.md")) "Grok quality profile was not installed."
    Assert-True (Test-Path -LiteralPath (Join-Path $Repo ".grok\skills\db-change-sqlserver\SKILL.md")) "Grok SQL Server skill was not installed."
    Assert-True (Test-Path -LiteralPath (Join-Path $Repo ".grok\skills\security-review-dotnet\SKILL.md")) "Grok quality skill was not installed."
    Assert-True (Test-Path -LiteralPath (Join-Path $Repo "CLAUDE.md")) "Adding Grok removed the coexisting Claude integration."

    Add-Content -LiteralPath (Join-Path $Repo "AGENTS.md") -Value "# local change"
    & $Installer -RepoPath $Repo -Confirm:$false
    Assert-True (Test-Path -LiteralPath (Join-Path $Repo "AGENTS.md.agent-pack.new")) "Conflict sidecar was not created."

    & $Installer -RepoPath $Repo -Force -Confirm:$false
    Assert-True ((Get-Content -LiteralPath (Join-Path $Repo "AGENTS.md") -Raw) -eq (Get-Content -LiteralPath (Join-Path $Template "AGENTS.md") -Raw)) "Force install did not replace modified file."
    Assert-True ((Get-ChildItem -LiteralPath $Repo -Filter "AGENTS.md.agent-pack.backup-*" -File).Count -gt 0) "Force install did not preserve a backup."

    Add-Content -LiteralPath (Join-Path $Repo "CLAUDE.md") -Value "# local Claude change"
    & $Installer -RepoPath $Repo -IncludeClaude -Confirm:$false
    Assert-True (Test-Path -LiteralPath (Join-Path $Repo "CLAUDE.md.agent-pack.new")) "Claude conflict sidecar was not created."

    & $Installer -RepoPath $Repo -IncludeClaude -Force -Confirm:$false
    Assert-True ((Get-Content -LiteralPath (Join-Path $Repo "CLAUDE.md") -Raw) -eq (Get-Content -LiteralPath (Join-Path $Template "CLAUDE.md") -Raw)) "Force install did not replace modified CLAUDE.md."
    Assert-True ((Get-ChildItem -LiteralPath $Repo -Filter "CLAUDE.md.agent-pack.backup-*" -File).Count -gt 0) "Force install did not preserve a CLAUDE.md backup."

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
