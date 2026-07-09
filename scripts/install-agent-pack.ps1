[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Medium")]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$RepoPath,

    [string[]]$Profile = @(),

    [switch]$InstallGlobal,
    [switch]$AllowNonGit,
    [switch]$Force,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ScriptDir = Split-Path -Parent $PSCommandPath
$PackRoot = Split-Path -Parent $ScriptDir
$TemplateRoot = Join-Path $PackRoot "repo-template"
$ManifestPath = Join-Path $PackRoot "pack-manifest.txt"
$GlobalGuidance = Join-Path $PackRoot "global\AGENTS.md"
$ValidProfiles = @("core", "web", "sqlserver", "quality")
$Actions = New-Object System.Collections.Generic.List[object]

function Get-CanonicalDirectory {
    param([Parameter(Mandatory = $true)][string]$Path, [string]$Label = "Path")

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "$Label is not a directory: $Path"
    }

    return (Resolve-Path -LiteralPath $Path).Path
}

function Test-PathWithin {
    param([Parameter(Mandatory = $true)][string]$Parent, [Parameter(Mandatory = $true)][string]$Child)

    $parentFull = [IO.Path]::GetFullPath($Parent).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $childFull = [IO.Path]::GetFullPath($Child)
    $prefix = $parentFull + [IO.Path]::DirectorySeparatorChar
    return $childFull.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
}

function Test-SameContent {
    param([Parameter(Mandatory = $true)][string]$Left, [Parameter(Mandatory = $true)][string]$Right)

    if (-not (Test-Path -LiteralPath $Left -PathType Leaf) -or -not (Test-Path -LiteralPath $Right -PathType Leaf)) {
        return $false
    }

    return (Get-FileHash -LiteralPath $Left -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $Right -Algorithm SHA256).Hash
}

function Get-AvailableBackupPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $timestamp = Get-Date -Format "yyyyMMddHHmmss"
    $candidate = "$Path.agent-pack.backup-$timestamp"
    $counter = 1
    while (Test-Path -LiteralPath $candidate) {
        $candidate = "$Path.agent-pack.backup-$timestamp-$counter"
        $counter++
    }
    return $candidate
}

function Add-CopyAction {
    param([Parameter(Mandatory = $true)][string]$Source, [Parameter(Mandatory = $true)][string]$Destination)

    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        throw "Manifest source is missing: $Source"
    }

    $state = "COPY"
    $effectiveDestination = $Destination

    if (Test-Path -LiteralPath $Destination) {
        if (Test-SameContent $Source $Destination) {
            $state = "SKIP"
        }
        elseif ($Force) {
            $state = "REPLACE"
        }
        else {
            $sidecar = "$Destination.agent-pack.new"
            if (Test-Path -LiteralPath $sidecar) {
                if (Test-SameContent $Source $sidecar) {
                    $state = "SKIP"
                    $effectiveDestination = $sidecar
                }
                else {
                    $state = "CONFLICT"
                    $effectiveDestination = $sidecar
                }
            }
            else {
                $state = "SIDECAR"
                $effectiveDestination = $sidecar
            }
        }
    }

    $Actions.Add([pscustomobject]@{
        State = $state
        Source = $Source
        Destination = $effectiveDestination
        OriginalDestination = $Destination
    }) | Out-Null
}

function Invoke-CopyAction {
    param([Parameter(Mandatory = $true)]$Action)

    Write-Host ("{0,-9} {1}" -f $Action.State, $Action.Destination)

    if ($Action.State -in @("SKIP", "CONFLICT") -or $DryRun) {
        return
    }

    if (-not $PSCmdlet.ShouldProcess($Action.Destination, $Action.State)) {
        return
    }

    $destinationDirectory = Split-Path -Parent $Action.Destination
    if (-not (Test-Path -LiteralPath $destinationDirectory)) {
        New-Item -ItemType Directory -Force -Path $destinationDirectory | Out-Null
    }

    if ($Action.State -eq "REPLACE") {
        $backup = Get-AvailableBackupPath $Action.OriginalDestination
        Copy-Item -LiteralPath $Action.OriginalDestination -Destination $backup -Force
        Write-Host ("BACKUP    {0}" -f $backup)
    }

    Copy-Item -LiteralPath $Action.Source -Destination $Action.Destination -Force
}

$repoRoot = Get-CanonicalDirectory -Path $RepoPath -Label "RepoPath"
$packRootCanonical = Get-CanonicalDirectory -Path $PackRoot -Label "Pack root"
$templateRootCanonical = Get-CanonicalDirectory -Path $TemplateRoot -Label "Template root"

if ((Test-PathWithin $templateRootCanonical $repoRoot) -or (Test-PathWithin $repoRoot $templateRootCanonical) -or $repoRoot -eq $templateRootCanonical) {
    throw "RepoPath must not overlap the pack template."
}

if (-not $AllowNonGit) {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw "Git is required to validate RepoPath. Install Git or pass -AllowNonGit explicitly."
    }

    $gitRoot = & git -C $repoRoot rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $gitRoot) {
        throw "RepoPath is not a Git repository root. Pass -AllowNonGit only when this is intentional."
    }

    $gitRootCanonical = Get-CanonicalDirectory -Path $gitRoot.Trim() -Label "Git root"
    if ($gitRootCanonical -ne $repoRoot) {
        throw "RepoPath must be the Git root, not a subdirectory: $gitRootCanonical"
    }
}

if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "Pack manifest is missing: $ManifestPath"
}

$requestedProfiles = New-Object System.Collections.Generic.List[string]
$requestedProfiles.Add("core")
foreach ($value in $Profile) {
    foreach ($item in ($value -split ",")) {
        $normalized = $item.Trim().ToLowerInvariant()
        if ($normalized) { $requestedProfiles.Add($normalized) }
    }
}
$requestedProfiles = @($requestedProfiles | Select-Object -Unique)

foreach ($requestedProfile in $requestedProfiles) {
    if ($ValidProfiles -notcontains $requestedProfile) {
        throw "Unknown profile '$requestedProfile'. Valid profiles: $($ValidProfiles -join ', ')."
    }
}

Get-Content -LiteralPath $ManifestPath | ForEach-Object {
    $line = $_.Trim()
    if (-not $line -or $line.StartsWith("#")) { return }

    $parts = $line -split '\|', 2
    if ($parts.Count -ne 2) { throw "Invalid manifest line: $line" }

    $component = $parts[0].Trim().ToLowerInvariant()
    $relativePath = $parts[1].Trim()
    if ($requestedProfiles -notcontains $component) { return }

    $source = [IO.Path]::GetFullPath((Join-Path $templateRootCanonical $relativePath))
    $destination = [IO.Path]::GetFullPath((Join-Path $repoRoot $relativePath))
    if (-not (Test-PathWithin $templateRootCanonical $source) -or -not (Test-PathWithin $repoRoot $destination)) {
        throw "Manifest path escapes its root: $relativePath"
    }

    Add-CopyAction -Source $source -Destination $destination
}

if ($InstallGlobal) {
    $codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME ".codex" }
    $codexHome = [IO.Path]::GetFullPath($codexHome)
    Add-CopyAction -Source $GlobalGuidance -Destination (Join-Path $codexHome "AGENTS.md")
}

Write-Host "Installing .NET Agents Pack profiles: $($requestedProfiles -join ', ')"
if ($DryRun) { Write-Host "Dry-run enabled: no files will be written." }

foreach ($action in $Actions) {
    Invoke-CopyAction -Action $action
}

$summary = $Actions | Group-Object State | Sort-Object Name | ForEach-Object { "{0}={1}" -f $_.Name, $_.Count }
Write-Host ("Summary: {0}" -f ($summary -join ", "))
if (@($Actions | Where-Object { $_.State -eq "CONFLICT" }).Count -gt 0) {
    Write-Warning "Conflicting .agent-pack.new files were preserved; review them before retrying."
}
