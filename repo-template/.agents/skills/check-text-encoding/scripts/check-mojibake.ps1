[CmdletBinding()]
param(
    [string]$RepoPath = ".",
    [string[]]$File = @(),
    [switch]$All
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Get-CanonicalRoot {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Repository path is not a directory: $Path"
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

function Get-RelativePath {
    param([string]$BasePath, [string]$Path)

    $baseFull = [IO.Path]::GetFullPath($BasePath)
    if (-not $baseFull.EndsWith([IO.Path]::DirectorySeparatorChar)) {
        $baseFull += [IO.Path]::DirectorySeparatorChar
    }
    $baseUri = New-Object System.Uri($baseFull)
    $pathUri = New-Object System.Uri([IO.Path]::GetFullPath($Path))
    return [Uri]::UnescapeDataString($baseUri.MakeRelativeUri($pathUri).ToString()).Replace('\', '/')
}

function Test-IgnoredPath {
    param([string]$RelativePath)

    return $RelativePath -match '(?i)(^|/)(\.git|\.agent-pack|bin|obj|build|\.dart_tool|\.gradle|Pods|DerivedData|node_modules|coverage)(/|$)'
}

function Get-CandidateFiles {
    param([string]$Root)

    $relativePaths = New-Object System.Collections.Generic.List[string]
    $usedGitRepository = $false
    if ($File.Count -gt 0) {
        foreach ($item in $File) {
            $candidate = if ([IO.Path]::IsPathRooted($item)) { [IO.Path]::GetFullPath($item) } else { [IO.Path]::GetFullPath((Join-Path $Root $item)) }
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                $relativePaths.Add((Get-RelativePath -BasePath $Root -Path $candidate))
            }
        }
    }
    elseif (Get-Command git -ErrorAction SilentlyContinue) {
        $previousErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            $inside = & git -C $Root rev-parse --is-inside-work-tree 2>$null
            if ($LASTEXITCODE -eq 0 -and $inside -eq "true") {
                $usedGitRepository = $true
                if ($All) {
                    $listed = @(& git -C $Root ls-files --cached --others --exclude-standard 2>$null)
                }
                else {
                    $listed = @(& git -C $Root diff --name-only --diff-filter=ACMR HEAD -- 2>$null)
                    if ($LASTEXITCODE -ne 0) {
                        $listed = @(& git -C $Root ls-files --cached 2>$null)
                    }
                    $listed += @(& git -C $Root ls-files --others --exclude-standard 2>$null)
                }
                foreach ($item in $listed) {
                    if ($item) { $relativePaths.Add($item.Replace('\', '/')) }
                }
            }
        }
        finally {
            $ErrorActionPreference = $previousErrorActionPreference
        }
    }

    if ($relativePaths.Count -eq 0 -and ($All -or (-not $usedGitRepository -and $File.Count -eq 0))) {
        Get-ChildItem -LiteralPath $Root -File -Recurse -Force | ForEach-Object {
            $relativePaths.Add((Get-RelativePath -BasePath $Root -Path $_.FullName))
        }
    }

    return @($relativePaths | Sort-Object -Unique | Where-Object { -not (Test-IgnoredPath $_) })
}

$root = Get-CanonicalRoot -Path $RepoPath
$utf8 = New-Object System.Text.UTF8Encoding($false, $true)
$signatures = @(
    [pscustomobject]@{ Name = "replacement-character"; Pattern = '\uFFFD' },
    [pscustomobject]@{ Name = "misdecoded-utf8-c3"; Pattern = '\u00C3[\u0080-\u00BF]' },
    [pscustomobject]@{ Name = "misdecoded-utf8-c2"; Pattern = '\u00C2[\u0080-\u00BF]' },
    [pscustomobject]@{ Name = "double-encoded-utf8"; Pattern = '\u00C3(?:\u0192|\u201A)' },
    [pscustomobject]@{ Name = "misdecoded-punctuation"; Pattern = '\u00E2(?:\u20AC|\u2020|\u0153|\u0098|\u0080|\u0086)' },
    [pscustomobject]@{ Name = "misdecoded-emoji"; Pattern = '\u00F0\u0178' },
    [pscustomobject]@{ Name = "misdecoded-bom"; Pattern = '\u00EF\u00BB\u00BF' },
    [pscustomobject]@{ Name = "misdecoded-replacement"; Pattern = '\u00EF\u00BF\u00BD' }
)

$findings = New-Object System.Collections.Generic.List[object]
$scanned = 0
foreach ($relativePath in (Get-CandidateFiles -Root $root)) {
    $fullPath = [IO.Path]::GetFullPath((Join-Path $root $relativePath))
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { continue }

    $bytes = [IO.File]::ReadAllBytes($fullPath)
    if ($bytes -contains 0) { continue }

    try {
        $text = $utf8.GetString($bytes)
    }
    catch {
        $findings.Add([pscustomobject]@{
            Path = $relativePath
            Line = 0
            Column = 0
            Kind = "invalid-utf8"
        }) | Out-Null
        continue
    }

    $scanned++
    $lines = $text -split "`r?`n", -1
    for ($lineIndex = 0; $lineIndex -lt $lines.Count; $lineIndex++) {
        $line = $lines[$lineIndex]
        if ($line -match 'agent-pack:allow-mojibake') { continue }
        foreach ($signature in $signatures) {
            $match = [regex]::Match($line, $signature.Pattern)
            if ($match.Success) {
                $findings.Add([pscustomobject]@{
                    Path = $relativePath
                    Line = $lineIndex + 1
                    Column = $match.Index + 1
                    Kind = $signature.Name
                }) | Out-Null
            }
        }
    }
}

foreach ($finding in $findings) {
    Write-Output ("{0}:{1}:{2}: {3}" -f $finding.Path, $finding.Line, $finding.Column, $finding.Kind)
}

if ($findings.Count -gt 0) {
    Write-Error "Text encoding check failed with $($findings.Count) finding(s) across $scanned decoded text file(s)."
    exit 1
}

Write-Host "Text encoding check passed: $scanned UTF-8 text file(s) scanned."
