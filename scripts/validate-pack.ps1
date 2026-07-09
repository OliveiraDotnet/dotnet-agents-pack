[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ScriptDir = Split-Path -Parent $PSCommandPath
$PackRoot = Split-Path -Parent $ScriptDir
$TemplateRoot = Join-Path $PackRoot "repo-template"
$ManifestPath = Join-Path $PackRoot "pack-manifest.txt"
$ValidProfiles = @("core", "web", "sqlserver", "quality")
$errors = New-Object System.Collections.Generic.List[string]

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
    $manifestEntries = @()
    Get-Content -LiteralPath $ManifestPath | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith("#")) {
            $parts = $line -split '\|', 2
            if ($parts.Count -ne 2) {
                Add-Error "Invalid manifest line: $line"
                return
            }
            $component = $parts[0].Trim()
            $relativePath = $parts[1].Trim()
            if ($ValidProfiles -notcontains $component) { Add-Error "Unknown manifest profile '$component'." }
            if (-not $relativePath) { Add-Error "Empty manifest path for '$component'." }
            $manifestEntries += [pscustomobject]@{ Component = $component; Path = $relativePath }
        }
    }

    $duplicates = $manifestEntries | Group-Object Path | Where-Object { $_.Count -gt 1 }
    foreach ($duplicate in $duplicates) { Add-Error "Manifest path appears more than once: $($duplicate.Name)" }

    foreach ($entry in $manifestEntries) {
        $source = Join-Path $TemplateRoot $entry.Path
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { Add-Error "Manifest source is missing: $($entry.Path)" }
    }

    $manifestPaths = @($manifestEntries.Path | Sort-Object -Unique)
    $templateFiles = @(Get-ChildItem -LiteralPath $TemplateRoot -File -Recurse -Force | ForEach-Object { Get-RelativePath $TemplateRoot $_.FullName })
    foreach ($file in $templateFiles) {
        if ($manifestPaths -notcontains $file) { Add-Error "Template file is not listed in the manifest: $file" }
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

$genericFiles = @(
    Get-ChildItem -LiteralPath $TemplateRoot -File -Recurse -Force
    Get-Item -LiteralPath (Join-Path $PackRoot "README.md"), (Join-Path $PackRoot "INSTRUCOES_DETALHADAS.md"), (Join-Path $PackRoot "FONTES_OFICIAIS_CODEX.md"), (Join-Path $PackRoot "global\AGENTS.md")
)
$allText = ($genericFiles | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
foreach ($term in @("Aptos", "M & Y TECH", "Portal de Vendas", "projetos/")) {
    if ($allText -match [regex]::Escape($term)) { Add-Error "Obsolete organization-specific reference found: $term" }
}

foreach ($path in @("AGENTS.md", "docs/ai/runbook.md")) {
    $content = Get-Content -LiteralPath (Join-Path $TemplateRoot $path) -Raw
    if ($content -match '(?m)^dotnet (restore|build|test)$') { Add-Error "Unverified dotnet command remains in $path." }
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ }
    throw "Pack validation failed with $($errors.Count) error(s)."
}

Write-Host "Pack validation passed: manifest, skills, agents and generic-content checks are valid."
