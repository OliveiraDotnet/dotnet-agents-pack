[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $PSCommandPath
$PackRoot = Split-Path -Parent $ScriptDir
$Inspector = Join-Path $PackRoot "repo-template\.agents\skills\bootstrap-dotnet-repo\scripts\inspect-dotnet-repo.ps1"

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$modernPath = Join-Path $PackRoot "tests\fixtures\modern-web"
$modern = & $Inspector -RepoPath $modernPath -Format json | ConvertFrom-Json
Assert-True ($modern.targetFrameworks -contains "net8.0") "Modern fixture target framework was not detected."
Assert-True ($modern.optionalProfilesSuggested -contains "web") "Modern web profile was not suggested."
Assert-True ($modern.optionalProfilesSuggested -contains "sqlserver") "SQL Server profile was not suggested from fixture evidence."
Assert-True ($modern.testProjects.Count -eq 1) "Modern test project was not detected."

$legacyPath = Join-Path $PackRoot "tests\fixtures\legacy-framework"
$legacy = & $Inspector -RepoPath $legacyPath -Format json | ConvertFrom-Json
Assert-True ($legacy.targetFrameworks -contains "v4.8") "Legacy target framework was not detected."
Assert-True (@($legacy.projectFiles | Where-Object { $_.style -eq "classic" }).Count -eq 1) "Classic project style was not detected."
Assert-True ($legacy.optionalProfilesSuggested -contains "legacy-framework") "Legacy framework profile was not suggested."

Write-Host "Repository inspector smoke test passed."
