[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Medium")]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$RepoPath,

    [string[]]$Profile = @(),

    [switch]$IncludeClaude,
    [switch]$IncludeGrokBuild,
    [switch]$InstallGlobal,
    [switch]$AllowNonGit,
    [switch]$Force,
    [switch]$DryRun,
    [switch]$DiscoverOnly
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ScriptDir = Split-Path -Parent $PSCommandPath
$PackRoot = Split-Path -Parent $ScriptDir
$TemplateRoot = Join-Path $PackRoot "repo-template"
$ManifestPath = Join-Path $PackRoot "pack-manifest.txt"
$ArtifactsPath = Join-Path $PackRoot "pack-artifacts.txt"
$VersionPath = Join-Path $PackRoot "pack-version.txt"
$GlobalGuidance = Join-Path $PackRoot "global\AGENTS.md"
$InspectScript = Join-Path $TemplateRoot ".agents\skills\bootstrap-dotnet-repo\scripts\inspect-dotnet-repo.ps1"
$ValidProfiles = @("core", "web", "sqlserver", "quality")
$AutoDetectableProfiles = @("web", "sqlserver")
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$Utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)
$PathComparison = if ($env:OS -eq "Windows_NT") { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }

function Get-CanonicalDirectory {
    param([Parameter(Mandatory = $true)][string]$Path, [string]$Label = "Path")

    if (-not (Test-Path -LiteralPath $Path -Type Container)) {
        throw "$Label is not a directory: $Path"
    }

    return (Resolve-Path -LiteralPath $Path).Path
}

function Test-PathWithin {
    param([Parameter(Mandatory = $true)][string]$Parent, [Parameter(Mandatory = $true)][string]$Child)

    $parentFull = [IO.Path]::GetFullPath($Parent).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $childFull = [IO.Path]::GetFullPath($Child)
    $prefix = $parentFull + [IO.Path]::DirectorySeparatorChar
    return $childFull.StartsWith($prefix, $PathComparison)
}

function Test-SameContent {
    param([Parameter(Mandatory = $true)][string]$Left, [Parameter(Mandatory = $true)][string]$Right)

    if (-not (Test-Path -LiteralPath $Left -PathType Leaf) -or -not (Test-Path -LiteralPath $Right -PathType Leaf)) {
        return $false
    }

    return (Get-FileHash -LiteralPath $Left -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $Right -Algorithm SHA256).Hash
}

function Get-NormalizedTextHash {
    param([Parameter(Mandatory = $true)][string]$Path)

    $bytes = [IO.File]::ReadAllBytes($Path)
    $offset = 0
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $offset = 3
    }
    $text = $Utf8Strict.GetString($bytes, $offset, $bytes.Length - $offset)
    $normalized = $text.Replace("`r`n", "`n").Replace("`r", "`n")
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($Utf8NoBom.GetBytes($normalized)))).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Test-IsGitRoot {
    param([Parameter(Mandatory = $true)][string]$Path)
    return Test-Path -LiteralPath (Join-Path $Path ".git")
}

function Find-GitRoots {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [int]$MaxDepth = 3
    )

    if (Test-IsGitRoot $Root) {
        return @($Root)
    }

    $exclude = @(".git", "node_modules", "bin", "obj", "packages", ".vs")
    $roots = New-Object System.Collections.Generic.List[string]

    function Walk {
        param([string]$Directory, [int]$Depth)
        if ($Depth -gt $MaxDepth) {
            return
        }
        Get-ChildItem -LiteralPath $Directory -Force -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            if ($exclude -contains $_.Name) {
                return
            }
            if (($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                return
            }
            if (Test-IsGitRoot $_.FullName) {
                $roots.Add($_.FullName)
                return
            }
            Walk -Directory $_.FullName -Depth ($Depth + 1)
        }
    }

    Walk -Directory $Root -Depth 1
    return @($roots.ToArray())
}

function Get-PackVersion {
    $lines = @(Get-Content -LiteralPath $VersionPath | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith("#") })
    if ($lines.Count -ne 1) {
        throw "pack-version.txt must contain exactly one version record."
    }
    return $lines[0]
}

function Get-DetectedProfiles {
    param([Parameter(Mandatory = $true)][string]$TargetRoot)

    if (-not (Test-Path -LiteralPath $InspectScript -PathType Leaf)) {
        return @()
    }

    try {
        $json = & $InspectScript -RepoPath $TargetRoot -Format json | Out-String
        $info = $json | ConvertFrom-Json
        $suggested = @($info.optionalProfilesSuggested)
        return @($suggested | Where-Object { $AutoDetectableProfiles -contains $_ } | Select-Object -Unique)
    }
    catch {
        Write-Warning "Workspace inspection failed for $TargetRoot. Installing core only unless profiles were requested. $($_.Exception.Message)"
        return @()
    }
}

function Get-StateRecords {
    param(
        [Parameter(Mandatory = $true)][string]$TargetRoot,
        [Parameter(Mandatory = $true)][string]$Kind
    )

    $statePath = Join-Path $TargetRoot ".agent-pack\state.txt"
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
        return @()
    }

    $values = New-Object System.Collections.Generic.List[string]
    Get-Content -LiteralPath $statePath | ForEach-Object {
        $line = $_.Trim()
        if ($line -match "^$Kind\|(.+)$") {
            $values.Add($Matches[1].Trim().ToLowerInvariant()) | Out-Null
        }
    }
    return @($values)
}

function Get-StateProfiles {
    param([Parameter(Mandatory = $true)][string]$TargetRoot)
    return @(Get-StateRecords -TargetRoot $TargetRoot -Kind "profile")
}

function Resolve-InstallProfiles {
    param(
        [Parameter(Mandatory = $true)][string]$TargetRoot,
        [string[]]$RequestedProfile
    )

    $profiles = New-Object System.Collections.Generic.List[string]
    $profiles.Add("core") | Out-Null
    $explicit = @()
    foreach ($value in $RequestedProfile) {
        foreach ($item in ($value -split ",")) {
            $normalized = $item.Trim().ToLowerInvariant()
            if ($normalized) {
                $explicit += $normalized
            }
        }
    }

    if ($explicit.Count -gt 0) {
        foreach ($profile in $explicit) {
            $profiles.Add($profile) | Out-Null
        }
        foreach ($profile in (Get-StateProfiles -TargetRoot $TargetRoot)) {
            $profiles.Add($profile) | Out-Null
        }
    }
    else {
        $existing = @(Get-StateProfiles -TargetRoot $TargetRoot)
        if ($existing.Count -gt 0) {
            foreach ($profile in $existing) {
                $profiles.Add($profile) | Out-Null
            }
        }
        else {
            foreach ($profile in (Get-DetectedProfiles -TargetRoot $TargetRoot)) {
                $profiles.Add($profile) | Out-Null
            }
        }
    }

    $resolved = @($profiles | Select-Object -Unique)
    foreach ($profile in $resolved) {
        if ($ValidProfiles -notcontains $profile) {
            throw "Unknown profile '$profile'. Valid profiles: $($ValidProfiles -join ', ')."
        }
    }
    return $resolved
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
    param(
        [Parameter(Mandatory = $true)]$Actions,
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )

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

function Write-InstallState {
    param(
        [Parameter(Mandatory = $true)][string]$TargetRoot,
        [Parameter(Mandatory = $true)][string]$PackVersion,
        [Parameter(Mandatory = $true)][string[]]$Profiles,
        [Parameter(Mandatory = $true)][string[]]$Integrations,
        [Parameter(Mandatory = $true)]$ManifestByDestination,
        [Parameter(Mandatory = $true)]$ArtifactEntries,
        [Parameter(Mandatory = $true)]$Actions
    )

    $writtenByOriginal = @{}
    foreach ($action in $Actions) {
        $writtenByOriginal[$action.OriginalDestination] = $action
    }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("version|$PackVersion") | Out-Null
    foreach ($profile in @($Profiles | Sort-Object { if ($_ -eq "core") { "0" } else { "1$_" } })) {
        $lines.Add("profile|$profile") | Out-Null
    }
    foreach ($integration in @($Integrations | Sort-Object)) {
        $lines.Add("integration|$integration") | Out-Null
    }

    foreach ($artifact in @($ArtifactEntries | Sort-Object Id)) {
        $sourceRelative = $ManifestByDestination[$artifact.Destination]
        if (-not $sourceRelative) {
            continue
        }
        $originalFull = [IO.Path]::GetFullPath((Join-Path $TargetRoot $artifact.Destination))
        $action = $writtenByOriginal[$originalFull]
        if (-not $action) {
            continue
        }

        $sourceFull = [IO.Path]::GetFullPath((Join-Path $TemplateRoot $sourceRelative))
        $packHash = Get-NormalizedTextHash -Path $sourceFull
        if ($artifact.Ownership -eq "seed") {
            $localHash = if ($action.State -in @("COPY", "REPLACE", "SKIP") -and (Test-Path -LiteralPath $originalFull -PathType Leaf)) {
                Get-NormalizedTextHash -Path $originalFull
            }
            else {
                $packHash
            }
            $lines.Add("artifact|$($artifact.Id)|$($artifact.Destination)|seed|-|-|keep-local|$localHash") | Out-Null
            continue
        }

        if ($action.State -in @("SIDECAR", "CONFLICT")) {
            if (Test-Path -LiteralPath $originalFull -PathType Leaf) {
                $localHash = Get-NormalizedTextHash -Path $originalFull
                $lines.Add("artifact|$($artifact.Id)|$($artifact.Destination)|$($artifact.Ownership)|-|-|keep-local|$localHash") | Out-Null
            }
            continue
        }

        $lines.Add("artifact|$($artifact.Id)|$($artifact.Destination)|$($artifact.Ownership)|$PackVersion|$packHash|tracked|-") | Out-Null
    }

    $stateDirectory = Join-Path $TargetRoot ".agent-pack"
    $statePath = Join-Path $stateDirectory "state.txt"
    if ($DryRun) {
        Write-Host "STATE     $statePath (dry-run)"
        return
    }
    if (-not (Test-Path -LiteralPath $stateDirectory)) {
        New-Item -ItemType Directory -Force -Path $stateDirectory | Out-Null
    }
    $tempPath = Join-Path $stateDirectory "state.txt.tmp"
    [IO.File]::WriteAllText($tempPath, (($lines -join "`n") + "`n"), $Utf8NoBom)
    Move-Item -LiteralPath $tempPath -Destination $statePath -Force
    Write-Host ("STATE     {0}" -f $statePath)
}

function Install-ToRepository {
    param(
        [Parameter(Mandatory = $true)][string]$TargetRoot,
        [Parameter(Mandatory = $true)][string]$Kind,
        [Parameter(Mandatory = $true)][string]$PackVersion,
        [Parameter(Mandatory = $true)]$ManifestEntries,
        [Parameter(Mandatory = $true)]$ManifestByDestination,
        [Parameter(Mandatory = $true)]$ArtifactEntries
    )

    $profiles = Resolve-InstallProfiles -TargetRoot $TargetRoot -RequestedProfile $Profile
    $integrations = New-Object System.Collections.Generic.List[string]
    $integrations.Add("codex") | Out-Null
    foreach ($integration in (Get-StateRecords -TargetRoot $TargetRoot -Kind "integration")) {
        $integrations.Add($integration) | Out-Null
    }
    if ($IncludeClaude) {
        $integrations.Add("claude") | Out-Null
    }
    if ($IncludeGrokBuild) {
        $integrations.Add("grok") | Out-Null
    }
    $integrations = @($integrations | Select-Object -Unique)

    Write-Host ""
    Write-Host "Target: $TargetRoot"
    Write-Host "Workspace: $Kind"
    Write-Host "Profiles: $($profiles -join ', ')"
    Write-Host "Integrations: $($integrations -join ', ')"
    if ($DryRun) {
        Write-Host "Dry-run enabled: no files will be written."
    }
    if ($DiscoverOnly) {
        Write-Host "Discover-only: inspection complete, no files will be written."
        return
    }

    $requestedComponents = New-Object System.Collections.Generic.List[string]
    foreach ($requestedProfile in $profiles) {
        $requestedComponents.Add($requestedProfile)
        if ($integrations -contains "claude") {
            $requestedComponents.Add("claude-$requestedProfile")
        }
        if ($integrations -contains "grok") {
            $requestedComponents.Add("grok-$requestedProfile")
        }
    }

    $actions = New-Object System.Collections.Generic.List[object]
    foreach ($entry in $ManifestEntries) {
        if ($requestedComponents -notcontains $entry.Component) {
            continue
        }
        $source = [IO.Path]::GetFullPath((Join-Path $templateRootCanonical $entry.Source))
        $destination = [IO.Path]::GetFullPath((Join-Path $TargetRoot $entry.Destination))
        if (-not (Test-PathWithin $templateRootCanonical $source)) {
            throw "Manifest source path escapes the template root: $($entry.Source)"
        }
        if (-not (Test-PathWithin $TargetRoot $destination)) {
            throw "Manifest destination path escapes the repository root: $($entry.Destination)"
        }
        Add-CopyAction -Actions $actions -Source $source -Destination $destination
    }

    foreach ($action in $actions) {
        Invoke-CopyAction -Action $action
    }

    Write-InstallState -TargetRoot $TargetRoot -PackVersion $PackVersion -Profiles $profiles -Integrations $integrations -ManifestByDestination $ManifestByDestination -ArtifactEntries $ArtifactEntries -Actions $actions

    $summary = $actions | Group-Object State | Sort-Object Name | ForEach-Object { "{0}={1}" -f $_.Name, $_.Count }
    Write-Host ("Summary: {0}" -f ($summary -join ", "))
    if (@($actions | Where-Object { $_.State -eq "CONFLICT" }).Count -gt 0) {
        Write-Warning "Conflicting .agent-pack.new files were preserved; review them before retrying."
    }
}

$repoRoot = Get-CanonicalDirectory -Path $RepoPath -Label "RepoPath"
$packRootCanonical = Get-CanonicalDirectory -Path $PackRoot -Label "Pack root"
$templateRootCanonical = Get-CanonicalDirectory -Path $TemplateRoot -Label "Template root"
$packVersion = Get-PackVersion

if ((Test-PathWithin $templateRootCanonical $repoRoot) -or (Test-PathWithin $repoRoot $templateRootCanonical) -or $repoRoot -eq $templateRootCanonical) {
    throw "RepoPath must not overlap the pack template."
}

if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf) -or -not (Test-Path -LiteralPath $ArtifactsPath -PathType Leaf)) {
    throw "Pack manifest or artifact metadata is missing."
}

$manifestEntries = @()
$manifestByDestination = @{}
Get-Content -LiteralPath $ManifestPath | ForEach-Object {
    $line = $_.Trim()
    if (-not $line -or $line.StartsWith("#")) {
        return
    }
    $parts = $line -split '\|'
    if ($parts.Count -notin 2, 3) {
        throw "Invalid manifest line: $line"
    }
    $component = $parts[0].Trim().ToLowerInvariant()
    $sourceRelativePath = $parts[1].Trim()
    $destinationRelativePath = if ($parts.Count -eq 3) { $parts[2].Trim() } else { $sourceRelativePath }
    $manifestEntries += [pscustomobject]@{
        Component = $component
        Source = $sourceRelativePath
        Destination = $destinationRelativePath
    }
    $manifestByDestination[$destinationRelativePath] = $sourceRelativePath
}

$artifactEntries = @()
Get-Content -LiteralPath $ArtifactsPath | ForEach-Object {
    $line = $_.Trim()
    if (-not $line -or $line.StartsWith("#")) {
        return
    }
    $parts = $line -split '\|'
    if ($parts.Count -ne 3) {
        throw "Invalid artifact metadata line: $line"
    }
    $artifactEntries += [pscustomobject]@{
        Id = $parts[0].Trim()
        Destination = $parts[1].Trim()
        Ownership = $parts[2].Trim().ToLowerInvariant()
    }
}

$targets = @()
if (Test-IsGitRoot $repoRoot) {
    if (-not $AllowNonGit) {
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
            throw "Git is required to validate RepoPath. Install Git or pass -AllowNonGit explicitly."
        }
        $gitPrefix = & git -C $repoRoot rev-parse --show-prefix 2>$null
        if ($LASTEXITCODE -ne 0) {
            throw "Unable to validate RepoPath against its Git root: $repoRoot"
        }
        if ($gitPrefix) {
            throw "RepoPath must be the Git root, not a subdirectory: $((& git -C $repoRoot rev-parse --show-toplevel).Trim())"
        }
    }
    $targets = @([pscustomobject]@{ Path = $repoRoot; Kind = "git-root" })
}
else {
    $discovered = @(Find-GitRoots -Root $repoRoot)
    if ($discovered.Count -gt 0) {
        $targets = @($discovered | ForEach-Object { [pscustomobject]@{ Path = $_; Kind = "discovered-git-root" } })
    }
    elseif ($AllowNonGit) {
        $targets = @([pscustomobject]@{ Path = $repoRoot; Kind = "non-git-folder" })
    }
    else {
        throw "RepoPath is not a Git root and no Git repositories were found underneath it. Point at a repository, a workspace folder that contains repositories, or pass -AllowNonGit."
    }
}

Write-Host "Installing .NET Agents Pack $packVersion"
Write-Host "Workspace path: $repoRoot"
Write-Host ("Repositories: {0}" -f (($targets | ForEach-Object { $_.Path }) -join ', '))
if ($IncludeClaude) {
    Write-Host "Claude project support enabled."
}
if ($IncludeGrokBuild) {
    Write-Host "Grok Build project support enabled."
}

foreach ($target in $targets) {
    Install-ToRepository -TargetRoot $target.Path -Kind $target.Kind -PackVersion $packVersion -ManifestEntries $manifestEntries -ManifestByDestination $manifestByDestination -ArtifactEntries $artifactEntries
}

if ($InstallGlobal -and -not $DiscoverOnly) {
    $codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME ".codex" }
    $codexHome = [IO.Path]::GetFullPath($codexHome)
    $globalActions = New-Object System.Collections.Generic.List[object]
    Add-CopyAction -Actions $globalActions -Source $GlobalGuidance -Destination (Join-Path $codexHome "AGENTS.md")
    foreach ($action in $globalActions) {
        Invoke-CopyAction -Action $action
    }
}
