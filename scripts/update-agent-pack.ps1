[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$RepoPath,

    [switch]$Check,
    [switch]$Apply,

    [string[]]$Integration = @(),

    [string[]]$AcceptPack = @(),
    [string[]]$AcceptMerge = @(),
    [string[]]$KeepLocal = @()
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ScriptDir = Split-Path -Parent $PSCommandPath
$PackRoot = Split-Path -Parent $ScriptDir
$TemplateRoot = Join-Path $PackRoot "repo-template"
$ManifestPath = Join-Path $PackRoot "pack-manifest.txt"
$ArtifactsPath = Join-Path $PackRoot "pack-artifacts.txt"
$VersionPath = Join-Path $PackRoot "pack-version.txt"
$CompatibilityRoot = Join-Path $PackRoot "compat\releases"
$StateRelativePath = ".agent-pack/state.txt"
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$Utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)
$PathComparison = if ($env:OS -eq "Windows_NT") { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }

function Get-CanonicalDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$Label = "Path"
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "$Label is not a directory: $Path"
    }

    return (Resolve-Path -LiteralPath $Path).Path
}

function Test-PathWithinOrEqual {
    param(
        [Parameter(Mandatory = $true)][string]$Parent,
        [Parameter(Mandatory = $true)][string]$Child
    )

    $parentFull = [IO.Path]::GetFullPath($Parent).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $childFull = [IO.Path]::GetFullPath($Child).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    if ($childFull.Equals($parentFull, $PathComparison)) {
        return $true
    }

    $prefix = $parentFull + [IO.Path]::DirectorySeparatorChar
    return $childFull.StartsWith($prefix, $PathComparison)
}

function Assert-NoReparsePoint {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$Label = "Path"
    )

    $rootFull = [IO.Path]::GetFullPath($Root)
    $cursor = [IO.Path]::GetFullPath($Path)
    while (Test-PathWithinOrEqual -Parent $rootFull -Child $cursor) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "$Label crosses a reparse point and cannot be reconciled safely: $cursor"
            }
        }

        if ($cursor.Equals($rootFull, $PathComparison)) {
            break
        }

        $parent = Split-Path -Parent $cursor
        if (-not $parent -or $parent.Equals($cursor, $PathComparison)) {
            break
        }
        $cursor = $parent
    }
}

function Resolve-SafeRelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [string]$Label = "Path",
        [switch]$CheckReparsePoint
    )

    if (-not $RelativePath -or $RelativePath.Contains("|") -or $RelativePath.Contains("`r") -or $RelativePath.Contains("`n")) {
        throw "$Label is empty or contains an unsupported character: '$RelativePath'"
    }
    if ([IO.Path]::IsPathRooted($RelativePath)) {
        throw "$Label must be relative: $RelativePath"
    }

    $platformPath = $RelativePath.Replace("/", [IO.Path]::DirectorySeparatorChar).Replace("\", [IO.Path]::DirectorySeparatorChar)
    $fullPath = [IO.Path]::GetFullPath((Join-Path $Root $platformPath))
    if (-not (Test-PathWithinOrEqual -Parent $Root -Child $fullPath) -or $fullPath.Equals([IO.Path]::GetFullPath($Root), $PathComparison)) {
        throw "$Label escapes its allowed root: $RelativePath"
    }

    if ($CheckReparsePoint) {
        Assert-NoReparsePoint -Root $Root -Path $fullPath -Label $Label
    }

    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $relative = $fullPath.Substring($rootFull.Length + 1).Replace("\", "/")
    return [pscustomobject]@{
        Relative = $relative
        Full = $fullPath
    }
}

function Get-DataLines {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required Agent Pack metadata is missing: $Path"
    }

    return @(
        Get-Content -LiteralPath $Path -Encoding UTF8 | ForEach-Object {
            $line = $_.Trim()
            if ($line -and -not $line.StartsWith("#")) {
                $line
            }
        }
    )
}

function Test-SemanticVersion {
    param([string]$Value)
    return [bool]($Value -match '^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$')
}

function Get-PackVersion {
    param([Parameter(Mandatory = $true)][string]$Path)

    $lines = @(Get-DataLines -Path $Path)
    if ($lines.Count -ne 1) {
        throw "pack-version.txt must contain exactly one version record."
    }

    $value = $lines[0]
    if ($value -match '^version\|(.+)$') {
        $value = $Matches[1].Trim()
    }
    if (-not (Test-SemanticVersion $value)) {
        throw "Invalid Agent Pack version: $value"
    }
    return $value
}

function Get-NormalizedTextHash {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Cannot hash a missing file: $Path"
    }

    $bytes = [IO.File]::ReadAllBytes($Path)
    $offset = 0
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $offset = 3
    }

    try {
        $text = $Utf8Strict.GetString($bytes, $offset, $bytes.Length - $offset)
    }
    catch {
        throw "Agent Pack artifacts must be valid UTF-8 text: $Path"
    }

    $normalized = $text.Replace("`r`n", "`n").Replace("`r", "`n")
    $normalizedBytes = $Utf8NoBom.GetBytes($normalized)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($normalizedBytes))).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Normalize-IdSet {
    param(
        [string[]]$Values,
        [string]$Label
    )

    $set = @{}
    foreach ($value in $Values) {
        foreach ($item in ($value -split ",")) {
            $normalized = $item.Trim().ToLowerInvariant()
            if (-not $normalized) {
                continue
            }
            if ($normalized -notmatch '^[a-z0-9][a-z0-9._-]*$') {
                throw "$Label contains an invalid artifact id: $item"
            }
            $set[$normalized] = $true
        }
    }
    return $set
}

function Read-PackManifest {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$TemplateRootPath,
        [Parameter(Mandatory = $true)][string]$RepositoryRoot
    )

    $entries = New-Object System.Collections.Generic.List[object]
    $byDestination = @{}
    foreach ($line in (Get-DataLines -Path $Path)) {
        $parts = $line -split '\|'
        if ($parts.Count -notin 2, 3) {
            throw "Invalid pack manifest line: $line"
        }

        $component = $parts[0].Trim().ToLowerInvariant()
        $sourceValue = $parts[1].Trim()
        $destinationValue = if ($parts.Count -eq 3) { $parts[2].Trim() } else { $sourceValue }
        if ($component -notmatch '^[a-z0-9][a-z0-9-]*$') {
            throw "Invalid manifest component: $component"
        }

        $source = Resolve-SafeRelativePath -Root $TemplateRootPath -RelativePath $sourceValue -Label "Manifest source" -CheckReparsePoint
        $destination = Resolve-SafeRelativePath -Root $RepositoryRoot -RelativePath $destinationValue -Label "Manifest destination" -CheckReparsePoint
        if (-not (Test-Path -LiteralPath $source.Full -PathType Leaf)) {
            throw "Manifest source is missing: $($source.Relative)"
        }
        if ($byDestination.ContainsKey($destination.Relative)) {
            throw "Manifest destination appears more than once: $($destination.Relative)"
        }

        $entry = [pscustomobject]@{
            Component = $component
            Source = $source.Relative
            SourceFull = $source.Full
            Destination = $destination.Relative
            DestinationFull = $destination.Full
        }
        $entries.Add($entry) | Out-Null
        $byDestination[$destination.Relative] = $entry
    }

    return [pscustomobject]@{
        Entries = $entries.ToArray()
        ByDestination = $byDestination
    }
}

function Read-PackArtifacts {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Manifest,
        [Parameter(Mandatory = $true)][string]$RepositoryRoot
    )

    $entries = New-Object System.Collections.Generic.List[object]
    $byId = @{}
    $byDestination = @{}
    foreach ($line in (Get-DataLines -Path $Path)) {
        $parts = $line -split '\|'
        if ($parts.Count -ne 3) {
            throw "Invalid pack artifact line: $line"
        }

        $id = $parts[0].Trim().ToLowerInvariant()
        $destination = Resolve-SafeRelativePath -Root $RepositoryRoot -RelativePath $parts[1].Trim() -Label "Artifact destination" -CheckReparsePoint
        $ownership = $parts[2].Trim().ToLowerInvariant()
        if ($id -notmatch '^[a-z0-9][a-z0-9._-]*$') {
            throw "Invalid artifact id: $id"
        }
        if ($ownership -notin @("managed", "merge", "seed")) {
            throw "Invalid ownership '$ownership' for artifact '$id'."
        }
        if ($byId.ContainsKey($id)) {
            throw "Artifact id appears more than once: $id"
        }
        if ($byDestination.ContainsKey($destination.Relative)) {
            throw "Artifact destination appears more than once: $($destination.Relative)"
        }
        if (-not $Manifest.ByDestination.ContainsKey($destination.Relative)) {
            throw "Artifact '$id' has no matching manifest destination: $($destination.Relative)"
        }

        $manifestEntry = $Manifest.ByDestination[$destination.Relative]
        $entry = [pscustomobject]@{
            Id = $id
            Destination = $destination.Relative
            DestinationFull = $destination.Full
            Ownership = $ownership
            Component = $manifestEntry.Component
            Source = $manifestEntry.Source
            SourceFull = $manifestEntry.SourceFull
            DesiredHash = Get-NormalizedTextHash -Path $manifestEntry.SourceFull
        }
        $entries.Add($entry) | Out-Null
        $byId[$id] = $entry
        $byDestination[$destination.Relative] = $entry
    }

    foreach ($manifestEntry in $Manifest.Entries) {
        if (-not $byDestination.ContainsKey($manifestEntry.Destination)) {
            throw "Manifest destination has no artifact metadata: $($manifestEntry.Destination)"
        }
    }

    return [pscustomobject]@{
        Entries = $entries.ToArray()
        ById = $byId
        ByDestination = $byDestination
    }
}

function Read-CompatibilityCatalog {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RepositoryRoot
    )

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        throw "Compatibility catalog directory is missing: $Root"
    }

    $entries = New-Object System.Collections.Generic.List[object]
    $byIdentity = @{}
    $byArtifact = @{}
    $releaseFiles = @(Get-ChildItem -LiteralPath $Root -File -Filter "*.txt" | Sort-Object Name)
    if ($releaseFiles.Count -eq 0) {
        throw "Compatibility catalog contains no release files: $Root"
    }

    foreach ($releaseFile in $releaseFiles) {
        $version = [IO.Path]::GetFileNameWithoutExtension($releaseFile.Name)
        if (-not (Test-SemanticVersion $version)) {
            throw "Compatibility release filename is not a semantic version: $($releaseFile.Name)"
        }

        foreach ($line in (Get-DataLines -Path $releaseFile.FullName)) {
            $parts = $line -split '\|'
            if ($parts.Count -ne 3) {
                throw "Invalid compatibility record in '$($releaseFile.Name)': $line"
            }

            $id = $parts[0].Trim().ToLowerInvariant()
            $destination = Resolve-SafeRelativePath -Root $RepositoryRoot -RelativePath $parts[1].Trim() -Label "Compatibility destination" -CheckReparsePoint
            $hash = $parts[2].Trim().ToLowerInvariant()
            if ($id -notmatch '^[a-z0-9][a-z0-9._-]*$' -or $hash -notmatch '^[a-f0-9]{64}$') {
                throw "Invalid compatibility record in '$($releaseFile.Name)': $line"
            }

            $identity = "$version|$id|$($destination.Relative)|$hash"
            if ($byIdentity.ContainsKey($identity)) {
                throw "Duplicate compatibility record: $identity"
            }

            $entry = [pscustomobject]@{
                Version = $version
                Id = $id
                Destination = $destination.Relative
                DestinationFull = $destination.Full
                Hash = $hash
            }
            $entries.Add($entry) | Out-Null
            $byIdentity[$identity] = $entry
            if (-not $byArtifact.ContainsKey($id)) {
                $byArtifact[$id] = New-Object System.Collections.Generic.List[object]
            }
            $byArtifact[$id].Add($entry) | Out-Null
        }
    }

    return [pscustomobject]@{
        Entries = $entries.ToArray()
        ByIdentity = $byIdentity
        ByArtifact = $byArtifact
    }
}

function Test-TrustedBaseline {
    param(
        [Parameter(Mandatory = $true)][string]$Version,
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][string]$Hash,
        [Parameter(Mandatory = $true)][string]$CurrentVersion,
        [Parameter(Mandatory = $true)]$CurrentArtifacts,
        [Parameter(Mandatory = $true)]$Compatibility
    )

    if ($Version -eq $CurrentVersion -and $CurrentArtifacts.ById.ContainsKey($Id)) {
        $current = $CurrentArtifacts.ById[$Id]
        if ($current.Destination -eq $Destination -and $current.DesiredHash -eq $Hash) {
            return $true
        }
    }

    return $Compatibility.ByIdentity.ContainsKey("$Version|$Id|$Destination|$Hash")
}

function Read-AgentPackState {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$CurrentVersion,
        [Parameter(Mandatory = $true)]$CurrentArtifacts,
        [Parameter(Mandatory = $true)]$Compatibility
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Agent Pack state is not a file: $Path"
    }
    Assert-NoReparsePoint -Root $RepositoryRoot -Path $Path -Label "Agent Pack state"

    $version = $null
    $profiles = New-Object System.Collections.Generic.List[string]
    $integrations = New-Object System.Collections.Generic.List[string]
    $artifacts = @{}
    foreach ($line in (Get-DataLines -Path $Path)) {
        $parts = $line -split '\|'
        $recordType = $parts[0].Trim().ToLowerInvariant()
        switch ($recordType) {
            "version" {
                if ($parts.Count -ne 2 -or $version) {
                    throw "Invalid or duplicate version state record: $line"
                }
                $version = $parts[1].Trim()
                if (-not (Test-SemanticVersion $version)) {
                    throw "Invalid state version: $version"
                }
            }
            "profile" {
                if ($parts.Count -ne 2) {
                    throw "Invalid profile state record: $line"
                }
                $profile = $parts[1].Trim().ToLowerInvariant()
                if ($profile -notmatch '^[a-z0-9][a-z0-9-]*$' -or $profiles -contains $profile) {
                    throw "Invalid or duplicate state profile: $profile"
                }
                $profiles.Add($profile) | Out-Null
            }
            "integration" {
                if ($parts.Count -ne 2) {
                    throw "Invalid integration state record: $line"
                }
                $integration = $parts[1].Trim().ToLowerInvariant()
                if ($integration -notin @("codex", "claude", "grok") -or $integrations -contains $integration) {
                    throw "Invalid or duplicate state integration: $integration"
                }
                $integrations.Add($integration) | Out-Null
            }
            "artifact" {
                if ($parts.Count -ne 8) {
                    throw "Invalid artifact state record: $line"
                }

                $id = $parts[1].Trim().ToLowerInvariant()
                $destination = Resolve-SafeRelativePath -Root $RepositoryRoot -RelativePath $parts[2].Trim() -Label "State artifact destination" -CheckReparsePoint
                $ownership = $parts[3].Trim().ToLowerInvariant()
                $baselineVersion = $parts[4].Trim()
                $baselineHash = $parts[5].Trim().ToLowerInvariant()
                $mode = $parts[6].Trim().ToLowerInvariant()
                $localHash = $parts[7].Trim().ToLowerInvariant()
                if ($id -notmatch '^[a-z0-9][a-z0-9._-]*$' -or $artifacts.ContainsKey($id)) {
                    throw "Invalid or duplicate state artifact id: $id"
                }
                if ($ownership -notin @("managed", "merge", "seed")) {
                    throw "Invalid state ownership for '$id': $ownership"
                }
                if ($mode -notin @("tracked", "merged", "keep-local", "deleted-local")) {
                    throw "Invalid state mode for '$id': $mode"
                }
                if ($localHash -ne "-" -and $localHash -notmatch '^[a-f0-9]{64}$') {
                    throw "Invalid local hash for state artifact '$id'."
                }

                $knownPath = $false
                if ($CurrentArtifacts.ById.ContainsKey($id) -and $CurrentArtifacts.ById[$id].Destination -eq $destination.Relative) {
                    $knownPath = $true
                }
                if (-not $knownPath -and $Compatibility.ByArtifact.ContainsKey($id)) {
                    foreach ($compatEntry in $Compatibility.ByArtifact[$id]) {
                        if ($compatEntry.Destination -eq $destination.Relative) {
                            $knownPath = $true
                            break
                        }
                    }
                }
                if (-not $knownPath) {
                    throw "State artifact '$id' is not present in current or historical trusted metadata."
                }

                if ($mode -in @("tracked", "merged")) {
                    if (-not (Test-SemanticVersion $baselineVersion) -or $baselineHash -notmatch '^[a-f0-9]{64}$') {
                        throw "State artifact '$id' has an invalid managed baseline."
                    }
                    if (-not (Test-TrustedBaseline -Version $baselineVersion -Id $id -Destination $destination.Relative -Hash $baselineHash -CurrentVersion $CurrentVersion -CurrentArtifacts $CurrentArtifacts -Compatibility $Compatibility)) {
                        throw "State artifact '$id' does not match a trusted Agent Pack release."
                    }
                    if ($mode -eq "tracked" -and $localHash -ne "-") {
                        throw "Tracked state artifact '$id' must not have a local hash."
                    }
                    if ($mode -eq "merged" -and ($ownership -ne "merge" -or $localHash -eq "-")) {
                        throw "Merged state artifact '$id' must have merge ownership and a local hash."
                    }
                }
                else {
                    if ($baselineVersion -ne "-" -or $baselineHash -ne "-") {
                        throw "Local override state artifact '$id' must not claim a pack baseline."
                    }
                    if ($mode -eq "deleted-local" -and $localHash -ne "-") {
                        throw "Deleted-local state artifact '$id' must not have a local hash."
                    }
                }

                $artifacts[$id] = [pscustomobject]@{
                    Id = $id
                    Destination = $destination.Relative
                    DestinationFull = $destination.Full
                    Ownership = $ownership
                    BaselineVersion = $baselineVersion
                    BaselineHash = $baselineHash
                    Mode = $mode
                    LocalHash = $localHash
                }
            }
            default {
                throw "Unknown Agent Pack state record: $line"
            }
        }
    }

    if (-not $version -or $profiles.Count -eq 0 -or $integrations.Count -eq 0) {
        throw "Agent Pack state must contain version, profiles and integrations."
    }

    return [pscustomobject]@{
        Version = $version
        Profiles = $profiles.ToArray()
        Integrations = $integrations.ToArray()
        Artifacts = $artifacts
    }
}

function Get-CurrentFileStatus {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$RepositoryRoot
    )

    Assert-NoReparsePoint -Root $RepositoryRoot -Path $Path -Label "Repository destination"
    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{ Kind = "missing"; Hash = "-" }
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{ Kind = "other"; Hash = "-" }
    }
    return [pscustomobject]@{
        Kind = "file"
        Hash = Get-NormalizedTextHash -Path $Path
    }
}

function Get-ProfileFromComponent {
    param([string]$Component)
    if ($Component.StartsWith("claude-")) {
        return $Component.Substring("claude-".Length)
    }
    if ($Component.StartsWith("grok-")) {
        return $Component.Substring("grok-".Length)
    }
    return $Component
}

function Get-EffectiveSelection {
    param(
        $State,
        [Parameter(Mandatory = $true)]$CurrentArtifacts,
        [Parameter(Mandatory = $true)]$Compatibility,
        [Parameter(Mandatory = $true)][string]$RepositoryRoot
    )

    if ($State) {
        return [pscustomobject]@{
            Profiles = @($State.Profiles)
            Integrations = @($State.Integrations)
            Adopted = $false
        }
    }

    $hasTrustedEvidence = $false
    foreach ($artifact in $CurrentArtifacts.Entries) {
        $status = Get-CurrentFileStatus -Path $artifact.DestinationFull -RepositoryRoot $RepositoryRoot
        if ($status.Kind -ne "file" -or $artifact.Ownership -eq "seed") {
            continue
        }
        if ($status.Hash -eq $artifact.DesiredHash) {
            $hasTrustedEvidence = $true
            break
        }
        if ($Compatibility.ByArtifact.ContainsKey($artifact.Id)) {
            foreach ($compatEntry in $Compatibility.ByArtifact[$artifact.Id]) {
                if ($compatEntry.Destination -eq $artifact.Destination -and $compatEntry.Hash -eq $status.Hash) {
                    $hasTrustedEvidence = $true
                    break
                }
            }
        }
        if ($hasTrustedEvidence) {
            break
        }
    }
    if (-not $hasTrustedEvidence) {
        throw "No trusted Agent Pack installation evidence was found. Use the installer for a new repository."
    }

    $profiles = @{}
    $integrations = @{ codex = $true }
    foreach ($artifact in $CurrentArtifacts.Entries) {
        $status = Get-CurrentFileStatus -Path $artifact.DestinationFull -RepositoryRoot $RepositoryRoot
        if ($status.Kind -eq "missing") {
            continue
        }

        $profile = Get-ProfileFromComponent $artifact.Component
        $profiles[$profile] = $true
        if ($artifact.Component.StartsWith("claude-")) {
            $integrations["claude"] = $true
        }
        elseif ($artifact.Component.StartsWith("grok-")) {
            $integrations["grok"] = $true
        }
    }
    $profiles["core"] = $true

    return [pscustomobject]@{
        Profiles = @($profiles.Keys | Sort-Object { if ($_ -eq "core") { "0" } else { "1$_" } })
        Integrations = @($integrations.Keys | Sort-Object)
        Adopted = $true
    }
}

function New-StateArtifact {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][string]$Ownership,
        [Parameter(Mandatory = $true)][string]$BaselineVersion,
        [Parameter(Mandatory = $true)][string]$BaselineHash,
        [Parameter(Mandatory = $true)][string]$Mode,
        [Parameter(Mandatory = $true)][string]$LocalHash
    )

    return [pscustomobject]@{
        Id = $Id
        Destination = $Destination
        Ownership = $Ownership
        BaselineVersion = $BaselineVersion
        BaselineHash = $BaselineHash
        Mode = $Mode
        LocalHash = $LocalHash
    }
}

function New-PlanAction {
    param(
        [Parameter(Mandatory = $true)][string]$Type,
        [Parameter(Mandatory = $true)][string]$ArtifactId,
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][string]$Ownership,
        [Parameter(Mandatory = $true)][string]$Reason,
        [bool]$Conflict,
        [string]$CurrentKind = "missing",
        [string]$CurrentHash = "-",
        [string]$SourceFull = "",
        [string]$DestinationFull = "",
        $NextState = $null
    )

    return [pscustomobject]@{
        Type = $Type
        ArtifactId = $ArtifactId
        Destination = $Destination
        DestinationFull = $DestinationFull
        Ownership = $Ownership
        Reason = $Reason
        Conflict = $Conflict
        CurrentKind = $CurrentKind
        CurrentHash = $CurrentHash
        SourceFull = $SourceFull
        NextState = $NextState
    }
}

function Find-CompatibleBaseline {
    param(
        [Parameter(Mandatory = $true)]$Artifact,
        [Parameter(Mandatory = $true)][string]$Hash,
        [Parameter(Mandatory = $true)]$Compatibility
    )

    if (-not $Compatibility.ByArtifact.ContainsKey($Artifact.Id)) {
        return $null
    }

    $matches = @(
        $Compatibility.ByArtifact[$Artifact.Id] |
            Where-Object { $_.Destination -eq $Artifact.Destination -and $_.Hash -eq $Hash } |
            Sort-Object Version -Descending
    )
    if ($matches.Count -eq 0) {
        return $null
    }
    return $matches[0]
}

function Get-ReconcilePlan {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$CurrentVersion,
        [Parameter(Mandatory = $true)]$CurrentArtifacts,
        [Parameter(Mandatory = $true)]$Compatibility,
        $State,
        [Parameter(Mandatory = $true)]$Selection,
        [Parameter(Mandatory = $true)]$AcceptPackSet,
        [Parameter(Mandatory = $true)]$AcceptMergeSet,
        [Parameter(Mandatory = $true)]$KeepLocalSet
    )

    $actions = New-Object System.Collections.Generic.List[object]
    $desiredComponents = @{}
    foreach ($profile in $Selection.Profiles) {
        $desiredComponents[$profile] = $true
        if ($Selection.Integrations -contains "claude") {
            $desiredComponents["claude-$profile"] = $true
        }
        if ($Selection.Integrations -contains "grok") {
            $desiredComponents["grok-$profile"] = $true
        }
    }
    $desiredArtifacts = @(
        $CurrentArtifacts.Entries | Where-Object { $desiredComponents.ContainsKey($_.Component) }
    )
    $desiredIds = @{}
    foreach ($artifact in $desiredArtifacts) {
        $desiredIds[$artifact.Id] = $true
    }

    $stateArtifacts = if ($State) { $State.Artifacts } else { @{} }
    $handledResolutionIds = @{}

    foreach ($artifact in $desiredArtifacts) {
        $record = if ($stateArtifacts.ContainsKey($artifact.Id)) { $stateArtifacts[$artifact.Id] } else { $null }
        $status = Get-CurrentFileStatus -Path $artifact.DestinationFull -RepositoryRoot $RepositoryRoot
        $acceptPack = $AcceptPackSet.ContainsKey($artifact.Id)
        $acceptMerge = $AcceptMergeSet.ContainsKey($artifact.Id)
        $keepLocal = $KeepLocalSet.ContainsKey($artifact.Id)
        if ($acceptPack -or $acceptMerge -or $keepLocal) {
            $handledResolutionIds[$artifact.Id] = $true
        }

        if ($record -and -not $record.Destination.Equals($artifact.Destination, [StringComparison]::Ordinal)) {
            if ($env:OS -eq "Windows_NT" -and
                $record.DestinationFull.Equals($artifact.DestinationFull, [StringComparison]::OrdinalIgnoreCase) -and
                -not $record.DestinationFull.Equals($artifact.DestinationFull, [StringComparison]::Ordinal)) {
                throw "Case-only artifact rename requires a manual two-step migration on Windows: $($artifact.Id)"
            }
            $oldStatus = Get-CurrentFileStatus -Path $record.DestinationFull -RepositoryRoot $RepositoryRoot

            if ($record.Mode -in @("keep-local", "deleted-local") -and -not $acceptPack -and -not $acceptMerge -and -not $keepLocal) {
                $actions.Add((New-PlanAction -Type "KEEP_LOCAL" -ArtifactId $record.Id -Destination $record.Destination -DestinationFull $record.DestinationFull -Ownership $record.Ownership -Reason "persisted local override remains at the old destination after a pack rename" -Conflict $false -CurrentKind $oldStatus.Kind -CurrentHash $oldStatus.Hash -NextState $record)) | Out-Null
                continue
            }

            if ($artifact.Ownership -eq "seed") {
                if ($acceptPack -or $acceptMerge) {
                    throw "Seed artifact '$($artifact.Id)' cannot move automatically or accept pack replacement."
                }
                if ($keepLocal) {
                    $oldMode = if ($oldStatus.Kind -eq "missing") { "deleted-local" } else { "keep-local" }
                    $oldLocalHash = if ($oldStatus.Kind -eq "file") { $oldStatus.Hash } else { "-" }
                    $next = New-StateArtifact -Id $record.Id -Destination $record.Destination -Ownership "seed" -BaselineVersion "-" -BaselineHash "-" -Mode $oldMode -LocalHash $oldLocalHash
                    $actions.Add((New-PlanAction -Type "KEEP_LOCAL" -ArtifactId $record.Id -Destination $record.Destination -DestinationFull $record.DestinationFull -Ownership "seed" -Reason "renamed seed explicitly preserved at its repository-owned path" -Conflict $false -CurrentKind $oldStatus.Kind -CurrentHash $oldStatus.Hash -NextState $next)) | Out-Null
                }
                else {
                    $actions.Add((New-PlanAction -Type "CONFLICT" -ArtifactId $artifact.Id -Destination $record.Destination -DestinationFull $record.DestinationFull -Ownership "seed" -Reason "seed destination changed; use KeepLocal to preserve the repository-owned file" -Conflict $true -CurrentKind $oldStatus.Kind -CurrentHash $oldStatus.Hash)) | Out-Null
                }
                continue
            }

            if ($keepLocal) {
                $oldMode = if ($oldStatus.Kind -eq "missing") { "deleted-local" } else { "keep-local" }
                $oldLocalHash = if ($oldStatus.Kind -eq "file") { $oldStatus.Hash } else { "-" }
                $next = New-StateArtifact -Id $record.Id -Destination $record.Destination -Ownership $record.Ownership -BaselineVersion "-" -BaselineHash "-" -Mode $oldMode -LocalHash $oldLocalHash
                $actions.Add((New-PlanAction -Type "KEEP_LOCAL" -ArtifactId $record.Id -Destination $record.Destination -DestinationFull $record.DestinationFull -Ownership $record.Ownership -Reason "renamed artifact explicitly preserved at its old path" -Conflict $false -CurrentKind $oldStatus.Kind -CurrentHash $oldStatus.Hash -NextState $next)) | Out-Null
                continue
            }

            if ($oldStatus.Kind -eq "other" -or $status.Kind -eq "other") {
                $actions.Add((New-PlanAction -Type "BLOCK" -ArtifactId $artifact.Id -Destination $artifact.Destination -DestinationFull $artifact.DestinationFull -Ownership $artifact.Ownership -Reason "artifact rename crosses a destination that is not a regular file" -Conflict $true -CurrentKind $status.Kind -CurrentHash $status.Hash)) | Out-Null
                continue
            }

            if ($acceptMerge) {
                if ($artifact.Ownership -ne "merge") {
                    throw "AcceptMerge is valid only for merge artifacts: $($artifact.Id)"
                }
                if ($status.Kind -ne "file") {
                    throw "AcceptMerge for a renamed artifact requires the manually merged file at the new destination: $($artifact.Id)"
                }
                if ($oldStatus.Kind -eq "file") {
                    $actions.Add((New-PlanAction -Type "RETIRE" -ArtifactId $artifact.Id -Destination $record.Destination -DestinationFull $record.DestinationFull -Ownership $record.Ownership -Reason "old path retired after explicit rename merge" -Conflict $false -CurrentKind $oldStatus.Kind -CurrentHash $oldStatus.Hash)) | Out-Null
                }
                $next = New-StateArtifact -Id $artifact.Id -Destination $artifact.Destination -Ownership "merge" -BaselineVersion $CurrentVersion -BaselineHash $artifact.DesiredHash -Mode "merged" -LocalHash $status.Hash
                $actions.Add((New-PlanAction -Type "ACCEPT_MERGE" -ArtifactId $artifact.Id -Destination $artifact.Destination -DestinationFull $artifact.DestinationFull -Ownership "merge" -Reason "manual merge at renamed destination explicitly accepted" -Conflict $false -CurrentKind $status.Kind -CurrentHash $status.Hash -NextState $next)) | Out-Null
                continue
            }

            if ($acceptPack) {
                if ($oldStatus.Kind -eq "file") {
                    $actions.Add((New-PlanAction -Type "RETIRE" -ArtifactId $artifact.Id -Destination $record.Destination -DestinationFull $record.DestinationFull -Ownership $record.Ownership -Reason "old path archived before explicit pack rename" -Conflict $false -CurrentKind $oldStatus.Kind -CurrentHash $oldStatus.Hash)) | Out-Null
                }
                $next = New-StateArtifact -Id $artifact.Id -Destination $artifact.Destination -Ownership $artifact.Ownership -BaselineVersion $CurrentVersion -BaselineHash $artifact.DesiredHash -Mode "tracked" -LocalHash "-"
                $actions.Add((New-PlanAction -Type "WRITE_PACK" -ArtifactId $artifact.Id -Destination $artifact.Destination -DestinationFull $artifact.DestinationFull -Ownership $artifact.Ownership -Reason "renamed pack destination explicitly accepted" -Conflict $false -CurrentKind $status.Kind -CurrentHash $status.Hash -SourceFull $artifact.SourceFull -NextState $next)) | Out-Null
                continue
            }

            if ($oldStatus.Kind -eq "missing" -and $status.Kind -eq "file" -and $status.Hash -eq $artifact.DesiredHash) {
                $next = New-StateArtifact -Id $artifact.Id -Destination $artifact.Destination -Ownership $artifact.Ownership -BaselineVersion $CurrentVersion -BaselineHash $artifact.DesiredHash -Mode "tracked" -LocalHash "-"
                $actions.Add((New-PlanAction -Type "ADOPT_RENAME" -ArtifactId $artifact.Id -Destination $artifact.Destination -DestinationFull $artifact.DestinationFull -Ownership $artifact.Ownership -Reason "artifact is already present only at the trusted new destination" -Conflict $false -CurrentKind $status.Kind -CurrentHash $status.Hash -NextState $next)) | Out-Null
                continue
            }

            $oldIsTrustedBaseline = $record.Mode -eq "tracked" -and $oldStatus.Kind -eq "file" -and $oldStatus.Hash -eq $record.BaselineHash
            if ($oldIsTrustedBaseline -and $status.Kind -eq "missing") {
                $actions.Add((New-PlanAction -Type "RETIRE" -ArtifactId $artifact.Id -Destination $record.Destination -DestinationFull $record.DestinationFull -Ownership $record.Ownership -Reason "unchanged old destination archived for stable-id rename" -Conflict $false -CurrentKind $oldStatus.Kind -CurrentHash $oldStatus.Hash)) | Out-Null
                $next = New-StateArtifact -Id $artifact.Id -Destination $artifact.Destination -Ownership $artifact.Ownership -BaselineVersion $CurrentVersion -BaselineHash $artifact.DesiredHash -Mode "tracked" -LocalHash "-"
                $actions.Add((New-PlanAction -Type "ADD_RENAMED" -ArtifactId $artifact.Id -Destination $artifact.Destination -DestinationFull $artifact.DestinationFull -Ownership $artifact.Ownership -Reason "stable-id artifact moved to its new destination" -Conflict $false -CurrentKind $status.Kind -CurrentHash $status.Hash -SourceFull $artifact.SourceFull -NextState $next)) | Out-Null
                continue
            }
            if ($oldIsTrustedBaseline -and $status.Kind -eq "file" -and $status.Hash -eq $artifact.DesiredHash) {
                $actions.Add((New-PlanAction -Type "RETIRE" -ArtifactId $artifact.Id -Destination $record.Destination -DestinationFull $record.DestinationFull -Ownership $record.Ownership -Reason "unchanged duplicate at old destination archived for stable-id rename" -Conflict $false -CurrentKind $oldStatus.Kind -CurrentHash $oldStatus.Hash)) | Out-Null
                $next = New-StateArtifact -Id $artifact.Id -Destination $artifact.Destination -Ownership $artifact.Ownership -BaselineVersion $CurrentVersion -BaselineHash $artifact.DesiredHash -Mode "tracked" -LocalHash "-"
                $actions.Add((New-PlanAction -Type "ADOPT_RENAME" -ArtifactId $artifact.Id -Destination $artifact.Destination -DestinationFull $artifact.DestinationFull -Ownership $artifact.Ownership -Reason "new destination already matches the current pack" -Conflict $false -CurrentKind $status.Kind -CurrentHash $status.Hash -NextState $next)) | Out-Null
                continue
            }

            $actions.Add((New-PlanAction -Type "CONFLICT" -ArtifactId $artifact.Id -Destination $artifact.Destination -DestinationFull $artifact.DestinationFull -Ownership $artifact.Ownership -Reason "artifact destination changed and old content or new destination is not safely attributable; use AcceptPack or KeepLocal" -Conflict $true -CurrentKind $status.Kind -CurrentHash $status.Hash)) | Out-Null
            continue
        }

        if ($artifact.Ownership -eq "seed") {
            if ($acceptPack -or $acceptMerge) {
                throw "Seed artifact '$($artifact.Id)' never accepts pack replacement or merge resolution."
            }
            if ($status.Kind -eq "other") {
                throw "Seed artifact destination is not a file: $($artifact.Destination)"
            }
            if ($status.Kind -eq "missing") {
                if ($record) {
                    $next = New-StateArtifact -Id $artifact.Id -Destination $artifact.Destination -Ownership "seed" -BaselineVersion "-" -BaselineHash "-" -Mode "deleted-local" -LocalHash "-"
                    $actions.Add((New-PlanAction -Type "PRESERVE_DELETED_SEED" -ArtifactId $artifact.Id -Destination $artifact.Destination -DestinationFull $artifact.DestinationFull -Ownership "seed" -Reason "repository-owned seed was deleted locally" -Conflict $false -CurrentKind $status.Kind -CurrentHash $status.Hash -NextState $next)) | Out-Null
                }
                else {
                    $next = New-StateArtifact -Id $artifact.Id -Destination $artifact.Destination -Ownership "seed" -BaselineVersion "-" -BaselineHash "-" -Mode "keep-local" -LocalHash $artifact.DesiredHash
                    $actions.Add((New-PlanAction -Type "ADD_SEED" -ArtifactId $artifact.Id -Destination $artifact.Destination -DestinationFull $artifact.DestinationFull -Ownership "seed" -Reason "new seed is absent" -Conflict $false -CurrentKind $status.Kind -CurrentHash $status.Hash -SourceFull $artifact.SourceFull -NextState $next)) | Out-Null
                }
            }
            else {
                $next = New-StateArtifact -Id $artifact.Id -Destination $artifact.Destination -Ownership "seed" -BaselineVersion "-" -BaselineHash "-" -Mode "keep-local" -LocalHash $status.Hash
                $actions.Add((New-PlanAction -Type "PRESERVE_SEED" -ArtifactId $artifact.Id -Destination $artifact.Destination -DestinationFull $artifact.DestinationFull -Ownership "seed" -Reason "seed is repository-owned after creation" -Conflict $false -CurrentKind $status.Kind -CurrentHash $status.Hash -NextState $next)) | Out-Null
            }
            continue
        }

        if ($status.Kind -eq "other") {
            if ($keepLocal) {
                $next = New-StateArtifact -Id $artifact.Id -Destination $artifact.Destination -Ownership $artifact.Ownership -BaselineVersion "-" -BaselineHash "-" -Mode "keep-local" -LocalHash "-"
                $actions.Add((New-PlanAction -Type "KEEP_LOCAL" -ArtifactId $artifact.Id -Destination $artifact.Destination -DestinationFull $artifact.DestinationFull -Ownership $artifact.Ownership -Reason "non-file destination explicitly preserved" -Conflict $false -CurrentKind $status.Kind -NextState $next)) | Out-Null
                continue
            }
            $actions.Add((New-PlanAction -Type "BLOCK" -ArtifactId $artifact.Id -Destination $artifact.Destination -DestinationFull $artifact.DestinationFull -Ownership $artifact.Ownership -Reason "destination exists but is not a regular file" -Conflict $true -CurrentKind $status.Kind)) | Out-Null
            continue
        }

        if ($keepLocal) {
            $mode = if ($status.Kind -eq "missing") { "deleted-local" } else { "keep-local" }
            $localHash = if ($status.Kind -eq "file") { $status.Hash } else { "-" }
            $next = New-StateArtifact -Id $artifact.Id -Destination $artifact.Destination -Ownership $artifact.Ownership -BaselineVersion "-" -BaselineHash "-" -Mode $mode -LocalHash $localHash
            $actions.Add((New-PlanAction -Type "KEEP_LOCAL" -ArtifactId $artifact.Id -Destination $artifact.Destination -DestinationFull $artifact.DestinationFull -Ownership $artifact.Ownership -Reason "explicit local override" -Conflict $false -CurrentKind $status.Kind -CurrentHash $status.Hash -NextState $next)) | Out-Null
            continue
        }

        if ($acceptMerge) {
            if ($artifact.Ownership -ne "merge") {
                throw "AcceptMerge is valid only for merge artifacts: $($artifact.Id)"
            }
            if ($status.Kind -ne "file") {
                throw "AcceptMerge requires an existing manually merged file: $($artifact.Id)"
            }
            $next = New-StateArtifact -Id $artifact.Id -Destination $artifact.Destination -Ownership "merge" -BaselineVersion $CurrentVersion -BaselineHash $artifact.DesiredHash -Mode "merged" -LocalHash $status.Hash
            $actions.Add((New-PlanAction -Type "ACCEPT_MERGE" -ArtifactId $artifact.Id -Destination $artifact.Destination -DestinationFull $artifact.DestinationFull -Ownership "merge" -Reason "manual merge explicitly accepted" -Conflict $false -CurrentKind $status.Kind -CurrentHash $status.Hash -NextState $next)) | Out-Null
            continue
        }

        if ($acceptPack) {
            $next = New-StateArtifact -Id $artifact.Id -Destination $artifact.Destination -Ownership $artifact.Ownership -BaselineVersion $CurrentVersion -BaselineHash $artifact.DesiredHash -Mode "tracked" -LocalHash "-"
            $actions.Add((New-PlanAction -Type "WRITE_PACK" -ArtifactId $artifact.Id -Destination $artifact.Destination -DestinationFull $artifact.DestinationFull -Ownership $artifact.Ownership -Reason "pack content explicitly accepted" -Conflict $false -CurrentKind $status.Kind -CurrentHash $status.Hash -SourceFull $artifact.SourceFull -NextState $next)) | Out-Null
            continue
        }

        if ($record -and $record.Mode -in @("keep-local", "deleted-local")) {
            $actions.Add((New-PlanAction -Type "KEEP_LOCAL" -ArtifactId $artifact.Id -Destination $record.Destination -DestinationFull $record.DestinationFull -Ownership $record.Ownership -Reason "persisted local override" -Conflict $false -CurrentKind $status.Kind -CurrentHash $status.Hash -NextState $record)) | Out-Null
            continue
        }

        if ($record -and $record.Mode -eq "merged") {
            if ($status.Kind -eq "file" -and $status.Hash -eq $record.LocalHash -and $artifact.DesiredHash -eq $record.BaselineHash) {
                $actions.Add((New-PlanAction -Type "KEEP_MERGED" -ArtifactId $artifact.Id -Destination $artifact.Destination -DestinationFull $artifact.DestinationFull -Ownership "merge" -Reason "accepted merge and pack baseline are unchanged" -Conflict $false -CurrentKind $status.Kind -CurrentHash $status.Hash -NextState $record)) | Out-Null
            }
            else {
                $actions.Add((New-PlanAction -Type "CONFLICT" -ArtifactId $artifact.Id -Destination $artifact.Destination -DestinationFull $artifact.DestinationFull -Ownership "merge" -Reason "accepted merge or pack baseline changed; merge again, AcceptPack, or KeepLocal" -Conflict $true -CurrentKind $status.Kind -CurrentHash $status.Hash)) | Out-Null
            }
            continue
        }

        if ($record) {
            if ($status.Kind -eq "missing") {
                $actions.Add((New-PlanAction -Type "CONFLICT" -ArtifactId $artifact.Id -Destination $artifact.Destination -DestinationFull $artifact.DestinationFull -Ownership $artifact.Ownership -Reason "previously managed artifact was deleted locally" -Conflict $true -CurrentKind $status.Kind)) | Out-Null
            }
            elseif ($status.Hash -eq $artifact.DesiredHash) {
                $next = New-StateArtifact -Id $artifact.Id -Destination $artifact.Destination -Ownership $artifact.Ownership -BaselineVersion $CurrentVersion -BaselineHash $artifact.DesiredHash -Mode "tracked" -LocalHash "-"
                $actions.Add((New-PlanAction -Type "KEEP" -ArtifactId $artifact.Id -Destination $artifact.Destination -DestinationFull $artifact.DestinationFull -Ownership $artifact.Ownership -Reason "already matches current pack" -Conflict $false -CurrentKind $status.Kind -CurrentHash $status.Hash -NextState $next)) | Out-Null
            }
            elseif ($status.Hash -eq $record.BaselineHash) {
                $next = New-StateArtifact -Id $artifact.Id -Destination $artifact.Destination -Ownership $artifact.Ownership -BaselineVersion $CurrentVersion -BaselineHash $artifact.DesiredHash -Mode "tracked" -LocalHash "-"
                $actions.Add((New-PlanAction -Type "UPDATE" -ArtifactId $artifact.Id -Destination $artifact.Destination -DestinationFull $artifact.DestinationFull -Ownership $artifact.Ownership -Reason "artifact is unchanged from its trusted baseline" -Conflict $false -CurrentKind $status.Kind -CurrentHash $status.Hash -SourceFull $artifact.SourceFull -NextState $next)) | Out-Null
            }
            else {
                $actions.Add((New-PlanAction -Type "CONFLICT" -ArtifactId $artifact.Id -Destination $artifact.Destination -DestinationFull $artifact.DestinationFull -Ownership $artifact.Ownership -Reason "local content differs from both baseline and current pack" -Conflict $true -CurrentKind $status.Kind -CurrentHash $status.Hash)) | Out-Null
            }
            continue
        }

        if ($status.Kind -eq "missing") {
            $next = New-StateArtifact -Id $artifact.Id -Destination $artifact.Destination -Ownership $artifact.Ownership -BaselineVersion $CurrentVersion -BaselineHash $artifact.DesiredHash -Mode "tracked" -LocalHash "-"
            $actions.Add((New-PlanAction -Type "ADD" -ArtifactId $artifact.Id -Destination $artifact.Destination -DestinationFull $artifact.DestinationFull -Ownership $artifact.Ownership -Reason "new pack artifact" -Conflict $false -CurrentKind $status.Kind -CurrentHash $status.Hash -SourceFull $artifact.SourceFull -NextState $next)) | Out-Null
        }
        elseif ($status.Hash -eq $artifact.DesiredHash) {
            $next = New-StateArtifact -Id $artifact.Id -Destination $artifact.Destination -Ownership $artifact.Ownership -BaselineVersion $CurrentVersion -BaselineHash $artifact.DesiredHash -Mode "tracked" -LocalHash "-"
            $actions.Add((New-PlanAction -Type "ADOPT" -ArtifactId $artifact.Id -Destination $artifact.Destination -DestinationFull $artifact.DestinationFull -Ownership $artifact.Ownership -Reason "matches current pack exactly" -Conflict $false -CurrentKind $status.Kind -CurrentHash $status.Hash -NextState $next)) | Out-Null
        }
        else {
            $compatBaseline = Find-CompatibleBaseline -Artifact $artifact -Hash $status.Hash -Compatibility $Compatibility
            if ($compatBaseline) {
                $next = New-StateArtifact -Id $artifact.Id -Destination $artifact.Destination -Ownership $artifact.Ownership -BaselineVersion $CurrentVersion -BaselineHash $artifact.DesiredHash -Mode "tracked" -LocalHash "-"
                $actions.Add((New-PlanAction -Type "UPDATE" -ArtifactId $artifact.Id -Destination $artifact.Destination -DestinationFull $artifact.DestinationFull -Ownership $artifact.Ownership -Reason "matches trusted release $($compatBaseline.Version)" -Conflict $false -CurrentKind $status.Kind -CurrentHash $status.Hash -SourceFull $artifact.SourceFull -NextState $next)) | Out-Null
            }
            else {
                $actions.Add((New-PlanAction -Type "CONFLICT" -ArtifactId $artifact.Id -Destination $artifact.Destination -DestinationFull $artifact.DestinationFull -Ownership $artifact.Ownership -Reason "existing file is not attributable to a trusted pack release" -Conflict $true -CurrentKind $status.Kind -CurrentHash $status.Hash)) | Out-Null
            }
        }
    }

    foreach ($record in @($stateArtifacts.Values | Sort-Object Id)) {
        if ($desiredIds.ContainsKey($record.Id)) {
            continue
        }

        $status = Get-CurrentFileStatus -Path $record.DestinationFull -RepositoryRoot $RepositoryRoot
        $acceptPack = $AcceptPackSet.ContainsKey($record.Id)
        $acceptMerge = $AcceptMergeSet.ContainsKey($record.Id)
        $keepLocal = $KeepLocalSet.ContainsKey($record.Id)
        if ($acceptPack -or $acceptMerge -or $keepLocal) {
            $handledResolutionIds[$record.Id] = $true
        }
        if ($acceptMerge) {
            throw "AcceptMerge is invalid for an artifact removed from the pack: $($record.Id)"
        }

        if ($record.Ownership -eq "seed" -or $record.Mode -in @("keep-local", "deleted-local") -or $keepLocal) {
            $mode = if ($status.Kind -eq "missing") { "deleted-local" } else { "keep-local" }
            $localHash = if ($status.Kind -eq "file") { $status.Hash } else { "-" }
            $next = New-StateArtifact -Id $record.Id -Destination $record.Destination -Ownership $record.Ownership -BaselineVersion "-" -BaselineHash "-" -Mode $mode -LocalHash $localHash
            $actions.Add((New-PlanAction -Type "KEEP_LOCAL" -ArtifactId $record.Id -Destination $record.Destination -DestinationFull $record.DestinationFull -Ownership $record.Ownership -Reason "removed seed or persisted local override is preserved" -Conflict $false -CurrentKind $status.Kind -CurrentHash $status.Hash -NextState $next)) | Out-Null
            continue
        }

        if ($status.Kind -eq "other") {
            $actions.Add((New-PlanAction -Type "BLOCK" -ArtifactId $record.Id -Destination $record.Destination -DestinationFull $record.DestinationFull -Ownership $record.Ownership -Reason "removed artifact destination is not a regular file" -Conflict $true -CurrentKind $status.Kind)) | Out-Null
        }
        elseif ($status.Kind -eq "missing") {
            $actions.Add((New-PlanAction -Type "DROP_STATE" -ArtifactId $record.Id -Destination $record.Destination -DestinationFull $record.DestinationFull -Ownership $record.Ownership -Reason "removed artifact is already absent" -Conflict $false -CurrentKind $status.Kind)) | Out-Null
        }
        elseif ($acceptPack) {
            $actions.Add((New-PlanAction -Type "RETIRE" -ArtifactId $record.Id -Destination $record.Destination -DestinationFull $record.DestinationFull -Ownership $record.Ownership -Reason "pack removal explicitly accepted" -Conflict $false -CurrentKind $status.Kind -CurrentHash $status.Hash)) | Out-Null
        }
        elseif ($record.Ownership -eq "managed" -and $record.Mode -eq "tracked" -and $status.Hash -eq $record.BaselineHash) {
            $actions.Add((New-PlanAction -Type "RETIRE" -ArtifactId $record.Id -Destination $record.Destination -DestinationFull $record.DestinationFull -Ownership $record.Ownership -Reason "unchanged artifact was removed from the pack" -Conflict $false -CurrentKind $status.Kind -CurrentHash $status.Hash)) | Out-Null
        }
        else {
            $actions.Add((New-PlanAction -Type "CONFLICT" -ArtifactId $record.Id -Destination $record.Destination -DestinationFull $record.DestinationFull -Ownership $record.Ownership -Reason "locally changed artifact was removed from the pack" -Conflict $true -CurrentKind $status.Kind -CurrentHash $status.Hash)) | Out-Null
        }
    }

    if (-not $State) {
        $historicalIds = @{}
        foreach ($compatEntry in $Compatibility.Entries) {
            if ($CurrentArtifacts.ById.ContainsKey($compatEntry.Id) -or $historicalIds.ContainsKey($compatEntry.Id)) {
                continue
            }
            $historicalIds[$compatEntry.Id] = $true
            $status = Get-CurrentFileStatus -Path $compatEntry.DestinationFull -RepositoryRoot $RepositoryRoot
            if ($status.Kind -eq "missing") {
                continue
            }

            $acceptPack = $AcceptPackSet.ContainsKey($compatEntry.Id)
            $acceptMerge = $AcceptMergeSet.ContainsKey($compatEntry.Id)
            $keepLocal = $KeepLocalSet.ContainsKey($compatEntry.Id)
            if ($acceptPack -or $acceptMerge -or $keepLocal) {
                $handledResolutionIds[$compatEntry.Id] = $true
            }
            if ($acceptMerge) {
                throw "AcceptMerge is invalid for a legacy artifact removed from the pack: $($compatEntry.Id)"
            }
            if ($keepLocal) {
                $localHash = if ($status.Kind -eq "file") { $status.Hash } else { "-" }
                $next = New-StateArtifact -Id $compatEntry.Id -Destination $compatEntry.Destination -Ownership "seed" -BaselineVersion "-" -BaselineHash "-" -Mode "keep-local" -LocalHash $localHash
                $actions.Add((New-PlanAction -Type "KEEP_LOCAL" -ArtifactId $compatEntry.Id -Destination $compatEntry.Destination -DestinationFull $compatEntry.DestinationFull -Ownership "seed" -Reason "legacy artifact explicitly preserved" -Conflict $false -CurrentKind $status.Kind -CurrentHash $status.Hash -NextState $next)) | Out-Null
            }
            elseif ($acceptPack -and $status.Kind -eq "file") {
                $actions.Add((New-PlanAction -Type "RETIRE" -ArtifactId $compatEntry.Id -Destination $compatEntry.Destination -DestinationFull $compatEntry.DestinationFull -Ownership "managed" -Reason "legacy pack removal explicitly accepted" -Conflict $false -CurrentKind $status.Kind -CurrentHash $status.Hash)) | Out-Null
            }
            else {
                $actions.Add((New-PlanAction -Type "CONFLICT" -ArtifactId $compatEntry.Id -Destination $compatEntry.Destination -DestinationFull $compatEntry.DestinationFull -Ownership "managed" -Reason "legacy-only artifact requires explicit AcceptPack or KeepLocal because historical ownership is unavailable" -Conflict $true -CurrentKind $status.Kind -CurrentHash $status.Hash)) | Out-Null
            }
        }
    }

    foreach ($setEntry in @($AcceptPackSet.Keys + $AcceptMergeSet.Keys + $KeepLocalSet.Keys | Select-Object -Unique)) {
        if (-not $handledResolutionIds.ContainsKey($setEntry)) {
            throw "Resolution references an artifact that is not part of this reconciliation: $setEntry"
        }
    }

    return [pscustomobject]@{
        Actions = $actions.ToArray()
        HasConflicts = @($actions | Where-Object { $_.Conflict }).Count -gt 0
        Profiles = @($Selection.Profiles)
        Integrations = @($Selection.Integrations)
        Adopted = $Selection.Adopted
    }
}

function Get-StateContent {
    param(
        [Parameter(Mandatory = $true)][string]$Version,
        [Parameter(Mandatory = $true)][string[]]$Profiles,
        [Parameter(Mandatory = $true)][string[]]$Integrations,
        [Parameter(Mandatory = $true)]$Actions
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("version|$Version") | Out-Null
    foreach ($profile in @($Profiles | Sort-Object { if ($_ -eq "core") { "0" } else { "1$_" } })) {
        $lines.Add("profile|$profile") | Out-Null
    }
    foreach ($integration in @($Integrations | Sort-Object)) {
        $lines.Add("integration|$integration") | Out-Null
    }

    $stateRecords = @(
        $Actions |
            Where-Object { $_.NextState } |
            ForEach-Object { $_.NextState } |
            Group-Object Id |
            ForEach-Object { $_.Group[-1] } |
            Sort-Object Id
    )
    foreach ($record in $stateRecords) {
        $lines.Add("artifact|$($record.Id)|$($record.Destination)|$($record.Ownership)|$($record.BaselineVersion)|$($record.BaselineHash)|$($record.Mode)|$($record.LocalHash)") | Out-Null
    }

    return (($lines -join "`n") + "`n")
}

function Get-AvailableArchivePath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$ArtifactId,
        [Parameter(Mandatory = $true)][string]$LeafName
    )

    $safeLeaf = if ($LeafName) { $LeafName } else { "artifact" }
    $candidate = Join-Path (Join-Path $Root $ArtifactId) $safeLeaf
    $counter = 1
    while (Test-Path -LiteralPath $candidate) {
        $candidate = Join-Path (Join-Path $Root $ArtifactId) "$safeLeaf-$counter"
        $counter++
    }
    return $candidate
}

function Write-StateAtomic {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        $existing = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8).Replace("`r`n", "`n").Replace("`r", "`n")
        if ($existing -eq $Content) {
            return
        }
    }

    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }
    $temporary = "$Path.tmp-$([Guid]::NewGuid().ToString('N'))"
    try {
        [IO.File]::WriteAllText($temporary, $Content, $Utf8NoBom)
        Move-Item -LiteralPath $temporary -Destination $Path -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporary) {
            Remove-Item -LiteralPath $temporary -Force
        }
    }
}

function Invoke-ReconcilePlan {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$CurrentVersion,
        [Parameter(Mandatory = $true)]$Plan,
        [Parameter(Mandatory = $true)][string]$StatePath
    )

    $stateRoot = Split-Path -Parent $StatePath
    if (-not (Test-Path -LiteralPath $stateRoot)) {
        New-Item -ItemType Directory -Force -Path $stateRoot | Out-Null
    }
    Assert-NoReparsePoint -Root $RepositoryRoot -Path $stateRoot -Label "Agent Pack state directory"

    $runtimeRoot = Join-Path $stateRoot ".runtime"
    if (-not (Test-Path -LiteralPath $runtimeRoot)) {
        New-Item -ItemType Directory -Force -Path $runtimeRoot | Out-Null
    }
    Assert-NoReparsePoint -Root $RepositoryRoot -Path $runtimeRoot -Label "Agent Pack runtime directory"
    $runtimeIgnorePath = Join-Path $runtimeRoot ".gitignore"
    Assert-NoReparsePoint -Root $RepositoryRoot -Path $runtimeIgnorePath -Label "Agent Pack runtime ignore file"
    $runtimeIgnoreContent = "*`n!.gitignore`n"
    if (Test-Path -LiteralPath $runtimeIgnorePath -PathType Leaf) {
        $existingRuntimeIgnore = [IO.File]::ReadAllText($runtimeIgnorePath, [Text.Encoding]::UTF8).Replace("`r`n", "`n").Replace("`r", "`n")
        if ($existingRuntimeIgnore -ne $runtimeIgnoreContent) {
            throw "Agent Pack runtime .gitignore has unexpected local content: $runtimeIgnorePath"
        }
    }
    else {
        [IO.File]::WriteAllText($runtimeIgnorePath, $runtimeIgnoreContent, $Utf8NoBom)
    }

    $lockPath = Join-Path $runtimeRoot "update.lock"
    Assert-NoReparsePoint -Root $RepositoryRoot -Path $lockPath -Label "Agent Pack update lock"
    $lockStream = $null
    $completed = New-Object System.Collections.Generic.List[object]
    try {
        try {
            $lockStream = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        }
        catch {
            throw "Another Agent Pack update is already running for this repository."
        }

        $backupRoot = Join-Path $runtimeRoot (Join-Path "backups" $CurrentVersion)
        $retiredRoot = Join-Path $runtimeRoot (Join-Path "retired" $CurrentVersion)
        Assert-NoReparsePoint -Root $RepositoryRoot -Path $backupRoot -Label "Agent Pack backup directory"
        Assert-NoReparsePoint -Root $RepositoryRoot -Path $retiredRoot -Label "Agent Pack retired directory"
        foreach ($action in $Plan.Actions) {
            if ($action.Type -notin @("ADD", "ADD_SEED", "ADD_RENAMED", "UPDATE", "WRITE_PACK", "RETIRE")) {
                continue
            }

            $current = Get-CurrentFileStatus -Path $action.DestinationFull -RepositoryRoot $RepositoryRoot
            if ($current.Kind -ne $action.CurrentKind -or ($current.Kind -eq "file" -and $current.Hash -ne $action.CurrentHash)) {
                throw "Repository content changed after planning: $($action.Destination)"
            }

            if ($action.Type -eq "RETIRE") {
                $archive = Get-AvailableArchivePath -Root $retiredRoot -ArtifactId $action.ArtifactId -LeafName (Split-Path -Leaf $action.DestinationFull)
                $archiveDirectory = Split-Path -Parent $archive
                if (-not (Test-Path -LiteralPath $archiveDirectory)) {
                    New-Item -ItemType Directory -Force -Path $archiveDirectory | Out-Null
                }
                Move-Item -LiteralPath $action.DestinationFull -Destination $archive
                $completed.Add([pscustomobject]@{ Kind = "retire"; Destination = $action.DestinationFull; Backup = $archive; DesiredHash = "-" }) | Out-Null
                continue
            }

            $expectedSourceHash = if ($action.Type -eq "ADD_SEED") { $action.NextState.LocalHash } else { $action.NextState.BaselineHash }
            if ((Get-NormalizedTextHash -Path $action.SourceFull) -ne $expectedSourceHash) {
                throw "Agent Pack source changed after planning: $($action.SourceFull)"
            }

            $destinationDirectory = Split-Path -Parent $action.DestinationFull
            if (-not (Test-Path -LiteralPath $destinationDirectory)) {
                New-Item -ItemType Directory -Force -Path $destinationDirectory | Out-Null
            }

            if ($current.Kind -eq "file") {
                $backup = Get-AvailableArchivePath -Root $backupRoot -ArtifactId $action.ArtifactId -LeafName (Split-Path -Leaf $action.DestinationFull)
                $backupDirectory = Split-Path -Parent $backup
                if (-not (Test-Path -LiteralPath $backupDirectory)) {
                    New-Item -ItemType Directory -Force -Path $backupDirectory | Out-Null
                }
                Copy-Item -LiteralPath $action.DestinationFull -Destination $backup -Force
                Copy-Item -LiteralPath $action.SourceFull -Destination $action.DestinationFull -Force
                $completed.Add([pscustomobject]@{ Kind = "replace"; Destination = $action.DestinationFull; Backup = $backup; DesiredHash = $action.NextState.BaselineHash }) | Out-Null
            }
            else {
                Copy-Item -LiteralPath $action.SourceFull -Destination $action.DestinationFull
                $addedHash = if ($action.NextState.Mode -eq "tracked") { $action.NextState.BaselineHash } else { $action.NextState.LocalHash }
                $completed.Add([pscustomobject]@{ Kind = "add"; Destination = $action.DestinationFull; Backup = ""; DesiredHash = $addedHash }) | Out-Null
            }
        }

        $stateContent = Get-StateContent -Version $CurrentVersion -Profiles $Plan.Profiles -Integrations $Plan.Integrations -Actions $Plan.Actions
        Write-StateAtomic -Path $StatePath -Content $stateContent
    }
    catch {
        for ($index = $completed.Count - 1; $index -ge 0; $index--) {
            $item = $completed[$index]
            try {
                switch ($item.Kind) {
                    "replace" {
                        Copy-Item -LiteralPath $item.Backup -Destination $item.Destination -Force
                    }
                    "retire" {
                        if (-not (Test-Path -LiteralPath $item.Destination) -and (Test-Path -LiteralPath $item.Backup -PathType Leaf)) {
                            $destinationDirectory = Split-Path -Parent $item.Destination
                            if (-not (Test-Path -LiteralPath $destinationDirectory)) {
                                New-Item -ItemType Directory -Force -Path $destinationDirectory | Out-Null
                            }
                            Move-Item -LiteralPath $item.Backup -Destination $item.Destination
                        }
                    }
                    "add" {
                        if (Test-Path -LiteralPath $item.Destination -PathType Leaf) {
                            $rollbackHash = Get-NormalizedTextHash -Path $item.Destination
                            if ($rollbackHash -eq $item.DesiredHash) {
                                Remove-Item -LiteralPath $item.Destination -Force
                            }
                            else {
                                Write-Warning "Rollback preserved concurrently changed added file '$($item.Destination)'."
                            }
                        }
                    }
                }
            }
            catch {
                Write-Warning "Rollback failed for '$($item.Destination)': $($_.Exception.Message)"
            }
        }
        throw
    }
    finally {
        if ($lockStream) {
            $lockStream.Dispose()
        }
    }
}

if ($Check -and $Apply) {
    throw "Use either -Check or -Apply, not both."
}

$acceptPackSet = Normalize-IdSet -Values $AcceptPack -Label "AcceptPack"
$acceptMergeSet = Normalize-IdSet -Values $AcceptMerge -Label "AcceptMerge"
$keepLocalSet = Normalize-IdSet -Values $KeepLocal -Label "KeepLocal"
foreach ($id in @($acceptPackSet.Keys)) {
    if ($acceptMergeSet.ContainsKey($id) -or $keepLocalSet.ContainsKey($id)) {
        throw "Artifact '$id' has conflicting resolutions."
    }
}
foreach ($id in @($acceptMergeSet.Keys)) {
    if ($keepLocalSet.ContainsKey($id)) {
        throw "Artifact '$id' has conflicting resolutions."
    }
}

$repoRoot = Get-CanonicalDirectory -Path $RepoPath -Label "RepoPath"
$templateRootCanonical = Get-CanonicalDirectory -Path $TemplateRoot -Label "Template root"
Assert-NoReparsePoint -Root $repoRoot -Path $repoRoot -Label "RepoPath"
$packVersion = Get-PackVersion -Path $VersionPath
$manifest = Read-PackManifest -Path $ManifestPath -TemplateRootPath $templateRootCanonical -RepositoryRoot $repoRoot
$currentArtifacts = Read-PackArtifacts -Path $ArtifactsPath -Manifest $manifest -RepositoryRoot $repoRoot
$compatibility = Read-CompatibilityCatalog -Root $CompatibilityRoot -RepositoryRoot $repoRoot
$statePathInfo = Resolve-SafeRelativePath -Root $repoRoot -RelativePath $StateRelativePath -Label "Agent Pack state"
$state = Read-AgentPackState -Path $statePathInfo.Full -RepositoryRoot $repoRoot -CurrentVersion $packVersion -CurrentArtifacts $currentArtifacts -Compatibility $compatibility
$selection = Get-EffectiveSelection -State $state -CurrentArtifacts $currentArtifacts -Compatibility $compatibility -RepositoryRoot $repoRoot
$requestedIntegrations = New-Object System.Collections.Generic.List[string]
foreach ($value in $Integration) {
    foreach ($item in ($value -split ",")) {
        $normalized = $item.Trim().ToLowerInvariant()
        if ($normalized) {
            if ($normalized -notin @("codex", "claude", "grok")) {
                throw "Unknown integration '$normalized'. Valid integrations: codex, claude, grok."
            }
            if ($requestedIntegrations -notcontains $normalized) {
                $requestedIntegrations.Add($normalized) | Out-Null
            }
        }
    }
}

if ($requestedIntegrations.Count -gt 0) {
    if ($requestedIntegrations -notcontains "codex") {
        throw "The Codex integration is mandatory. Include 'codex' when overriding integrations."
    }
    $selection = [pscustomobject]@{
        Profiles = @($selection.Profiles)
        Integrations = $requestedIntegrations.ToArray()
        Adopted = $selection.Adopted
    }
}
$plan = Get-ReconcilePlan -RepositoryRoot $repoRoot -CurrentVersion $packVersion -CurrentArtifacts $currentArtifacts -Compatibility $compatibility -State $state -Selection $selection -AcceptPackSet $acceptPackSet -AcceptMergeSet $acceptMergeSet -KeepLocalSet $keepLocalSet

Write-Host "Agent Pack reconciliation target: $packVersion"
Write-Host "Profiles: $($plan.Profiles -join ', ')"
Write-Host "Integrations: $($plan.Integrations -join ', ')"
if ($plan.Adopted) {
    Write-Host "Legacy installation detected from trusted release hashes."
}
foreach ($action in $plan.Actions) {
    $marker = if ($action.Conflict) { " !" } else { "" }
    Write-Host ("{0,-16} {1}{2} - {3}" -f $action.Type, $action.Destination, $marker, $action.Reason)
}

$summary = $plan.Actions | Group-Object Type | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Count)" }
Write-Host ("Summary: {0}" -f ($summary -join ", "))
if ($plan.HasConflicts) {
    Write-Warning "Unresolved Agent Pack conflicts remain. No repository files were changed."
}

if (-not $Apply) {
    Write-Host "Plan only: rerun with -Apply and explicit resolutions when required."
    return
}
if ($plan.HasConflicts) {
    throw "Agent Pack reconciliation aborted before writing because conflicts remain."
}
if (-not $PSCmdlet.ShouldProcess($repoRoot, "Apply Agent Pack reconciliation $packVersion")) {
    return
}

Invoke-ReconcilePlan -RepositoryRoot $repoRoot -CurrentVersion $packVersion -Plan $plan -StatePath $statePathInfo.Full
Write-Host "Agent Pack reconciliation applied successfully. State: $StateRelativePath"
