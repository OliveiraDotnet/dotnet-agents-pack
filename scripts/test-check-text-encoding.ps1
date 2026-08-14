[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ScriptDir = Split-Path -Parent $PSCommandPath
$PackRoot = Split-Path -Parent $ScriptDir
$Checker = Join-Path $PackRoot "repo-template\.agents\skills\check-text-encoding\scripts\check-mojibake.ps1"
$TempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd(
    [IO.Path]::DirectorySeparatorChar,
    [IO.Path]::AltDirectorySeparatorChar
)
$TempRoot = Join-Path $TempBase ("agent-pack-encoding-test-" + [Guid]::NewGuid().ToString("N"))
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Invoke-CheckerCase {
    param(
        [string]$Name,
        [string]$RelativePath,
        [int]$ExpectedExitCode,
        [string]$ExpectedOutput
    )

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $outputLines = @(
            & $script:PowerShellExecutable `
                -NoLogo `
                -NoProfile `
                -ExecutionPolicy Bypass `
                -File $script:Checker `
                -RepoPath $script:TempRoot `
                -File $RelativePath 2>&1
        )
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    $output = $outputLines | Out-String
    Assert-True ($exitCode -eq $ExpectedExitCode) (
        "Case '$Name' returned exit code $exitCode; expected $ExpectedExitCode.`n$output"
    )
    Assert-True ($output -match [regex]::Escape($ExpectedOutput)) (
        "Case '$Name' did not report '$ExpectedOutput'.`n$output"
    )
}

Assert-True (Test-Path -LiteralPath $Checker -PathType Leaf) "Text encoding checker is missing: $Checker"

$powerShellCommand = Get-Command pwsh -ErrorAction SilentlyContinue
if (-not $powerShellCommand) {
    $powerShellCommand = Get-Command powershell -ErrorAction SilentlyContinue
}
Assert-True ($null -ne $powerShellCommand) "Unable to locate a PowerShell executable for isolated checker cases."
$PowerShellExecutable = $powerShellCommand.Source

try {
    New-Item -ItemType Directory -Path $TempRoot | Out-Null

    $correctText = "informa$([char]0x00E7)$([char]0x00E3)o $([char]0x00FA)til em $([char]0x00E2)mbito local"
    [IO.File]::WriteAllText((Join-Path $TempRoot "correct.txt"), $correctText, $Utf8NoBom)

    $mojibake = "informa$([char]0x00C3)$([char]0x00A7)$([char]0x00C3)$([char]0x00A3)o"
    [IO.File]::WriteAllText((Join-Path $TempRoot "mojibake.txt"), $mojibake, $Utf8NoBom)

    [IO.File]::WriteAllText(
        (Join-Path $TempRoot "replacement.txt"),
        "replacement $([char]0xFFFD)",
        $Utf8NoBom
    )

    [IO.File]::WriteAllText(
        (Join-Path $TempRoot "allowed.txt"),
        "# agent-pack:allow-mojibake $mojibake",
        $Utf8NoBom
    )

    [IO.File]::WriteAllBytes(
        (Join-Path $TempRoot "invalid-utf8.txt"),
        [byte[]]@(0x43, 0xC3, 0x28, 0x44)
    )

    Invoke-CheckerCase `
        -Name "valid UTF-8 accents" `
        -RelativePath "correct.txt" `
        -ExpectedExitCode 0 `
        -ExpectedOutput "Text encoding check passed"
    Invoke-CheckerCase `
        -Name "common mojibake" `
        -RelativePath "mojibake.txt" `
        -ExpectedExitCode 1 `
        -ExpectedOutput "misdecoded-utf8-c3"
    Invoke-CheckerCase `
        -Name "replacement character" `
        -RelativePath "replacement.txt" `
        -ExpectedExitCode 1 `
        -ExpectedOutput "replacement-character"
    Invoke-CheckerCase `
        -Name "intentional mojibake marker" `
        -RelativePath "allowed.txt" `
        -ExpectedExitCode 0 `
        -ExpectedOutput "Text encoding check passed"
    Invoke-CheckerCase `
        -Name "invalid UTF-8 bytes" `
        -RelativePath "invalid-utf8.txt" `
        -ExpectedExitCode 1 `
        -ExpectedOutput "invalid-utf8"

    Remove-Item -LiteralPath (Join-Path $TempRoot "mojibake.txt"), (Join-Path $TempRoot "replacement.txt"), (Join-Path $TempRoot "allowed.txt"), (Join-Path $TempRoot "invalid-utf8.txt") -Force
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & git -C $TempRoot init -q 2>$null
        Assert-True ($LASTEXITCODE -eq 0) "Unable to initialize the default-scan Git fixture."
        & git -C $TempRoot -c user.name=agent-pack-test -c user.email=agent-pack@example.invalid add correct.txt 2>$null
        Assert-True ($LASTEXITCODE -eq 0) "Unable to stage the default-scan fixture."
        & git -C $TempRoot -c user.name=agent-pack-test -c user.email=agent-pack@example.invalid commit -qm baseline 2>$null
        Assert-True ($LASTEXITCODE -eq 0) "Unable to commit the default-scan fixture."
        & git -C $TempRoot config core.autocrlf true
        [IO.File]::AppendAllText((Join-Path $TempRoot "correct.txt"), "`nlinha alterada", $Utf8NoBom)

        $defaultOutputLines = @(
            & $PowerShellExecutable `
                -NoLogo `
                -NoProfile `
                -ExecutionPolicy Bypass `
                -File $Checker `
                -RepoPath $TempRoot 2>&1
        )
        $defaultExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    $defaultOutput = $defaultOutputLines | Out-String
    Assert-True ($defaultExitCode -eq 0) "Default Git changed-file scan failed with exit $defaultExitCode.`n$defaultOutput"
    Assert-True ($defaultOutput -match "Text encoding check passed") "Default Git changed-file scan did not report success.`n$defaultOutput"

    Write-Host "Text encoding checker tests passed: 6 cases."
}
finally {
    if (Test-Path -LiteralPath $TempRoot) {
        $resolvedTempRoot = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $TempRoot).Path)
        $expectedPrefix = $TempBase + [IO.Path]::DirectorySeparatorChar + "agent-pack-encoding-test-"
        if (-not $resolvedTempRoot.StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to clean unexpected temporary path: $resolvedTempRoot"
        }
        Remove-Item -LiteralPath $resolvedTempRoot -Recurse -Force
    }
}
