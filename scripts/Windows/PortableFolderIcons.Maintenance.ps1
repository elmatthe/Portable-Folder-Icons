Set-StrictMode -Version 2.0

# Phase 0A (ADR 021). Repair can rebuild only the HKCU registration; everything else (runtime, broker, manifest,
# settings, cached icons) comes back only from the setup launcher, so every Repair failure names it.
$script:PfiSetupGuidance = 'To restore Portable Folder Icons, double-click Setup_and_Run-Portable-Folder-Icons.bat in your Portable Folder Icons folder. It needs no administrator rights.'
# Repair and ordinary Uninstall hold one short named lock per user and install root, only for the maintenance work
# itself (never while a dialog is open). A second request waits at most this long, then reports that it changed nothing.
$script:PfiMaintenanceLockTimeoutSeconds = 60
# Invoke-PfiUninstall copies the cleanup helper here; the helper deletes it last, after the runtime.
$script:PfiUninstallCleanupMarker = '.uninstall-cleanup.ps1'
# Optional observer for verification: scriptblock param($Event, $Detail). Only the dispatcher's test mode sets it.
$script:PfiMaintenanceTrace = $null
# Exit codes of Invoke-PfiMaintenanceRequest (and of the dispatcher for Repair/Uninstall).
$script:PfiMaintenanceExitCompleted = 0
$script:PfiMaintenanceExitFailed = 1
$script:PfiMaintenanceExitCancelled = 2
$script:PfiMaintenanceExitPartial = 3

function Write-PfiMaintenanceTrace {
    param([string]$EventName, [string]$Detail = '')
    if ($null -eq $script:PfiMaintenanceTrace) { return }
    try { & $script:PfiMaintenanceTrace $EventName $Detail } catch { }
}

function Get-PfiInstalledRuntimeState {
    # Validates everything Repair depends on and diagnoses EVERY cached icon instead of stopping at the first damaged
    # one. Throws only for damage Repair cannot work around: runtime scripts, broker, settings or the manifest itself.
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$InstallRoot)

    $requiredScripts = @(
        'Cleanup-PortableFolderIcons.ps1',
        'Install-PortableFolderIcons.ps1',
        'Invoke-PortableFolderIcons.Hidden.vbs',
        'Invoke-PortableFolderIcons.ps1',
        'PortableFolderIcons.Actions.ps1',
        'PortableFolderIcons.Core.ps1',
        'PortableFolderIcons.Integration.ps1',
        'PortableFolderIcons.Maintenance.ps1',
        'PortableFolderIcons.Selection.ps1'
    )
    $missing = New-Object System.Collections.Generic.List[string]
    foreach ($name in $requiredScripts) {
        $path = Join-Path (Join-Path $InstallRoot 'runtime') $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $missing.Add($name) }
    }
    if ($missing.Count -gt 0) {
        throw ('Installed runtime is incomplete. Missing: {0}' -f ($missing -join ', '))
    }
    $selectionRoot = Join-Path (Join-Path $InstallRoot 'runtime') 'SelectionHandler'
    $selectionManifest = Read-PfiSelectionBrokerBuildManifest `
        (Join-Path $selectionRoot 'SelectionBroker.build.json')
    $selectionBroker = Test-PfiSelectionBrokerArtifact `
        (Join-Path $selectionRoot 'PortableFolderIcons.SelectionBroker.exe') $selectionManifest
    $settings = Read-PfiInstalledSettings (Join-Path $InstallRoot 'settings.json')
    $manifest = Read-PfiManifest (Join-Path $InstallRoot 'manifest.json')
    $accepted = @($manifest.entries | Where-Object validationState -eq 'Accepted')
    $damaged = New-Object System.Collections.Generic.List[object]
    $validated = 0
    foreach ($entry in $accepted) {
        $hash = [string]$entry.hash
        if ($hash -notmatch '^[a-fA-F0-9]{64}$') {
            throw "Manifest entry '$($entry.originalFilename)' has an invalid hash."
        }
        if ([string]::IsNullOrWhiteSpace([string]$entry.menuLabel)) {
            throw "Manifest entry '$($entry.originalFilename)' has no menu label."
        }
        # Setup always names a cached icon after its SHA-256; anything else is a damaged manifest, never a path.
        if (-not ([string]$entry.cachedFilename).Equals($hash + '.ico', [StringComparison]::OrdinalIgnoreCase)) {
            throw "Manifest entry '$($entry.originalFilename)' names an unexpected cached file."
        }
        $iconPath = Join-Path (Join-Path $InstallRoot 'icons') ([string]$entry.cachedFilename)
        $problem = $null
        if (-not (Test-Path -LiteralPath $iconPath -PathType Leaf)) { $problem = 'Missing' }
        else {
            try {
                if ((Get-PfiSha256 $iconPath) -ne $hash.ToLowerInvariant()) { $problem = 'Corrupt' }
            }
            catch { $problem = 'Unreadable' }
        }
        if ($null -eq $problem) { $validated++; continue }
        $damaged.Add([pscustomobject][ordered]@{
            MenuLabel = [string]$entry.menuLabel
            CachedFilename = [string]$entry.cachedFilename
            Hash = $hash.ToLowerInvariant()
            Problem = $problem
        })
    }
    return [pscustomobject]@{
        Manifest = $manifest
        Settings = $settings
        AcceptedIcons = $accepted.Count
        ValidatedIcons = $validated
        DamagedIcons = $damaged.ToArray()
        SelectionBroker = $selectionBroker
    }
}

function Test-PfiInstalledRuntime {
    # Strict form (unchanged contract): throws on the first damaged cached icon. Used where a fully healthy
    # installation is a precondition, for example the opt-in installed COM check.
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$InstallRoot)

    $state = Get-PfiInstalledRuntimeState $InstallRoot
    foreach ($icon in @($state.DamagedIcons)) {
        switch ($icon.Problem) {
            'Missing' { throw "Cached icon is missing: $($icon.CachedFilename)" }
            'Unreadable' { throw "Cached icon could not be read: $($icon.CachedFilename)" }
            default { throw "Cached icon is corrupt: $($icon.CachedFilename)" }
        }
    }
    return [pscustomobject]@{
        Manifest = $state.Manifest
        Settings = $state.Settings
        ValidatedIcons = $state.ValidatedIcons
        SelectionBroker = $state.SelectionBroker
    }
}

function Select-PfiRegistryRootArguments {
    # Keeps only the registry-root arguments a command accepts (Remove-PfiContextMenu takes no HKCR references).
    param([hashtable]$RegistryRoots, [Parameter(Mandatory = $true)][string]$CommandName)

    $selected = @{}
    if ($null -eq $RegistryRoots) { return $selected }
    $parameters = (Get-Command $CommandName).Parameters
    foreach ($key in @($RegistryRoots.Keys)) {
        if ($parameters.ContainsKey([string]$key)) { $selected[[string]$key] = $RegistryRoots[$key] }
    }
    return $selected
}

function New-PfiRepairFailureMessage {
    param([Parameter(Mandatory = $true)][string]$Reason, [string]$Consequence = 'Nothing was changed.')

    return ("Repair could not complete.`n`n{0}`n{1}`n`n{2}" -f $Reason.Trim(), $Consequence, $script:PfiSetupGuidance)
}

function Invoke-PfiRepair {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$InstallRoot,
        [switch]$SkipRegistry,
        [hashtable]$RegistryRoots = @{}
    )

    try { $state = Get-PfiInstalledRuntimeState $InstallRoot }
    catch { throw (New-PfiRepairFailureMessage ('The installation is damaged: ' + $_.Exception.Message)) }

    # Damaged icons are left out of the menu. Their manifest entries and cached files stay exactly as they are:
    # Repair cannot restore their bytes, and registering them would offer icons that Apply must refuse.
    $damagedHashes = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($icon in @($state.DamagedIcons)) { [void]$damagedHashes.Add($icon.Hash) }
    $menuManifest = [pscustomobject]@{
        schemaVersion = $state.Manifest.schemaVersion
        productVersion = $state.Manifest.productVersion
        installedAt = $state.Manifest.installedAt
        entries = @($state.Manifest.entries | Where-Object {
            -not ($_.validationState -eq 'Accepted' -and $damagedHashes.Contains([string]$_.hash))
        })
    }
    $registry = 'Skipped'
    if (-not $SkipRegistry) {
        $rootArguments = Select-PfiRegistryRootArguments $RegistryRoots 'Register-PfiContextMenu'
        try {
            [void](Register-PfiContextMenu -Manifest $menuManifest -InstallRoot $InstallRoot `
                -DeveloperMode ([bool]$state.Settings.developerMode) @rootArguments)
        }
        catch {
            throw (New-PfiRepairFailureMessage `
                ('Repair checked the installed files but could not recreate the Explorer menu: ' + $_.Exception.Message) `
                'The Folder Icons menu may be missing or incomplete until the installation is restored.')
        }
        $registry = 'Recreated'
    }
    # Generated per-folder resources are counted but deliberately NOT deleted.
    # Whether a resource is still referenced can only be answered by reading the
    # desktop.ini of every folder it was applied to, which Repair cannot
    # enumerate. Deleting one that is still referenced makes the folder fall back
    # to the plain default icon permanently, so retention is the safe default.
    $generatedRoot = Join-Path (Join-Path $InstallRoot 'icons') 'applied'
    $generatedResources = 0
    if (Test-Path -LiteralPath $generatedRoot -PathType Container) {
        $generatedResources = @(Get-ChildItem -LiteralPath $generatedRoot -File -Filter '*.ico').Count
    }
    return [pscustomobject]@{
        Action = 'Repair'
        Outcome = if (@($state.DamagedIcons).Count -gt 0) { 'PartiallyRepaired' } else { 'Repaired' }
        Runtime = 'Valid'
        AcceptedIcons = $state.AcceptedIcons
        ValidatedIcons = $state.ValidatedIcons
        DamagedIcons = @($state.DamagedIcons)
        RegisteredIcons = if ($registry -eq 'Recreated') { $state.ValidatedIcons } else { 0 }
        Registry = $registry
        ImportedRepositoryIcons = $false
        GeneratedResources = $generatedResources
        DeveloperMode = [bool]$state.Settings.developerMode
        SelectionBrokerPlatform = $state.SelectionBroker.Platform
    }
}

function Format-PfiRepairResult {
    # What Repair actually checked and recreated; damaged icons are reported as NOT repaired.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Result,
        [switch]$PreviousOperationInterrupted
    )

    $damaged = @($Result.DamagedIcons)
    $lines = New-Object System.Collections.Generic.List[string]
    if ($damaged.Count -eq 0) { $lines.Add('Repair completed.') }
    else { $lines.Add('Repair partially completed. Some cached icons are damaged and were NOT repaired.') }
    $lines.Add('')
    $lines.Add('Checked:')
    $lines.Add('- Runtime files and selection broker: valid')
    $lines.Add(('- Cached icons verified: {0} of {1}' -f $Result.ValidatedIcons, $Result.AcceptedIcons))
    foreach ($icon in $damaged) {
        $problem = switch ($icon.Problem) {
            'Missing' { 'missing' }
            'Unreadable' { 'could not be read' }
            default { 'damaged (its content no longer matches its recorded SHA-256)' }
        }
        $lines.Add(('- {0}: {1}; not repaired and left out of the menu' -f $icon.MenuLabel, $problem))
    }
    if ($Result.Registry -eq 'Recreated') {
        $lines.Add(('- Explorer menu: recreated with {0} icon(s)' -f $Result.RegisteredIcons))
    }
    else { $lines.Add('- Explorer menu: not changed') }
    $lines.Add(('- Developer Mode: {0}' -f $(if ($Result.DeveloperMode) { 'on' } else { 'off' })))
    if ($PreviousOperationInterrupted) {
        $lines.Add('')
        $lines.Add('A previous Repair or Uninstall ended before it finished. This Repair checked the installation again.')
    }
    $lines.Add('')
    if ($damaged.Count -gt 0) {
        $lines.Add('Repair cannot restore damaged icons. Setup copies them again from the icon files still in your Portable Folder Icons folder. ' + $script:PfiSetupGuidance)
    }
    else {
        $lines.Add('Repair does not import new icons. To add or remove icons, double-click Setup_and_Run-Portable-Folder-Icons.bat.')
    }
    return ($lines -join "`n")
}

function Format-PfiUninstallFailure {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Reason, [switch]$NothingChanged)

    $state = if ($NothingChanged) { 'Nothing was changed.' } else { 'The Folder Icons menu may be unchanged or partly removed.' }
    return ("Uninstall could not complete.`n`n{0}`n{1} Customized folders were not changed; ordinary Uninstall never changes them.`n`nTo return to a working installation, double-click Setup_and_Run-Portable-Folder-Icons.bat in your Portable Folder Icons folder, then run Uninstall again if you still want to remove it." -f $Reason.Trim(), $state)
}

function Get-PfiMaintenanceLockName {
    # Local\ (this logon session), plus the user's SID and the install root, so the lock is per user and per
    # installation and never machine-wide.
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$InstallRoot)

    $root = [IO.Path]::GetFullPath($InstallRoot).TrimEnd('\').ToLowerInvariant()
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $digest = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($root)))).Replace('-', '').Substring(0, 16)
    }
    finally { $sha.Dispose() }
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    return ('Local\PortableFolderIcons.Maintenance.{0}.{1}' -f $sid, $digest)
}

function Test-PfiAbandonedMutexException {
    param($Exception)
    for ($current = $Exception; $null -ne $current; $current = $current.InnerException) {
        if ($current -is [System.Threading.AbandonedMutexException]) { return $true }
    }
    return $false
}

function Enter-PfiMaintenanceLock {
    # Returns an owned lock, or throws TimeoutException after the bounded wait. A lock left behind by a process that
    # ended without releasing it (abandoned) is taken over and reported, never waited on forever.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$InstallRoot,
        [int]$TimeoutSeconds = $script:PfiMaintenanceLockTimeoutSeconds
    )

    if ($TimeoutSeconds -lt 0) { throw 'The maintenance lock timeout must not be negative.' }
    $name = Get-PfiMaintenanceLockName $InstallRoot
    $mutex = New-Object System.Threading.Mutex($false, $name)
    $acquired = $false
    $abandoned = $false
    Write-PfiMaintenanceTrace 'lock-waiting'
    try {
        try { $acquired = $mutex.WaitOne([TimeSpan]::FromSeconds($TimeoutSeconds)) }
        catch {
            if (-not (Test-PfiAbandonedMutexException $_.Exception)) { throw }
            $acquired = $true
            $abandoned = $true
        }
    }
    catch {
        $mutex.Dispose()
        throw
    }
    if (-not $acquired) {
        $mutex.Dispose()
        Write-PfiMaintenanceTrace 'lock-timeout'
        throw (New-Object System.TimeoutException(
            ('Another Portable Folder Icons Repair or Uninstall is still running. This request waited {0} seconds and stopped without changing anything. Try again when the other operation has finished.' -f $TimeoutSeconds)))
    }
    Write-PfiMaintenanceTrace 'lock-acquired' $(if ($abandoned) { 'abandoned' } else { '' })
    return [pscustomobject]@{ Mutex = $mutex; Name = $name; Abandoned = $abandoned; Released = $false }
}

function Exit-PfiMaintenanceLock {
    [CmdletBinding()]
    param($Lock)

    if ($null -eq $Lock -or $Lock.Released) { return }
    # Traced while still owned, so an observer can order critical sections: after ReleaseMutex another process may
    # acquire the lock before this process records anything.
    Write-PfiMaintenanceTrace 'lock-releasing'
    try { $Lock.Mutex.ReleaseMutex() }
    finally {
        $Lock.Mutex.Dispose()
        $Lock.Released = $true
        Write-PfiMaintenanceTrace 'lock-released'
    }
}

function Get-PfiMaintenanceRecordPath {
    param([Parameter(Mandatory = $true)][string]$InstallRoot)
    return (Join-Path (Join-Path $InstallRoot 'state') 'maintenance.json')
}

function Write-PfiMaintenanceRecord {
    # Best effort, written only while the maintenance lock is held: the last Repair's start, so overlapping requests
    # (one Explorer process per selected folder) can recognise that their work was just done.
    param(
        [Parameter(Mandatory = $true)][string]$InstallRoot,
        [Parameter(Mandatory = $true)][string]$Operation,
        [Parameter(Mandatory = $true)][datetime]$StartedUtc,
        [Parameter(Mandatory = $true)][string]$Outcome
    )

    $path = Get-PfiMaintenanceRecordPath $InstallRoot
    $temporary = '{0}.{1}.tmp' -f $path, [guid]::NewGuid().ToString('N')
    try {
        $parent = Split-Path -Parent $path
        if (-not (Test-Path -LiteralPath $parent -PathType Container)) { [void](New-Item -ItemType Directory -Path $parent -Force) }
        $json = [ordered]@{
            schemaVersion = 1
            operation = $Operation
            startedUtcTicks = $StartedUtc.ToUniversalTime().Ticks
            startedUtc = $StartedUtc.ToUniversalTime().ToString('o')
            finishedUtc = [DateTime]::UtcNow.ToString('o')
            outcome = $Outcome
            processId = $PID
        } | ConvertTo-Json
        [IO.File]::WriteAllText($temporary, $json, (New-Object Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $temporary -Destination $path -Force
    }
    catch { Write-PfiMaintenanceTrace 'record-failed' $_.Exception.Message }
    finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
    }
}

function Test-PfiRepairCovered {
    # True when another process started a Repair after this request was launched and has finished it. Explorer may
    # start one Repair process per selected folder; those requests coalesce into the one result already reported.
    param(
        [Parameter(Mandatory = $true)][string]$InstallRoot,
        [Parameter(Mandatory = $true)][datetime]$RequestedUtc
    )

    $path = Get-PfiMaintenanceRecordPath $InstallRoot
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }
    try { $record = [IO.File]::ReadAllText($path) | ConvertFrom-Json }
    catch { return $false }
    if ($null -eq $record -or [string]$record.operation -ne 'Repair' -or [int]$record.processId -eq $PID) { return $false }
    try { $started = [long]$record.startedUtcTicks }
    catch { return $false }
    return ($started -ge $RequestedUtc.ToUniversalTime().Ticks)
}

function Test-PfiUninstallStarted {
    # An ordinary Uninstall removes the registration first, then a helper deletes the runtime and finally its own
    # marker. Marker or missing runtime, together with an absent registration, means removal has begun or finished.
    param(
        [Parameter(Mandatory = $true)][string]$InstallRoot,
        [hashtable]$RegistryRoots = @{},
        [switch]$SkipRegistry
    )

    $marker = Test-Path -LiteralPath (Join-Path $InstallRoot $script:PfiUninstallCleanupMarker) -PathType Leaf
    $dispatcher = Join-Path (Join-Path $InstallRoot 'runtime') 'Invoke-PortableFolderIcons.ps1'
    $runtimeGone = -not (Test-Path -LiteralPath $dispatcher -PathType Leaf)
    if (-not ($marker -or $runtimeGone)) { return $false }
    if ($SkipRegistry) { return $true }
    $registryRoot = $script:PfiProductionRegistryRoot
    if ($null -ne $RegistryRoots -and $RegistryRoots.ContainsKey('RegistryRoot')) { $registryRoot = [string]$RegistryRoots['RegistryRoot'] }
    return (-not (Test-Path -LiteralPath $registryRoot))
}

function Get-PfiProcessStartUtc {
    try { return (Get-Process -Id $PID).StartTime.ToUniversalTime() }
    catch { return [DateTime]::UtcNow }
}

function Invoke-PfiMaintenanceRequest {
    # One Explorer Repair or Uninstall request, as the dispatcher runs it. ShowDialog is
    # param($Message, $Title, $Buttons 'OK'|'YesNo', $Image 'Information'|'Warning'|'Error') and returns 'OK'|'Yes'|'No'.
    # Returns 0 completed (or coalesced into another request's result), 1 failed, 2 cancelled, 3 partially repaired.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateSet('Repair', 'Uninstall')][string]$Action,
        [Parameter(Mandatory = $true)][string]$InstallRoot,
        [Parameter(Mandatory = $true)][scriptblock]$ShowDialog,
        [hashtable]$RegistryRoots = @{},
        [switch]$SkipRegistry,
        [int]$LockTimeoutSeconds = $script:PfiMaintenanceLockTimeoutSeconds,
        $RequestedUtc = $null
    )

    if ($null -eq $RequestedUtc) { $RequestedUtc = Get-PfiProcessStartUtc }
    if ($Action -eq 'Repair') {
        return (Invoke-PfiRepairRequest -InstallRoot $InstallRoot -ShowDialog $ShowDialog -RegistryRoots $RegistryRoots `
            -SkipRegistry:$SkipRegistry -LockTimeoutSeconds $LockTimeoutSeconds -RequestedUtc ([datetime]$RequestedUtc))
    }
    return (Invoke-PfiUninstallRequest -InstallRoot $InstallRoot -ShowDialog $ShowDialog -RegistryRoots $RegistryRoots `
        -SkipRegistry:$SkipRegistry -LockTimeoutSeconds $LockTimeoutSeconds)
}

function Invoke-PfiRepairRequest {
    param(
        [string]$InstallRoot, [scriptblock]$ShowDialog, [hashtable]$RegistryRoots, [switch]$SkipRegistry,
        [int]$LockTimeoutSeconds, [datetime]$RequestedUtc
    )

    $lock = $null
    $result = $null
    $failure = $null
    $coalesced = $false
    $interrupted = $false
    try {
        $lock = Enter-PfiMaintenanceLock -InstallRoot $InstallRoot -TimeoutSeconds $LockTimeoutSeconds
        $interrupted = $lock.Abandoned
        if (-not $interrupted -and (Test-PfiRepairCovered -InstallRoot $InstallRoot -RequestedUtc $RequestedUtc)) {
            $coalesced = $true
        }
        elseif (Test-PfiUninstallStarted -InstallRoot $InstallRoot -RegistryRoots $RegistryRoots -SkipRegistry:$SkipRegistry) {
            $failure = New-PfiRepairFailureMessage 'Portable Folder Icons is being uninstalled, or another request has already uninstalled it.' 'Repair did not change anything.'
        }
        else {
            $started = [DateTime]::UtcNow
            Write-PfiMaintenanceTrace 'repair-start'
            try { $result = Invoke-PfiRepair -InstallRoot $InstallRoot -SkipRegistry:$SkipRegistry -RegistryRoots $RegistryRoots }
            catch { $failure = $_.Exception.Message }
            $outcome = if ($null -ne $failure) { 'Failed' } else { $result.Outcome }
            Write-PfiMaintenanceRecord -InstallRoot $InstallRoot -Operation 'Repair' -StartedUtc $started -Outcome $outcome
            Write-PfiMaintenanceTrace 'repair-end' $outcome
        }
    }
    catch {
        $failure = if ($_.Exception -is [TimeoutException]) { New-PfiRepairFailureMessage $_.Exception.Message 'Repair did not run.' }
        else { New-PfiRepairFailureMessage $_.Exception.Message }
    }
    finally { Exit-PfiMaintenanceLock $lock }

    if ($coalesced) {
        Write-PfiMaintenanceTrace 'coalesced'
        return $script:PfiMaintenanceExitCompleted
    }
    if ($null -ne $failure) {
        if ($failure -notmatch 'Setup_and_Run-Portable-Folder-Icons\.bat') { $failure = New-PfiRepairFailureMessage $failure }
        [void](& $ShowDialog $failure 'Portable Folder Icons' 'OK' 'Error')
        return $script:PfiMaintenanceExitFailed
    }
    $partial = $result.Outcome -eq 'PartiallyRepaired'
    [void](& $ShowDialog (Format-PfiRepairResult -Result $result -PreviousOperationInterrupted:$interrupted) `
        'Portable Folder Icons' 'OK' $(if ($partial) { 'Warning' } else { 'Information' }))
    if ($partial) { return $script:PfiMaintenanceExitPartial }
    return $script:PfiMaintenanceExitCompleted
}

function Invoke-PfiUninstallRequest {
    param(
        [string]$InstallRoot, [scriptblock]$ShowDialog, [hashtable]$RegistryRoots, [switch]$SkipRegistry,
        [int]$LockTimeoutSeconds
    )

    # Unchanged order: installed settings are validated before the prompts, as before Phase 0A.
    try { [void](Read-PfiInstalledSettings (Join-Path $InstallRoot 'settings.json')) }
    catch {
        [void](& $ShowDialog (Format-PfiUninstallFailure $_.Exception.Message -NothingChanged) 'Portable Folder Icons' 'OK' 'Error')
        return $script:PfiMaintenanceExitFailed
    }
    # The prompts are unchanged; they are shown before the lock is taken, so no lock is held while one is open.
    $confirm = & $ShowDialog "Remove the Folder Icons context menu and installed runtime?`n`nCustomized folders will not be changed. The hashed icon cache will be preserved by default so their icons keep working." 'Uninstall Portable Folder Icons' 'YesNo' 'Warning'
    if ([string]$confirm -ne 'Yes') { return $script:PfiMaintenanceExitCancelled }
    $purge = [string](& $ShowDialog "Optional cache purge:`n`nPurging cached icons can BREAK icons already applied to folders.`n`nChoose Yes only if you intentionally want to purge the cache. Choose No to preserve it (recommended)." 'Purge cached icons?' 'YesNo' 'Warning') -eq 'Yes'

    $lock = $null
    $result = $null
    $failure = $null
    $nothingChanged = $false
    $alreadyDone = $false
    try {
        $lock = Enter-PfiMaintenanceLock -InstallRoot $InstallRoot -TimeoutSeconds $LockTimeoutSeconds
        if (Test-PfiUninstallStarted -InstallRoot $InstallRoot -RegistryRoots $RegistryRoots -SkipRegistry:$SkipRegistry) {
            $alreadyDone = $true
        }
        else {
            Write-PfiMaintenanceTrace 'uninstall-start'
            try {
                $result = Invoke-PfiUninstall -InstallRoot $InstallRoot -Confirmed -PurgeCache:$purge `
                    -SkipRegistry:$SkipRegistry -RegistryRoots $RegistryRoots
            }
            catch { $failure = $_.Exception.Message }
            Write-PfiMaintenanceTrace 'uninstall-end' $(if ($null -ne $failure) { 'Failed' } else { 'Completed' })
        }
    }
    catch {
        $failure = $_.Exception.Message
        $nothingChanged = $true
    }
    finally { Exit-PfiMaintenanceLock $lock }

    if ($alreadyDone) {
        Write-PfiMaintenanceTrace 'coalesced'
        [void](& $ShowDialog 'Portable Folder Icons has already been uninstalled by another request. This request changed nothing, including the cached icons.' 'Portable Folder Icons' 'OK' 'Information')
        return $script:PfiMaintenanceExitCompleted
    }
    if ($null -ne $failure) {
        [void](& $ShowDialog (Format-PfiUninstallFailure $failure -NothingChanged:$nothingChanged) 'Portable Folder Icons' 'OK' 'Error')
        return $script:PfiMaintenanceExitFailed
    }
    [void](& $ShowDialog $(if ($result.CachePreserved) {
            "Uninstall completed. Cached icons were preserved at:`n$($result.CachePath)`n`nThis keeps icons on already-customized folders working."
        } else {
            'Uninstall completed and the cached icons were purged as requested.'
        }) 'Portable Folder Icons' 'OK' 'Information')
    return $script:PfiMaintenanceExitCompleted
}

function Remove-PfiInstalledFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$InstallRoot,
        [switch]$PurgeCache
    )

    $root = [IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
    $expectedParent = [IO.Path]::GetFullPath($env:LOCALAPPDATA).TrimEnd('\')
    # The suite's test root. Windows PowerShell 5.1 read the former literal (u-umlaut, UTF-8 bytes C3 BC) from this
    # BOM-less file as the two characters U+00C3 U+00BC; the escapes keep exactly that match in an ASCII-only file.
    $isTestRoot = $root -match '(?i)[\\/]PfiTests-[a-f0-9]+[\\/]stable install \xC3\xBCnicode$'
    if (-not $isTestRoot) {
        $expected = Join-Path $expectedParent 'Portable-Folder-Icons'
        if (-not $root.Equals($expected, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Refusing cleanup outside the exact Portable-Folder-Icons install root.'
        }
    }
    foreach ($relativePath in @('runtime', 'state', 'manifest.json', 'settings.json')) {
        $target = Join-Path $root $relativePath
        if (Test-Path -LiteralPath $target) {
            [void](Assert-PfiPathWithinRoot $target $root)
            Remove-Item -LiteralPath $target -Recurse -Force
        }
    }
    if ($PurgeCache) {
        $icons = Join-Path $root 'icons'
        if (Test-Path -LiteralPath $icons) {
            [void](Assert-PfiPathWithinRoot $icons $root)
            Remove-Item -LiteralPath $icons -Recurse -Force
        }
    }
    return [pscustomobject]@{
        RuntimeRemoved = $true
        CachePreserved = -not $PurgeCache
        CachePath = Join-Path $root 'icons'
    }
}

function Invoke-PfiUninstall {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$InstallRoot,
        [switch]$Confirmed,
        [switch]$PurgeCache,
        [switch]$SkipRegistry,
        [hashtable]$RegistryRoots = @{}
    )

    if (-not $Confirmed) { throw 'Uninstall requires explicit confirmation.' }
    if (-not $SkipRegistry) {
        $rootArguments = Select-PfiRegistryRootArguments $RegistryRoots 'Remove-PfiContextMenu'
        Remove-PfiContextMenu -InstallRoot $InstallRoot -Confirm:$false @rootArguments
        $cleanupSource = Join-Path (Join-Path $InstallRoot 'runtime') 'Cleanup-PortableFolderIcons.ps1'
        if (-not (Test-Path -LiteralPath $cleanupSource -PathType Leaf)) {
            throw 'The uninstall cleanup helper is missing. Rerun Repair or repository setup.'
        }
        $cleanupTarget = Join-Path $InstallRoot $script:PfiUninstallCleanupMarker
        Copy-Item -LiteralPath $cleanupSource -Destination $cleanupTarget -Force
        $windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $arguments = @(
            '-NoLogo', '-NoProfile', '-WindowStyle', 'Hidden',
            '-ExecutionPolicy', 'Bypass',
            '-File', (ConvertTo-PfiQuotedCommandArgument $cleanupTarget),
            '-InstallRoot', (ConvertTo-PfiQuotedCommandArgument $InstallRoot),
            '-ParentProcessId', [string]$PID
        )
        if ($PurgeCache) { $arguments += '-PurgeCache' }
        Start-Process -FilePath $windowsPowerShell -ArgumentList $arguments -WindowStyle Hidden
        return [pscustomobject]@{
            RuntimeRemoved = $false
            CleanupScheduled = $true
            CachePreserved = -not $PurgeCache
            CachePath = Join-Path $InstallRoot 'icons'
        }
    }
    return Remove-PfiInstalledFiles -InstallRoot $InstallRoot -PurgeCache:$PurgeCache
}
