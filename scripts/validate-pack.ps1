[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ScriptDir = Split-Path -Parent $PSCommandPath
$PackRoot = Split-Path -Parent $ScriptDir
$TemplateRoot = Join-Path $PackRoot "repo-template"
$ManifestPath = Join-Path $PackRoot "pack-manifest.txt"
$PackVersionPath = Join-Path $PackRoot "pack-version.txt"
$ArtifactMetadataPath = Join-Path $PackRoot "pack-artifacts.txt"
$CompatibilityRoot = Join-Path $PackRoot "compat\releases"
$ValidComponents = @(
    "core", "web", "sqlserver", "quality",
    "claude-core", "claude-web", "claude-sqlserver", "claude-quality",
    "grok-core", "grok-web", "grok-sqlserver", "grok-quality"
)
$errors = New-Object System.Collections.Generic.List[string]
$manifestEntries = @()
$artifactEntries = @()

function Add-Error { param([string]$Message) $errors.Add($Message) | Out-Null }

function Get-RelativePath {
    param([string]$BasePath, [string]$Path)

    $baseFull = [IO.Path]::GetFullPath($BasePath)
    if (-not $baseFull.EndsWith([IO.Path]::DirectorySeparatorChar)) { $baseFull += [IO.Path]::DirectorySeparatorChar }
    $baseUri = New-Object System.Uri($baseFull)
    $pathUri = New-Object System.Uri([IO.Path]::GetFullPath($Path))
    return [Uri]::UnescapeDataString($baseUri.MakeRelativeUri($pathUri).ToString()).Replace('\', '/')
}

if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    Add-Error "Missing pack manifest: $ManifestPath"
}
else {
    Get-Content -LiteralPath $ManifestPath | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith("#")) {
            $parts = $line -split '\|', 4
            if ($parts.Count -notin @(2, 3)) {
                Add-Error "Invalid manifest line: $line"
                return
            }
            $component = $parts[0].Trim()
            $sourcePath = $parts[1].Trim()
            $destinationPath = if ($parts.Count -eq 3) { $parts[2].Trim() } else { $sourcePath }
            if ($ValidComponents -notcontains $component) { Add-Error "Unknown manifest component '$component'." }
            if (-not $sourcePath) { Add-Error "Empty manifest source for '$component'." }
            if (-not $destinationPath) { Add-Error "Empty manifest destination for '$component'." }
            $manifestEntries += [pscustomobject]@{
                Component = $component
                Source = $sourcePath
                Destination = $destinationPath
            }
        }
    }

    $duplicates = $manifestEntries | Group-Object Destination | Where-Object { $_.Count -gt 1 }
    foreach ($duplicate in $duplicates) { Add-Error "Manifest destination appears more than once: $($duplicate.Name)" }

    foreach ($entry in $manifestEntries) {
        $source = Join-Path $TemplateRoot $entry.Source
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { Add-Error "Manifest source is missing: $($entry.Source)" }
    }

    $manifestSources = @($manifestEntries.Source | Sort-Object -Unique)
    $templateFiles = @(Get-ChildItem -LiteralPath $TemplateRoot -File -Recurse -Force | ForEach-Object { Get-RelativePath $TemplateRoot $_.FullName })
    foreach ($file in $templateFiles) {
        if ($manifestSources -notcontains $file) { Add-Error "Template file is not listed as a manifest source: $file" }
    }
}

if (-not (Test-Path -LiteralPath $PackVersionPath -PathType Leaf)) {
    Add-Error "Missing pack version file: $PackVersionPath"
}
else {
    $packVersion = (Get-Content -LiteralPath $PackVersionPath -Raw).Trim()
    if ($packVersion -notmatch '^\d+\.\d+\.\d+$') {
        Add-Error "Invalid semantic version in pack-version.txt: $packVersion"
    }
    elseif ((Get-Content -LiteralPath $ManifestPath -Raw) -notmatch "(?m)^# \.NET Agents Pack manifest v$([regex]::Escape($packVersion))\s*$") {
        Add-Error "Manifest header version does not match pack-version.txt ($packVersion)."
    }
}

if (-not (Test-Path -LiteralPath $ArtifactMetadataPath -PathType Leaf)) {
    Add-Error "Missing artifact metadata: $ArtifactMetadataPath"
}
else {
    Get-Content -LiteralPath $ArtifactMetadataPath | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith("#")) {
            $parts = $line -split '\|', 4
            if ($parts.Count -ne 3) {
                Add-Error "Invalid artifact metadata line: $line"
                return
            }
            $artifactId = $parts[0].Trim()
            $destination = $parts[1].Trim()
            $ownership = $parts[2].Trim()
            if ($artifactId -notmatch '^[a-z0-9][a-z0-9.-]*$') { Add-Error "Invalid artifact id '$artifactId'." }
            if (-not $destination -or [IO.Path]::IsPathRooted($destination) -or $destination -match '(^|/)\.\.(/|$)|\\') {
                Add-Error "Invalid artifact destination '$destination'."
            }
            if ($ownership -notin @("managed", "merge", "seed")) { Add-Error "Invalid ownership '$ownership' for '$artifactId'." }
            $artifactEntries += [pscustomobject]@{
                Id = $artifactId
                Destination = $destination
                Ownership = $ownership
            }
        }
    }

    foreach ($duplicate in @($artifactEntries | Group-Object Id | Where-Object { $_.Count -gt 1 })) {
        Add-Error "Artifact id appears more than once: $($duplicate.Name)"
    }
    foreach ($duplicate in @($artifactEntries | Group-Object { $_.Destination.ToLowerInvariant() } | Where-Object { $_.Count -gt 1 })) {
        Add-Error "Artifact destination appears more than once: $($duplicate.Group[0].Destination)"
    }
    foreach ($entry in $manifestEntries) {
        if (@($artifactEntries | Where-Object { $_.Destination -eq $entry.Destination }).Count -ne 1) {
            Add-Error "Manifest destination must have exactly one artifact metadata entry: $($entry.Destination)"
        }
    }
    foreach ($artifact in $artifactEntries) {
        if (@($manifestEntries | Where-Object { $_.Destination -eq $artifact.Destination }).Count -ne 1) {
            Add-Error "Artifact metadata destination is not present once in the manifest: $($artifact.Destination)"
        }
    }

    foreach ($path in @("AGENTS.md", "CLAUDE.md", ".grok/config.toml")) {
        $artifact = @($artifactEntries | Where-Object { $_.Destination -eq $path })
        if ($artifact.Count -eq 1 -and $artifact[0].Ownership -ne "merge") {
            Add-Error "$path must use merge ownership."
        }
    }
    foreach ($artifact in @($artifactEntries | Where-Object { $_.Destination -like "docs/ai/*" })) {
        if ($artifact.Ownership -ne "seed") { Add-Error "Repository memory must use seed ownership: $($artifact.Destination)" }
    }
}

if (-not (Test-Path -LiteralPath $CompatibilityRoot -PathType Container)) {
    Add-Error "Missing compatibility catalog directory: $CompatibilityRoot"
}
else {
    foreach ($catalog in @(Get-ChildItem -LiteralPath $CompatibilityRoot -File -Filter "*.txt")) {
        $catalogEntries = @()
        Get-Content -LiteralPath $catalog.FullName | ForEach-Object {
            $line = $_.Trim()
            if ($line -and -not $line.StartsWith("#")) {
                $parts = $line -split '\|', 4
                if ($parts.Count -ne 3) {
                    Add-Error "Invalid compatibility line in '$($catalog.Name)': $line"
                    return
                }
                if ($parts[0] -notmatch '^[a-z0-9][a-z0-9.-]*$') { Add-Error "Invalid compatibility artifact id '$($parts[0])'." }
                if (-not $parts[1] -or [IO.Path]::IsPathRooted($parts[1]) -or $parts[1] -match '(^|/)\.\.(/|$)|\\') {
                    Add-Error "Invalid compatibility destination '$($parts[1])'."
                }
                if ($parts[2] -notmatch '^[a-f0-9]{64}$') { Add-Error "Invalid compatibility hash for '$($parts[0])'." }
                $catalogEntries += [pscustomobject]@{ Id = $parts[0]; Destination = $parts[1] }
            }
        }
        foreach ($duplicate in @($catalogEntries | Group-Object Id | Where-Object { $_.Count -gt 1 })) {
            Add-Error "Compatibility catalog '$($catalog.Name)' repeats artifact id '$($duplicate.Name)'."
        }
    }
}

$agentFiles = Get-ChildItem -LiteralPath (Join-Path $TemplateRoot ".codex\agents") -File -Filter "*.toml" -ErrorAction SilentlyContinue
foreach ($agent in $agentFiles) {
    $content = Get-Content -LiteralPath $agent.FullName -Raw
    foreach ($requiredKey in @("name", "description", "developer_instructions")) {
        if ($content -notmatch "(?m)^$requiredKey\s*=") { Add-Error "Agent '$($agent.Name)' is missing $requiredKey." }
    }

    $nicknameLine = [regex]::Match($content, '(?m)^nickname_candidates\s*=\s*\[(.+)\]$')
    if ($nicknameLine.Success) {
        foreach ($value in [regex]::Matches($nicknameLine.Groups[1].Value, '"([^"]+)"')) {
            if ($value.Groups[1].Value -notmatch '^[A-Za-z0-9 _-]+$') {
                Add-Error "Agent '$($agent.Name)' has a non-ASCII nickname: $($value.Groups[1].Value)"
            }
        }
    }
}

$claudeAgentRoot = Join-Path $TemplateRoot ".claude\agents"
$claudeAgentFiles = Get-ChildItem -LiteralPath $claudeAgentRoot -File -Filter "*.md" -ErrorAction SilentlyContinue
foreach ($agent in $claudeAgentFiles) {
    $content = Get-Content -LiteralPath $agent.FullName -Raw
    $frontmatter = [regex]::Match($content, '(?ms)\A---\s*\r?\n(.*?)\r?\n---')
    if (-not $frontmatter.Success) {
        Add-Error "Claude agent '$($agent.Name)' has invalid frontmatter."
        continue
    }

    $nameMatch = [regex]::Match($frontmatter.Groups[1].Value, '(?m)^name:\s*([^\r\n]+)$')
    $descriptionMatch = [regex]::Match($frontmatter.Groups[1].Value, '(?m)^description:\s*([^\r\n]+)$')
    if (-not $nameMatch.Success) { Add-Error "Claude agent '$($agent.Name)' is missing name."; continue }
    if (-not $descriptionMatch.Success) { Add-Error "Claude agent '$($agent.Name)' is missing description." }

    $name = $nameMatch.Groups[1].Value.Trim().Trim('"', "'")
    if ($name -notmatch '^[a-z0-9-]+$') { Add-Error "Claude agent '$($agent.Name)' has invalid name '$name'." }
    if ($name -ne [IO.Path]::GetFileNameWithoutExtension($agent.Name)) {
        Add-Error "Claude agent name '$name' does not match file '$($agent.Name)'."
    }
}

foreach ($agent in $agentFiles) {
    $content = Get-Content -LiteralPath $agent.FullName -Raw
    $nameMatch = [regex]::Match($content, '(?m)^name\s*=\s*"([^"]+)"')
    if (-not $nameMatch.Success) { continue }
    $claudeName = $nameMatch.Groups[1].Value.Replace('_', '-')
    $claudePath = Join-Path $claudeAgentRoot "$claudeName.md"
    if (-not (Test-Path -LiteralPath $claudePath -PathType Leaf)) {
        Add-Error "Codex agent '$($agent.Name)' has no Claude counterpart '$claudeName.md'."
    }

    $grokSource = ".claude/agents/$claudeName.md"
    $grokDestination = ".grok/agents/$claudeName.md"
    $grokMirror = @($manifestEntries | Where-Object {
        $_.Source -eq $grokSource -and
        $_.Destination -eq $grokDestination -and
        $_.Component -like "grok-*"
    })
    if ($grokMirror.Count -ne 1) {
        Add-Error "Codex agent '$($agent.Name)' must map once to Grok agent '$grokDestination'."
    }
}

$claudeGuidancePath = Join-Path $TemplateRoot "CLAUDE.md"
if (-not (Test-Path -LiteralPath $claudeGuidancePath -PathType Leaf)) {
    Add-Error "Missing Claude guidance bridge: CLAUDE.md"
}
elseif ((Get-Content -LiteralPath $claudeGuidancePath -Raw) -notmatch '(?m)^@AGENTS\.md\s*$') {
    Add-Error "CLAUDE.md must import @AGENTS.md."
}

$grokConfigPath = Join-Path $TemplateRoot ".grok\config.toml"
if (-not (Test-Path -LiteralPath $grokConfigPath -PathType Leaf)) {
    Add-Error "Missing Grok Build project configuration: .grok/config.toml"
}
else {
    $grokConfig = Get-Content -LiteralPath $grokConfigPath -Raw
    foreach ($command in @("git commit", "git push")) {
        $requiredRule = '{ action = "deny", tool = "bash", pattern = "' + $command + ' *" }'
        if (-not $grokConfig.Contains($requiredRule)) { Add-Error ".grok/config.toml must deny '$command'." }
    }
}

$governanceFiles = @{
    "AGENTS.md" = Join-Path $TemplateRoot "AGENTS.md"
    "delegate-to-grok-build" = Join-Path $TemplateRoot ".agents\skills\delegate-to-grok-build\SKILL.md"
    "execute-codex-work-order" = Join-Path $TemplateRoot ".grok\skills\execute-codex-work-order\SKILL.md"
}
foreach ($name in $governanceFiles.Keys) {
    if (-not (Test-Path -LiteralPath $governanceFiles[$name] -PathType Leaf)) {
        Add-Error "Missing Grok governance artifact: $name."
    }
}
if (@($governanceFiles.Values | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) }).Count -eq 0) {
    $agentsGovernance = Get-Content -LiteralPath $governanceFiles["AGENTS.md"] -Raw
    $delegationContract = Get-Content -LiteralPath $governanceFiles["delegate-to-grok-build"] -Raw
    $executionContract = Get-Content -LiteralPath $governanceFiles["execute-codex-work-order"] -Raw

    foreach ($required in @("sole decision authority", "Gate 1", "execution envelope", "Gate 2", "BLOCKED_BY_DECISION")) {
        if (-not $agentsGovernance.Contains($required)) { Add-Error "AGENTS.md is missing governance marker '$required'." }
    }
    foreach ($required in @("Human-approved scope", "Allowed read areas", "Allowed modification areas", "Decision boundaries", "Escalation conditions", "READY_FOR_MANUAL_VALIDATION", "USER_DECISION_REQUIRED")) {
        if (-not $delegationContract.Contains($required)) { Add-Error "Codex-to-Grok delegation contract is missing '$required'." }
    }
    foreach ($required in @("COMPLETED", "COMPLETED_WITH_CONCERNS", "BLOCKED_BY_DECISION", "UNABLE_TO_VALIDATE", "material change was not performed")) {
        if (-not $executionContract.Contains($required)) { Add-Error "Grok execution contract is missing '$required'." }
    }
}

$skillFiles = Get-ChildItem -LiteralPath (Join-Path $TemplateRoot ".agents\skills") -File -Filter "SKILL.md" -Recurse -ErrorAction SilentlyContinue
foreach ($skill in $skillFiles) {
    $content = Get-Content -LiteralPath $skill.FullName -Raw
    $match = [regex]::Match($content, '(?ms)^---\s*\r?\nname:\s*([^\r\n]+)\r?\ndescription:\s*([^\r\n]+)\r?\n---')
    if (-not $match.Success) {
        Add-Error "Skill '$($skill.FullName)' has invalid required frontmatter."
        continue
    }

    $name = $match.Groups[1].Value.Trim()
    $folder = Split-Path -Leaf (Split-Path -Parent $skill.FullName)
    if ($name -ne $folder) { Add-Error "Skill name '$name' does not match folder '$folder'." }
    if ($name -notmatch '^[a-z0-9-]+$') { Add-Error "Skill '$name' violates naming rules." }
}

$baseComponents = @("core", "web", "sqlserver", "quality")
$canonicalSkillEntries = @($manifestEntries | Where-Object { $_.Component -in $baseComponents -and $_.Destination -like ".agents/skills/*" })
foreach ($entry in $canonicalSkillEntries) {
    $expectedComponent = "claude-$($entry.Component)"
    $expectedDestination = $entry.Destination -replace '^\.agents/skills/', '.claude/skills/'
    $mirror = @($manifestEntries | Where-Object {
        $_.Component -eq $expectedComponent -and
        $_.Source -eq $entry.Source -and
        $_.Destination -eq $expectedDestination
    })
    if ($mirror.Count -ne 1) {
        Add-Error "Skill '$($entry.Source)' must map once to '$expectedDestination' in '$expectedComponent'."
    }

    if (-not $entry.Destination.EndsWith("/agents/openai.yaml")) {
        $grokComponent = "grok-$($entry.Component)"
        $grokDestination = $entry.Destination -replace '^\.agents/skills/', '.grok/skills/'
        $grokMirror = @($manifestEntries | Where-Object {
            $_.Component -eq $grokComponent -and
            $_.Source -eq $entry.Source -and
            $_.Destination -eq $grokDestination
        })
        if ($grokMirror.Count -ne 1) {
            Add-Error "Skill '$($entry.Source)' must map once to '$grokDestination' in '$grokComponent'."
        }
    }
}

$genericFiles = @(
    Get-ChildItem -LiteralPath $TemplateRoot -File -Recurse -Force
    Get-Item -LiteralPath (Join-Path $PackRoot "README.md"), (Join-Path $PackRoot "MANUAL_DE_USO.md"), (Join-Path $PackRoot "INSTRUCOES_DETALHADAS.md"), (Join-Path $PackRoot "FONTES_OFICIAIS_CODEX.md"), (Join-Path $PackRoot "FONTES_OFICIAIS_CLAUDE.md"), (Join-Path $PackRoot "FONTES_OFICIAIS_GROK_BUILD.md"), (Join-Path $PackRoot "global\AGENTS.md")
)
$allText = ($genericFiles | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
foreach ($term in @("Aptos", "M & Y TECH", "Portal de Vendas", "projetos/")) {
    if ($allText -match [regex]::Escape($term)) { Add-Error "Obsolete organization-specific reference found: $term" }
}

foreach ($path in @("AGENTS.md", "docs/ai/runbook.md")) {
    $content = Get-Content -LiteralPath (Join-Path $TemplateRoot $path) -Raw
    if ($content -match '(?m)^dotnet (restore|build|test)$') { Add-Error "Unverified dotnet command remains in $path." }
}

$encodingChecker = Join-Path $TemplateRoot ".agents\skills\check-text-encoding\scripts\check-mojibake.ps1"
if (Test-Path -LiteralPath $encodingChecker -PathType Leaf) {
    & $encodingChecker -RepoPath $PackRoot -All
    if ($LASTEXITCODE -ne 0) { Add-Error "Text encoding validation failed." }
}
else {
    Add-Error "Missing PowerShell text encoding checker."
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ }
    throw "Pack validation failed with $($errors.Count) error(s)."
}

Write-Host "Pack validation passed: manifest, shared skills, Codex/Claude/Grok agents and generic-content checks are valid."
