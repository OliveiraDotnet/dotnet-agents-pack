[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ScriptDir = Split-Path -Parent $PSCommandPath
$UpdaterSource = Join-Path $ScriptDir "update-agent-pack.ps1"
$TempRoot = Join-Path ([IO.Path]::GetTempPath()) ("agent-pack-update-tests-" + [Guid]::NewGuid().ToString("N"))
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

function Assert-Equal {
    param(
        $Expected,
        $Actual,
        [string]$Message
    )
    if ($Expected -ne $Actual) {
        throw "$Message Expected='$Expected' Actual='$Actual'."
    }
}

function Assert-Throws {
    param(
        [scriptblock]$Action,
        [string]$Message
    )

    $threw = $false
    try {
        & $Action
    }
    catch {
        $threw = $true
    }
    if (-not $threw) {
        throw $Message
    }
}

function Write-TestText {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content
    )

    $directory = Split-Path -Parent $Path
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }
    [IO.File]::WriteAllText($Path, $Content, $Utf8NoBom)
}

function Get-TestTextHash {
    param([Parameter(Mandatory = $true)][string]$Content)

    $normalized = $Content.Replace("`r`n", "`n").Replace("`r", "`n")
    $bytes = $Utf8NoBom.GetBytes($normalized)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function New-TestPack {
    param([Parameter(Mandatory = $true)][string]$Root)

    $scripts = Join-Path $Root "scripts"
    $template = Join-Path $Root "repo-template"
    $compatibility = Join-Path $Root "compat\releases"
    New-Item -ItemType Directory -Force -Path $scripts, $template, $compatibility | Out-Null
    Copy-Item -LiteralPath $UpdaterSource -Destination (Join-Path $scripts "update-agent-pack.ps1")

    $oldManaged = "managed version 1`n"
    $oldMerge = "merge version 1`n"
    $oldSeed = "seed version 1`n"
    $oldRemoved = "removed version 1`n"
    $newManaged = "managed version 2`n"
    $newMerge = "merge version 2`n"
    $newSeed = "seed version 2`n"
    $newAdded = "added version 2`n"

    Write-TestText -Path (Join-Path $Root "pack-version.txt") -Content "2.0.0`n"
    Write-TestText -Path (Join-Path $Root "pack-manifest.txt") -Content @"
core|managed.txt
core|merge.txt
core|seed.txt
core|added.txt
"@
    Write-TestText -Path (Join-Path $Root "pack-artifacts.txt") -Content @"
managed.asset|managed.txt|managed
merge.asset|merge.txt|merge
seed.asset|seed.txt|seed
added.asset|added.txt|managed
"@
    Write-TestText -Path (Join-Path $template "managed.txt") -Content $newManaged
    Write-TestText -Path (Join-Path $template "merge.txt") -Content $newMerge
    Write-TestText -Path (Join-Path $template "seed.txt") -Content $newSeed
    Write-TestText -Path (Join-Path $template "added.txt") -Content $newAdded

    $compatibilityContent = @(
        "managed.asset|managed.txt|$(Get-TestTextHash $oldManaged)"
        "merge.asset|merge.txt|$(Get-TestTextHash $oldMerge)"
        "seed.asset|seed.txt|$(Get-TestTextHash $oldSeed)"
        "removed.asset|removed.txt|$(Get-TestTextHash $oldRemoved)"
    ) -join "`n"
    Write-TestText -Path (Join-Path $compatibility "1.1.0.txt") -Content ($compatibilityContent + "`n")

    return [pscustomobject]@{
        Updater = Join-Path $scripts "update-agent-pack.ps1"
        OldManaged = $oldManaged
        OldManagedHash = Get-TestTextHash $oldManaged
        OldMerge = $oldMerge
        OldMergeHash = Get-TestTextHash $oldMerge
        OldSeed = $oldSeed
        OldSeedHash = Get-TestTextHash $oldSeed
        OldRemoved = $oldRemoved
        OldRemovedHash = Get-TestTextHash $oldRemoved
        NewManaged = $newManaged
        NewManagedHash = Get-TestTextHash $newManaged
        NewMerge = $newMerge
        NewMergeHash = Get-TestTextHash $newMerge
        NewSeed = $newSeed
        NewAdded = $newAdded
        NewAddedHash = Get-TestTextHash $newAdded
    }
}

function New-RenameTestPack {
    param([Parameter(Mandatory = $true)][string]$Root)

    $scripts = Join-Path $Root "scripts"
    $template = Join-Path $Root "repo-template"
    $compatibility = Join-Path $Root "compat\releases"
    New-Item -ItemType Directory -Force -Path $scripts, $template, $compatibility | Out-Null
    Copy-Item -LiteralPath $UpdaterSource -Destination (Join-Path $scripts "update-agent-pack.ps1")

    $oldContent = "stable artifact at old path`n"
    $newContent = "stable artifact at renamed path`n"
    Write-TestText -Path (Join-Path $Root "pack-version.txt") -Content "2.0.0`n"
    Write-TestText -Path (Join-Path $Root "pack-manifest.txt") -Content "core|renamed/managed.txt`n"
    Write-TestText -Path (Join-Path $Root "pack-artifacts.txt") -Content "managed.asset|renamed/managed.txt|managed`n"
    Write-TestText -Path (Join-Path $template "renamed\managed.txt") -Content $newContent
    Write-TestText -Path (Join-Path $compatibility "1.1.0.txt") -Content "managed.asset|managed.txt|$(Get-TestTextHash $oldContent)`n"

    return [pscustomobject]@{
        Updater = Join-Path $scripts "update-agent-pack.ps1"
        OldContent = $oldContent
        OldHash = Get-TestTextHash $oldContent
        NewContent = $newContent
        NewHash = Get-TestTextHash $newContent
    }
}

function Invoke-TestUpdater {
    param(
        [Parameter(Mandatory = $true)][string]$Updater,
        [Parameter(Mandatory = $true)][hashtable]$Parameters
    )

    & $Updater @Parameters -Confirm:$false 6>$null 3>$null
}

try {
    New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null
    $packRoot = Join-Path $TempRoot "pack"
    $pack = New-TestPack -Root $packRoot

    # Scenario 1: plan-only, conflict atomicity, add, update, accepted merge,
    # recoverable removal and seed preservation.
    $repo = Join-Path $TempRoot "repo-stateful"
    New-Item -ItemType Directory -Force -Path $repo | Out-Null
    $localMerge = "merge version 1`nrepository customization`n"
    Write-TestText -Path (Join-Path $repo "managed.txt") -Content $pack.OldManaged
    Write-TestText -Path (Join-Path $repo "merge.txt") -Content $localMerge
    Write-TestText -Path (Join-Path $repo "seed.txt") -Content $pack.OldSeed
    Write-TestText -Path (Join-Path $repo "removed.txt") -Content $pack.OldRemoved

    $initialState = @(
        "version|1.1.0"
        "profile|core"
        "integration|codex"
        "artifact|managed.asset|managed.txt|managed|1.1.0|$($pack.OldManagedHash)|tracked|-"
        "artifact|merge.asset|merge.txt|merge|1.1.0|$($pack.OldMergeHash)|tracked|-"
        "artifact|removed.asset|removed.txt|managed|1.1.0|$($pack.OldRemovedHash)|tracked|-"
    ) -join "`n"
    $statePath = Join-Path $repo ".agent-pack\state.txt"
    Write-TestText -Path $statePath -Content ($initialState + "`n")
    $stateBeforeCheck = Get-Content -LiteralPath $statePath -Raw

    Invoke-TestUpdater -Updater $pack.Updater -Parameters @{ RepoPath = $repo; Check = $true }
    Assert-Equal $pack.OldManaged (Get-Content -LiteralPath (Join-Path $repo "managed.txt") -Raw) "Check changed a managed file."
    Assert-Equal $localMerge (Get-Content -LiteralPath (Join-Path $repo "merge.txt") -Raw) "Check changed a merge file."
    Assert-Equal $pack.OldSeed (Get-Content -LiteralPath (Join-Path $repo "seed.txt") -Raw) "Check changed a seed file."
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $repo "added.txt"))) "Check added a file."
    Assert-True (Test-Path -LiteralPath (Join-Path $repo "removed.txt") -PathType Leaf) "Check removed a file."
    Assert-Equal $stateBeforeCheck (Get-Content -LiteralPath $statePath -Raw) "Check changed Agent Pack state."
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $repo ".agent-pack\.runtime"))) "Check created Agent Pack runtime files."

    Assert-Throws -Message "Apply with an unresolved merge conflict did not fail." -Action {
        Invoke-TestUpdater -Updater $pack.Updater -Parameters @{ RepoPath = $repo; Apply = $true }
    }
    Assert-Equal $pack.OldManaged (Get-Content -LiteralPath (Join-Path $repo "managed.txt") -Raw) "Conflicted apply partially updated a managed file."
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $repo "added.txt"))) "Conflicted apply partially added a file."
    Assert-True (Test-Path -LiteralPath (Join-Path $repo "removed.txt") -PathType Leaf) "Conflicted apply partially removed a file."
    Assert-Equal $stateBeforeCheck (Get-Content -LiteralPath $statePath -Raw) "Conflicted apply changed state."
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $repo ".agent-pack\.runtime"))) "Conflicted apply created Agent Pack runtime files."

    Invoke-TestUpdater -Updater $pack.Updater -Parameters @{ RepoPath = $repo; Apply = $true; AcceptMerge = @("merge.asset") }
    Assert-Equal $pack.NewManaged (Get-Content -LiteralPath (Join-Path $repo "managed.txt") -Raw) "Managed artifact was not updated."
    Assert-Equal $localMerge (Get-Content -LiteralPath (Join-Path $repo "merge.txt") -Raw) "Accepted manual merge was overwritten."
    Assert-Equal $pack.OldSeed (Get-Content -LiteralPath (Join-Path $repo "seed.txt") -Raw) "Existing seed was updated."
    Assert-Equal $pack.NewAdded (Get-Content -LiteralPath (Join-Path $repo "added.txt") -Raw) "New managed artifact was not added."
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $repo "removed.txt"))) "Removed managed artifact remained active."
    $retiredRemoved = Join-Path $repo ".agent-pack\.runtime\retired\2.0.0\removed.asset\removed.txt"
    Assert-Equal $pack.OldRemoved (Get-Content -LiteralPath $retiredRemoved -Raw) "Removed artifact was not preserved in the retirement archive."
    $runtimeIgnore = Join-Path $repo ".agent-pack\.runtime\.gitignore"
    Assert-Equal "*`n!.gitignore`n" (Get-Content -LiteralPath $runtimeIgnore -Raw) "Runtime files are not protected by the expected .gitignore."
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $repo ".agent-pack\backups"))) "Backups leaked outside the ignored runtime directory."
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $repo ".agent-pack\retired"))) "Retired files leaked outside the ignored runtime directory."

    $stateAfterApply = Get-Content -LiteralPath $statePath -Raw
    Assert-True ($stateAfterApply -match '(?m)^version\|2\.0\.0$') "State version was not advanced."
    Assert-True ($stateAfterApply -match "(?m)^artifact\|managed\.asset\|managed\.txt\|managed\|2\.0\.0\|$($pack.NewManagedHash)\|tracked\|-$") "Managed baseline was not recorded."
    Assert-True ($stateAfterApply -match "(?m)^artifact\|merge\.asset\|merge\.txt\|merge\|2\.0\.0\|$($pack.NewMergeHash)\|merged\|$(Get-TestTextHash $localMerge)$") "Accepted merge state was not recorded."
    Assert-True ($stateAfterApply -match '(?m)^artifact\|seed\.asset\|seed\.txt\|seed\|-\|-\|keep-local\|[a-f0-9]{64}$') "Seed ownership was not preserved."
    Assert-True ($stateAfterApply -notmatch '(?m)^artifact\|removed\.asset\|') "Retired artifact remained tracked."

    Invoke-TestUpdater -Updater $pack.Updater -Parameters @{ RepoPath = $repo; Apply = $true }
    Assert-Equal $stateAfterApply (Get-Content -LiteralPath $statePath -Raw) "Idempotent apply changed state."
    Assert-Equal $localMerge (Get-Content -LiteralPath (Join-Path $repo "merge.txt") -Raw) "Idempotent apply changed an accepted merge."

    Invoke-TestUpdater -Updater $pack.Updater -Parameters @{ RepoPath = $repo; Apply = $true; Integration = @("codex", "grok") }
    $grokSelectionState = Get-Content -LiteralPath $statePath -Raw
    Assert-True ($grokSelectionState -match '(?m)^integration\|codex$') "Codex was not retained in the integration override."
    Assert-True ($grokSelectionState -match '(?m)^integration\|grok$') "Grok integration override was not persisted."
    Assert-True ($grokSelectionState -notmatch '(?m)^integration\|claude$') "Claude remained selected after a codex,grok override."

    Invoke-TestUpdater -Updater $pack.Updater -Parameters @{ RepoPath = $repo; Apply = $true }
    $preservedGrokSelection = Get-Content -LiteralPath $statePath -Raw
    Assert-Equal $grokSelectionState $preservedGrokSelection "A later update did not preserve the codex,grok selection."

    Assert-Throws -Message "An integration override without mandatory Codex was accepted." -Action {
        Invoke-TestUpdater -Updater $pack.Updater -Parameters @{ RepoPath = $repo; Check = $true; Integration = @("grok") }
    }

    Remove-Item -LiteralPath (Join-Path $repo "seed.txt") -Force
    Invoke-TestUpdater -Updater $pack.Updater -Parameters @{ RepoPath = $repo; Apply = $true }
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $repo "seed.txt"))) "Repository-deleted seed was recreated."
    $stateAfterSeedDeletion = Get-Content -LiteralPath $statePath -Raw
    Assert-True ($stateAfterSeedDeletion -match '(?m)^artifact\|seed\.asset\|seed\.txt\|seed\|-\|-\|deleted-local\|-$') "Repository-deleted seed was not recorded as deleted-local."
    Invoke-TestUpdater -Updater $pack.Updater -Parameters @{ RepoPath = $repo; Apply = $true }
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $repo "seed.txt"))) "Deleted-local seed was recreated on an idempotent apply."
    Assert-Equal $stateAfterSeedDeletion (Get-Content -LiteralPath $statePath -Raw) "Deleted-local seed state was not idempotent."

    # Scenario 2: adoption without state uses only current or compatibility hashes;
    # explicit check remains read-only.
    $adoptionRepo = Join-Path $TempRoot "repo-adoption"
    New-Item -ItemType Directory -Force -Path $adoptionRepo | Out-Null
    $customSeed = "repository-owned seed`n"
    Write-TestText -Path (Join-Path $adoptionRepo "managed.txt") -Content $pack.OldManaged
    Write-TestText -Path (Join-Path $adoptionRepo "merge.txt") -Content $pack.OldMerge
    Write-TestText -Path (Join-Path $adoptionRepo "seed.txt") -Content $customSeed

    Invoke-TestUpdater -Updater $pack.Updater -Parameters @{ RepoPath = $adoptionRepo; Check = $true }
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $adoptionRepo ".agent-pack"))) "Check created Agent Pack state during adoption."
    Assert-Equal $pack.OldManaged (Get-Content -LiteralPath (Join-Path $adoptionRepo "managed.txt") -Raw) "Adoption check changed a managed file."
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $adoptionRepo "added.txt"))) "Adoption check added an artifact."

    Invoke-TestUpdater -Updater $pack.Updater -Parameters @{ RepoPath = $adoptionRepo; Apply = $true }
    Assert-Equal $pack.NewManaged (Get-Content -LiteralPath (Join-Path $adoptionRepo "managed.txt") -Raw) "Compatible managed artifact was not adopted and updated."
    Assert-Equal $pack.NewMerge (Get-Content -LiteralPath (Join-Path $adoptionRepo "merge.txt") -Raw) "Unmodified merge artifact was not adopted and updated."
    Assert-Equal $customSeed (Get-Content -LiteralPath (Join-Path $adoptionRepo "seed.txt") -Raw) "Existing seed was not preserved during adoption."
    Assert-Equal $pack.NewAdded (Get-Content -LiteralPath (Join-Path $adoptionRepo "added.txt") -Raw) "New artifact was not added during adoption."
    $adoptedState = Get-Content -LiteralPath (Join-Path $adoptionRepo ".agent-pack\state.txt") -Raw
    Assert-True ($adoptedState -match '(?m)^profile\|core$') "Adopted profiles were not recorded."
    Assert-True ($adoptedState -match '(?m)^integration\|codex$') "Adopted integration was not recorded."

    # Scenario 3: an unattributable managed file blocks all writes, then KeepLocal
    # persists the override while other safe actions proceed.
    $conflictRepo = Join-Path $TempRoot "repo-keep-local"
    New-Item -ItemType Directory -Force -Path $conflictRepo | Out-Null
    $customManaged = "repository managed replacement`n"
    Write-TestText -Path (Join-Path $conflictRepo "managed.txt") -Content $customManaged
    Write-TestText -Path (Join-Path $conflictRepo "merge.txt") -Content $pack.OldMerge

    Assert-Throws -Message "Unattributable managed content did not block apply." -Action {
        Invoke-TestUpdater -Updater $pack.Updater -Parameters @{ RepoPath = $conflictRepo; Apply = $true }
    }
    Assert-Equal $customManaged (Get-Content -LiteralPath (Join-Path $conflictRepo "managed.txt") -Raw) "Conflict apply overwrote unattributable content."
    Assert-Equal $pack.OldMerge (Get-Content -LiteralPath (Join-Path $conflictRepo "merge.txt") -Raw) "Conflict apply partially updated another artifact."
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $conflictRepo "added.txt"))) "Conflict apply partially added an artifact."
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $conflictRepo ".agent-pack"))) "Conflict apply wrote state before resolving conflicts."

    Invoke-TestUpdater -Updater $pack.Updater -Parameters @{ RepoPath = $conflictRepo; Apply = $true; KeepLocal = @("managed.asset") }
    Assert-Equal $customManaged (Get-Content -LiteralPath (Join-Path $conflictRepo "managed.txt") -Raw) "KeepLocal did not preserve managed content."
    Assert-Equal $pack.NewMerge (Get-Content -LiteralPath (Join-Path $conflictRepo "merge.txt") -Raw) "KeepLocal prevented an unrelated safe update."
    $keepLocalState = Get-Content -LiteralPath (Join-Path $conflictRepo ".agent-pack\state.txt") -Raw
    Assert-True ($keepLocalState -match '(?m)^artifact\|managed\.asset\|managed\.txt\|managed\|-\|-\|keep-local\|[a-f0-9]{64}$') "KeepLocal override was not persisted."

    # Scenario 4: state is written last. If its atomic replacement is blocked,
    # already applied file operations are rolled back.
    $rollbackRepo = Join-Path $TempRoot "repo-rollback"
    New-Item -ItemType Directory -Force -Path $rollbackRepo | Out-Null
    Write-TestText -Path (Join-Path $rollbackRepo "managed.txt") -Content $pack.OldManaged
    Write-TestText -Path (Join-Path $rollbackRepo "merge.txt") -Content $pack.OldMerge
    Write-TestText -Path (Join-Path $rollbackRepo "seed.txt") -Content $pack.OldSeed
    Write-TestText -Path (Join-Path $rollbackRepo "removed.txt") -Content $pack.OldRemoved
    $rollbackStatePath = Join-Path $rollbackRepo ".agent-pack\state.txt"
    Write-TestText -Path $rollbackStatePath -Content ($initialState + "`n")
    $stateLock = [IO.File]::Open($rollbackStatePath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        Assert-Throws -Message "A blocked state replacement did not fail reconciliation." -Action {
            Invoke-TestUpdater -Updater $pack.Updater -Parameters @{ RepoPath = $rollbackRepo; Apply = $true }
        }
    }
    finally {
        $stateLock.Dispose()
    }
    Assert-Equal $pack.OldManaged (Get-Content -LiteralPath (Join-Path $rollbackRepo "managed.txt") -Raw) "Rollback did not restore an updated managed artifact."
    Assert-Equal $pack.OldMerge (Get-Content -LiteralPath (Join-Path $rollbackRepo "merge.txt") -Raw) "Rollback did not restore an updated merge artifact."
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $rollbackRepo "added.txt"))) "Rollback did not remove an artifact added by the failed transaction."
    Assert-Equal $pack.OldRemoved (Get-Content -LiteralPath (Join-Path $rollbackRepo "removed.txt") -Raw) "Rollback did not restore a retired artifact."
    Assert-Equal ($initialState + "`n") (Get-Content -LiteralPath $rollbackStatePath -Raw) "Rollback changed the previous state."

    # Scenario 5: a stable artifact id permits a safe destination rename only
    # while the old content still matches its trusted baseline.
    $renamePackRoot = Join-Path $TempRoot "pack-rename"
    $renamePack = New-RenameTestPack -Root $renamePackRoot
    $renameState = @(
        "version|1.1.0"
        "profile|core"
        "integration|codex"
        "artifact|managed.asset|managed.txt|managed|1.1.0|$($renamePack.OldHash)|tracked|-"
    ) -join "`n"

    $renameRepo = Join-Path $TempRoot "repo-rename"
    New-Item -ItemType Directory -Force -Path $renameRepo | Out-Null
    Write-TestText -Path (Join-Path $renameRepo "managed.txt") -Content $renamePack.OldContent
    Write-TestText -Path (Join-Path $renameRepo ".agent-pack\state.txt") -Content ($renameState + "`n")
    Invoke-TestUpdater -Updater $renamePack.Updater -Parameters @{ RepoPath = $renameRepo; Apply = $true }
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $renameRepo "managed.txt"))) "Stable-id rename left the old destination active."
    Assert-Equal $renamePack.NewContent (Get-Content -LiteralPath (Join-Path $renameRepo "renamed\managed.txt") -Raw) "Stable-id rename did not install the new destination."
    Assert-Equal $renamePack.OldContent (Get-Content -LiteralPath (Join-Path $renameRepo ".agent-pack\.runtime\retired\2.0.0\managed.asset\managed.txt") -Raw) "Stable-id rename did not archive the old destination."
    $renamedState = Get-Content -LiteralPath (Join-Path $renameRepo ".agent-pack\state.txt") -Raw
    Assert-True ($renamedState -match "(?m)^artifact\|managed\.asset\|renamed/managed\.txt\|managed\|2\.0\.0\|$($renamePack.NewHash)\|tracked\|-$") "Stable-id rename did not advance state to the new destination."

    $modifiedRenameRepo = Join-Path $TempRoot "repo-rename-modified"
    New-Item -ItemType Directory -Force -Path $modifiedRenameRepo | Out-Null
    $modifiedOldPath = "locally modified old destination`n"
    Write-TestText -Path (Join-Path $modifiedRenameRepo "managed.txt") -Content $modifiedOldPath
    Write-TestText -Path (Join-Path $modifiedRenameRepo ".agent-pack\state.txt") -Content ($renameState + "`n")
    Assert-Throws -Message "Modified old destination was renamed without an explicit resolution." -Action {
        Invoke-TestUpdater -Updater $renamePack.Updater -Parameters @{ RepoPath = $modifiedRenameRepo; Apply = $true }
    }
    Assert-Equal $modifiedOldPath (Get-Content -LiteralPath (Join-Path $modifiedRenameRepo "managed.txt") -Raw) "Rename conflict changed the modified old destination."
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $modifiedRenameRepo "renamed\managed.txt"))) "Rename conflict created the new destination."
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $modifiedRenameRepo ".agent-pack\.runtime"))) "Rename conflict created runtime files."
    Invoke-TestUpdater -Updater $renamePack.Updater -Parameters @{ RepoPath = $modifiedRenameRepo; Apply = $true; KeepLocal = @("managed.asset") }
    $modifiedRenameState = Get-Content -LiteralPath (Join-Path $modifiedRenameRepo ".agent-pack\state.txt") -Raw
    Assert-True ($modifiedRenameState -match '(?m)^artifact\|managed\.asset\|managed\.txt\|managed\|-\|-\|keep-local\|[a-f0-9]{64}$') "KeepLocal did not persist a modified rename override at the old destination."
    Invoke-TestUpdater -Updater $renamePack.Updater -Parameters @{ RepoPath = $modifiedRenameRepo; Apply = $true }
    Assert-Equal $modifiedRenameState (Get-Content -LiteralPath (Join-Path $modifiedRenameRepo ".agent-pack\state.txt") -Raw) "Persisted rename override was not idempotent."

    $occupiedRenameRepo = Join-Path $TempRoot "repo-rename-occupied"
    New-Item -ItemType Directory -Force -Path (Join-Path $occupiedRenameRepo "renamed") | Out-Null
    $occupiedNewPath = "unrelated content at new destination`n"
    Write-TestText -Path (Join-Path $occupiedRenameRepo "managed.txt") -Content $renamePack.OldContent
    Write-TestText -Path (Join-Path $occupiedRenameRepo "renamed\managed.txt") -Content $occupiedNewPath
    Write-TestText -Path (Join-Path $occupiedRenameRepo ".agent-pack\state.txt") -Content ($renameState + "`n")
    Assert-Throws -Message "Occupied new destination did not block stable-id rename." -Action {
        Invoke-TestUpdater -Updater $renamePack.Updater -Parameters @{ RepoPath = $occupiedRenameRepo; Apply = $true }
    }
    Assert-Equal $renamePack.OldContent (Get-Content -LiteralPath (Join-Path $occupiedRenameRepo "managed.txt") -Raw) "Occupied rename conflict changed the old destination."
    Assert-Equal $occupiedNewPath (Get-Content -LiteralPath (Join-Path $occupiedRenameRepo "renamed\managed.txt") -Raw) "Occupied rename conflict changed the new destination."
    Invoke-TestUpdater -Updater $renamePack.Updater -Parameters @{ RepoPath = $occupiedRenameRepo; Apply = $true; AcceptPack = @("managed.asset") }
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $occupiedRenameRepo "managed.txt"))) "AcceptPack rename left the old destination active."
    Assert-Equal $renamePack.NewContent (Get-Content -LiteralPath (Join-Path $occupiedRenameRepo "renamed\managed.txt") -Raw) "AcceptPack rename did not replace the occupied new destination."
    Assert-Equal $occupiedNewPath (Get-Content -LiteralPath (Join-Path $occupiedRenameRepo ".agent-pack\.runtime\backups\2.0.0\managed.asset\managed.txt") -Raw) "AcceptPack rename did not back up occupied new content."

    $renameRollbackRepo = Join-Path $TempRoot "repo-rename-rollback"
    New-Item -ItemType Directory -Force -Path $renameRollbackRepo | Out-Null
    Write-TestText -Path (Join-Path $renameRollbackRepo "managed.txt") -Content $renamePack.OldContent
    $renameRollbackStatePath = Join-Path $renameRollbackRepo ".agent-pack\state.txt"
    Write-TestText -Path $renameRollbackStatePath -Content ($renameState + "`n")
    $renameStateLock = [IO.File]::Open($renameRollbackStatePath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        Assert-Throws -Message "Blocked rename state replacement did not fail." -Action {
            Invoke-TestUpdater -Updater $renamePack.Updater -Parameters @{ RepoPath = $renameRollbackRepo; Apply = $true }
        }
    }
    finally {
        $renameStateLock.Dispose()
    }
    Assert-Equal $renamePack.OldContent (Get-Content -LiteralPath (Join-Path $renameRollbackRepo "managed.txt") -Raw) "Rename rollback did not restore the old destination."
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $renameRollbackRepo "renamed\managed.txt"))) "Rename rollback left the new destination active."
    Assert-Equal ($renameState + "`n") (Get-Content -LiteralPath $renameRollbackStatePath -Raw) "Rename rollback changed previous state."

    Write-Host "Agent Pack updater tests passed: plan-only, add, update, conflict atomicity, removal, seed, adoption, local overrides, rollback and stable-id rename."
}
finally {
    if (Test-Path -LiteralPath $TempRoot) {
        $resolvedTemp = [IO.Path]::GetFullPath($TempRoot)
        $systemTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        if (-not $resolvedTemp.StartsWith($systemTemp, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to clean an unexpected test path: $resolvedTemp"
        }
        Remove-Item -LiteralPath $resolvedTemp -Recurse -Force
    }
}
