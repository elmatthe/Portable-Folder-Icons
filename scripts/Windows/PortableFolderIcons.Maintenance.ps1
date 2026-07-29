Set-StrictMode -Version 2.0

function Test-PfiInstalledRuntime {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$InstallRoot)

    $requiredScripts = @(
        'Cleanup-PortableFolderIcons.ps1',
        'Install-PortableFolderIcons.ps1',
        'Invoke-PortableFolderIcons.ps1',
        'PortableFolderIcons.Actions.ps1',
        'PortableFolderIcons.Core.ps1',
        'PortableFolderIcons.Integration.ps1',
        'PortableFolderIcons.Maintenance.ps1'
    )
    $missing = New-Object System.Collections.Generic.List[string]
    foreach ($name in $requiredScripts) {
        $path = Join-Path (Join-Path $InstallRoot 'runtime') $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $missing.Add($name) }
    }
    if ($missing.Count -gt 0) {
        throw ('Installed runtime is incomplete. Missing: {0}' -f ($missing -join ', '))
    }
    $settings = Read-PfiInstalledSettings (Join-Path $InstallRoot 'settings.json')
    $manifest = Read-PfiManifest (Join-Path $InstallRoot 'manifest.json')
    $validated = 0
    foreach ($entry in @($manifest.entries | Where-Object validationState -eq 'Accepted')) {
        if ([string]$entry.hash -notmatch '^[a-fA-F0-9]{64}$') {
            throw "Manifest entry '$($entry.originalFilename)' has an invalid hash."
        }
        $iconPath = Join-Path (Join-Path $InstallRoot 'icons') ([string]$entry.cachedFilename)
        if (-not (Test-Path -LiteralPath $iconPath -PathType Leaf)) {
            throw "Cached icon is missing: $($entry.cachedFilename)"
        }
        if ((Get-PfiSha256 $iconPath) -ne ([string]$entry.hash).ToLowerInvariant()) {
            throw "Cached icon is corrupt: $($entry.cachedFilename)"
        }
        $validated++
    }
    return [pscustomobject]@{
        Manifest = $manifest
        Settings = $settings
        ValidatedIcons = $validated
    }
}

function Invoke-PfiRepair {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$InstallRoot,
        [switch]$SkipRegistry
    )

    $state = Test-PfiInstalledRuntime $InstallRoot
    if (-not $SkipRegistry) {
        [void](Register-PfiContextMenu -Manifest $state.Manifest -InstallRoot $InstallRoot `
            -DeveloperMode ([bool]$state.Settings.developerMode))
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
        Runtime = 'Valid'
        ValidatedIcons = $state.ValidatedIcons
        Registry = if ($SkipRegistry) { 'Skipped' } else { 'Recreated' }
        ImportedRepositoryIcons = $false
        GeneratedResources = $generatedResources
        DeveloperMode = [bool]$state.Settings.developerMode
    }
}

function Remove-PfiInstalledFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$InstallRoot,
        [switch]$PurgeCache
    )

    $root = [IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
    $expectedParent = [IO.Path]::GetFullPath($env:LOCALAPPDATA).TrimEnd('\')
    $isTestRoot = $root -match '(?i)[\\/]PfiTests-[a-f0-9]+[\\/]stable install ünicode$'
    if (-not $isTestRoot) {
        $expected = Join-Path $expectedParent 'Portable-Folder-Icons'
        if (-not $root.Equals($expected, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Refusing cleanup outside the exact Portable-Folder-Icons install root.'
        }
    }
    foreach ($relativePath in @('runtime', 'manifest.json', 'settings.json')) {
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
        [switch]$SkipRegistry
    )

    if (-not $Confirmed) { throw 'Uninstall requires explicit confirmation.' }
    if (-not $SkipRegistry) {
        Remove-PfiContextMenu -Confirm:$false
        $cleanupSource = Join-Path (Join-Path $InstallRoot 'runtime') 'Cleanup-PortableFolderIcons.ps1'
        if (-not (Test-Path -LiteralPath $cleanupSource -PathType Leaf)) {
            throw 'The uninstall cleanup helper is missing. Rerun Repair or repository setup.'
        }
        $cleanupTarget = Join-Path $InstallRoot '.uninstall-cleanup.ps1'
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
