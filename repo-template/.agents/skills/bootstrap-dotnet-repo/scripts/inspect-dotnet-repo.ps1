param(
    [string]$RepoPath = (Get-Location).Path,
    [ValidateSet("json", "markdown")]
    [string]$Format = "json"
)

$ErrorActionPreference = "Stop"

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

function Get-ProjectMetadata {
    param([string]$ProjectPath, [string]$RepoRoot)

    $metadata = [ordered]@{
        path = Get-RelativePath $RepoRoot $ProjectPath
        style = "unknown"
        targetFrameworks = @()
        packageReferences = @()
        testFrameworks = @()
    }

    try {
        [xml]$project = Get-Content -LiteralPath $ProjectPath -Raw
        if ($project.DocumentElement.GetAttribute("Sdk")) { $metadata.style = "sdk" }
        elseif ($project.SelectSingleNode("//*[local-name()='TargetFrameworkVersion']")) { $metadata.style = "classic" }

        $tfms = @($project.SelectNodes("//*[local-name()='TargetFramework' or local-name()='TargetFrameworks' or local-name()='TargetFrameworkVersion']") | ForEach-Object { $_.InnerText.Trim() } | Where-Object { $_ })
        $metadata.targetFrameworks = @($tfms | Sort-Object -Unique)

        $packages = @($project.SelectNodes("//*[local-name()='PackageReference']") | ForEach-Object { if ($_.Include) { $_.Include } elseif ($_.Update) { $_.Update } } | Where-Object { $_ } | Sort-Object -Unique)
        $metadata.packageReferences = $packages

        $testNames = @($packages | Where-Object { $_ -match '(^|\.)(xunit|nunit|mstest|microsoft\.net\.test\.sdk)(\.|$)' })
        if ($metadata.path -match '(?i)(^|/)(test|tests|spec)(/|$)|(\.|-)(test|tests|spec)(\.|-|$)') { $testNames += "project-name" }
        $metadata.testFrameworks = @($testNames | Sort-Object -Unique)
    }
    catch {
        $metadata.style = "unreadable"
    }

    return [pscustomobject]$metadata
}

$repo = (Resolve-Path -LiteralPath $RepoPath).Path
$gitRoot = $null
if (Get-Command git -ErrorAction SilentlyContinue) {
    try {
        $candidate = & git -C $repo rev-parse --show-toplevel 2>$null
    }
    catch {
        $candidate = $null
    }
    if ($LASTEXITCODE -eq 0 -and $candidate) { $gitRoot = (Resolve-Path -LiteralPath $candidate.Trim()).Path }
}

$excluded = @(".git", "bin", "obj", "node_modules", "packages", ".vs")
$files = Get-ChildItem -LiteralPath $repo -File -Recurse -Force | Where-Object {
    $relative = Get-RelativePath $repo $_.FullName
    -not ($excluded | Where-Object { $relative -match "(^|/)$([regex]::Escape($_))(/|$)" })
}

$byExtension = @{}
foreach ($file in $files) {
    $extension = $file.Extension.ToLowerInvariant()
    if (-not $byExtension.ContainsKey($extension)) { $byExtension[$extension] = 0 }
    $byExtension[$extension]++
}

function Get-ExtensionCount {
    param([string]$Extension)
    if ($byExtension.ContainsKey($Extension)) { return $byExtension[$Extension] }
    return 0
}

$projectFiles = @($files | Where-Object { $_.Extension -in ".csproj", ".fsproj", ".vbproj" })
$projects = @($projectFiles | ForEach-Object { Get-ProjectMetadata $_.FullName $repo })
$allPackages = @($projects | ForEach-Object { $_.packageReferences } | Sort-Object -Unique)
$allTfms = @($projects | ForEach-Object { $_.targetFrameworks } | Sort-Object -Unique)

$relativeFiles = @($files | ForEach-Object { Get-RelativePath $repo $_.FullName })
$contains = {
    param([string]$Pattern)
    return @($relativeFiles | Where-Object { $_ -match $Pattern }).Count -gt 0
}

$applicationTypes = @()
if (& $contains '(?i)(\.cshtml$|\.razor$|\.aspx$|web\.config$|wwwroot/)') { $applicationTypes += "web" }
if (& $contains '(?i)(\.xaml$|\.resx$)') { $applicationTypes += "desktop-or-xaml" }
if (& $contains '(?i)(\.svc$|\.asmx$)') { $applicationTypes += "legacy-service" }
if (& $contains '(?i)(worker|service)') { $applicationTypes += "worker-or-service" }

$profiles = @()
if ($applicationTypes -contains "web") { $profiles += "web" }
if ((& $contains '(?i)(^|/)packages\.config$|web\.config$|\.aspx$') -or @($projects | Where-Object { $_.style -eq "classic" }).Count -gt 0) { $profiles += "legacy-framework" }
if ((& $contains '(?i)\.sql$') -or @($allPackages | Where-Object { $_ -match '(?i)(sqlclient|entityframework|dapper)' }).Count -gt 0) { $profiles += "sqlserver" }

$ciFiles = @($relativeFiles | Where-Object { $_ -match '(^\.github/workflows/|(^|/)azure-pipelines.*\.ya?ml$|(^|/)\.gitlab-ci\.ya?ml$|(^|/)(build|test)\.(ps1|sh|cmd|bat)$)' })
$structure = if ($gitRoot) { "git-repository" } elseif (@($projectFiles).Count -gt 1) { "non-git-multi-project" } else { "non-git-folder" }

$result = [ordered]@{
    inspectedPath = $repo
    gitRoot = $gitRoot
    repositoryShape = $structure
    solutionFiles = @($relativeFiles | Where-Object { $_ -match '(?i)\.slnx?$' })
    projectFiles = $projects
    targetFrameworks = $allTfms
    applicationTypes = @($applicationTypes | Sort-Object -Unique)
    packagesConfigFiles = @($relativeFiles | Where-Object { $_ -match '(?i)(^|/)packages\.config$' })
    buildMetadata = @($relativeFiles | Where-Object { $_ -match '(?i)(^|/)(global\.json|directory\.build\.(props|targets)|directory\.packages\.props)$' })
    testProjects = @($projects | Where-Object { $_.testFrameworks.Count -gt 0 } | ForEach-Object { $_.path })
    ciAndScripts = $ciFiles
    optionalProfilesSuggested = @($profiles | Sort-Object -Unique)
    fileExtensionCounts = [ordered]@{
        csproj = Get-ExtensionCount ".csproj"
        fsproj = Get-ExtensionCount ".fsproj"
        vbproj = Get-ExtensionCount ".vbproj"
        cshtml = Get-ExtensionCount ".cshtml"
        razor = Get-ExtensionCount ".razor"
        aspx = Get-ExtensionCount ".aspx"
        sql = Get-ExtensionCount ".sql"
        xaml = Get-ExtensionCount ".xaml"
    }
}

if ($Format -eq "markdown") {
    "# .NET repository fingerprint"
    ""
    "- Shape: $($result.repositoryShape)"
    "- Git root: $($result.gitRoot)"
    "- Solutions: $($result.solutionFiles -join ', ')"
    "- Target frameworks: $($result.targetFrameworks -join ', ')"
    "- Application types: $($result.applicationTypes -join ', ')"
    "- Suggested profiles: $($result.optionalProfilesSuggested -join ', ')"
    "- CI/scripts: $($result.ciAndScripts -join ', ')"
}
else {
    $result | ConvertTo-Json -Depth 6
}
