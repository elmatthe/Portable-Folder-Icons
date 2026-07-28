[CmdletBinding()]
param(
    [string]$RepositoryRoot,
    [string]$InstallRoot,
    [switch]$SkipRegistry
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}
$RepositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot)
if ([string]::IsNullOrWhiteSpace($InstallRoot)) {
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        throw 'LOCALAPPDATA is unavailable; the stable current-user runtime cannot be located.'
    }
    $InstallRoot = Join-Path $env:LOCALAPPDATA 'Portable-Folder-Icons'
}
$InstallRoot = [IO.Path]::GetFullPath($InstallRoot)

$corePath = Join-Path $PSScriptRoot 'PortableFolderIcons.Core.ps1'
if (-not (Test-Path -LiteralPath $corePath -PathType Leaf)) {
    throw "Required core script is missing: $corePath"
}
. $corePath
$integrationPath = Join-Path $PSScriptRoot 'PortableFolderIcons.Integration.ps1'
if (-not (Test-Path -LiteralPath $integrationPath -PathType Leaf)) {
    throw "Required integration script is missing: $integrationPath"
}
. $integrationPath
Add-Type -AssemblyName System.Drawing

function Write-SetupSummary {
    param([object[]]$Inventory)

    Write-Host ''
    Write-Host 'Icon scan results'
    Write-Host '-----------------'
    @($Inventory | Select-Object `
        @{N = 'Status'; E = { $_.Status } },
        @{N = 'Menu Label'; E = { $_.MenuLabel } },
        @{N = 'Source File'; E = { $_.SourceFile } },
        @{N = 'Hash'; E = { if ($_.Hash) { $_.Hash.Substring(0, 12) } else { '' } } },
        @{N = 'Result / Reason'; E = {
            if ($_.Status -eq 'Accepted') { $_.CacheAction } else { $_.Reason }
        }} | Format-Table -AutoSize -Wrap | Out-Host)

    $discovered = @($Inventory).Count
    $accepted = @($Inventory | Where-Object Status -eq 'Accepted').Count
    $reused = @($Inventory | Where-Object { $_.Status -eq 'Accepted' -and $_.CacheAction -eq 'Reuse' }).Count
    $copied = @($Inventory | Where-Object { $_.Status -eq 'Accepted' -and $_.CacheAction -eq 'Copied' }).Count
    $rejected = @($Inventory | Where-Object Status -eq 'Rejected').Count
    Write-Host ('Totals: discovered={0}; accepted={1}; reused={2}; copied={3}; rejected={4}' -f
        $discovered, $accepted, $reused, $copied, $rejected)
}

$sourceIcons = Join-Path $RepositoryRoot 'files\ICO-Files'
$sourceScripts = Join-Path $RepositoryRoot 'scripts\Windows'
$runtimePath = Join-Path $InstallRoot 'runtime'
$iconsPath = Join-Path $InstallRoot 'icons'
$manifestPath = Join-Path $InstallRoot 'manifest.json'
$stageRoot = Join-Path $InstallRoot ('.stage-' + [guid]::NewGuid().ToString('N'))
$stageRuntime = Join-Path $stageRoot 'runtime'
$oldRuntime = Join-Path $InstallRoot ('.runtime-old-' + [guid]::NewGuid().ToString('N'))
$oldManifest = Join-Path $InstallRoot ('.manifest-old-' + [guid]::NewGuid().ToString('N') + '.json')
$runtimeMoved = $false
$manifestMoved = $false
$previousManifest = $null

try {
    if (-not (Test-Path -LiteralPath $sourceScripts -PathType Container)) {
        throw "Runtime source directory is missing: $sourceScripts"
    }
    [void](New-Item -ItemType Directory -Path $InstallRoot -Force)
    [void](New-Item -ItemType Directory -Path $iconsPath -Force)
    [void](New-Item -ItemType Directory -Path $stageRuntime -Force)

    Write-Host ('Stable install root: {0}' -f $InstallRoot)
    Write-Host ('Icon source: {0}' -f $sourceIcons)
    Write-Host 'Staging and validating runtime scripts...'

    $runtimeSources = @(Get-ChildItem -LiteralPath $sourceScripts -Filter '*.ps1' -File | Sort-Object Name)
    $requiredRuntime = @(
        'Cleanup-PortableFolderIcons.ps1',
        'Install-PortableFolderIcons.ps1',
        'Invoke-PortableFolderIcons.ps1',
        'PortableFolderIcons.Actions.ps1',
        'PortableFolderIcons.Core.ps1',
        'PortableFolderIcons.Integration.ps1',
        'PortableFolderIcons.Maintenance.ps1'
    )
    foreach ($requiredName in $requiredRuntime) {
        if ($requiredName -notin @($runtimeSources.Name)) {
            throw "The staged runtime is incomplete: $requiredName is missing."
        }
    }
    foreach ($requiredName in $requiredRuntime) {
        $source = $runtimeSources | Where-Object Name -eq $requiredName | Select-Object -First 1
        Copy-Item -LiteralPath $source.FullName -Destination (Join-Path $stageRuntime $source.Name)
    }
    foreach ($scriptFile in @(Get-ChildItem -LiteralPath $stageRuntime -Filter '*.ps1' -File)) {
        $tokens = $null
        $errors = $null
        [void][Management.Automation.Language.Parser]::ParseFile(
            $scriptFile.FullName,
            [ref]$tokens,
            [ref]$errors
        )
        if (@($errors).Count -gt 0) {
            throw "Staged runtime script failed parsing: $($scriptFile.Name)"
        }
    }

    $inventory = @(Get-PfiIconInventory -SourceDirectory $sourceIcons -CacheDirectory $iconsPath)
    $cacheConflicts = @($inventory | Where-Object CacheAction -eq 'RejectCacheConflict')
    if ($cacheConflicts.Count -gt 0) {
        throw ('The stable icon cache contains {0} hash-filename conflict(s); the previous runtime and menu were preserved.' -f $cacheConflicts.Count)
    }
    foreach ($entry in @($inventory | Where-Object {
        $_.Status -eq 'Accepted' -and $_.CacheAction -eq 'Copy'
    })) {
        $sourcePath = Join-Path $sourceIcons $entry.SourceFile
        $destinationPath = Join-Path $iconsPath $entry.CachedFile
        Copy-Item -LiteralPath $sourcePath -Destination $destinationPath
        if ((Get-PfiSha256 -LiteralPath $destinationPath) -ne $entry.Hash) {
            Remove-Item -LiteralPath $destinationPath -Force
            throw "Cached icon verification failed for $($entry.SourceFile)."
        }
        $entry.CacheAction = 'Copied'
    }

    $manifest = New-PfiManifest -Inventory $inventory
    $stagedManifest = Join-Path $stageRoot 'manifest.json'
    Write-PfiManifest -Manifest $manifest -LiteralPath $stagedManifest
    [void](Read-PfiManifest -LiteralPath $stagedManifest)

    if (Test-Path -LiteralPath $runtimePath -PathType Container) {
        Move-Item -LiteralPath $runtimePath -Destination $oldRuntime
        $runtimeMoved = $true
    }
    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        try { $previousManifest = Read-PfiManifest -LiteralPath $manifestPath } catch { $previousManifest = $null }
        Move-Item -LiteralPath $manifestPath -Destination $oldManifest
        $manifestMoved = $true
    }
    Move-Item -LiteralPath $stageRuntime -Destination $runtimePath
    Move-Item -LiteralPath $stagedManifest -Destination $manifestPath

    if (-not $SkipRegistry) {
        [void](Register-PfiContextMenu -Manifest (Read-PfiManifest $manifestPath) -InstallRoot $InstallRoot)
    }

    if ($runtimeMoved -and (Test-Path -LiteralPath $oldRuntime -PathType Container)) {
        [void](Assert-PfiPathWithinRoot -CandidatePath $oldRuntime -AllowedRoot $InstallRoot)
        Remove-Item -LiteralPath $oldRuntime -Recurse -Force
        $runtimeMoved = $false
    }
    if ($manifestMoved -and (Test-Path -LiteralPath $oldManifest -PathType Leaf)) {
        [void](Assert-PfiPathWithinRoot -CandidatePath $oldManifest -AllowedRoot $InstallRoot)
        Remove-Item -LiteralPath $oldManifest -Force
        $manifestMoved = $false
    }

    Write-SetupSummary -Inventory $inventory
    Write-Host ''
    Write-Host 'Installed paths'
    Write-Host '---------------'
    [pscustomobject][ordered]@{
        Runtime = $runtimePath
        Icons = $iconsPath
        Manifest = $manifestPath
        Registry = if ($SkipRegistry) { 'Skipped by request' } else { $script:PfiProductionRegistryRoot }
    } | Format-List | Out-Host
    exit 0
}
catch {
    [Console]::Error.WriteLine(('ERROR: {0}' -f $_.Exception.Message))
    if ($runtimeMoved -and (Test-Path -LiteralPath $oldRuntime -PathType Container)) {
        if (Test-Path -LiteralPath $runtimePath -PathType Container) {
            [void](Assert-PfiPathWithinRoot -CandidatePath $runtimePath -AllowedRoot $InstallRoot)
            Remove-Item -LiteralPath $runtimePath -Recurse -Force
        }
        Move-Item -LiteralPath $oldRuntime -Destination $runtimePath
    }
    if ($manifestMoved -and (Test-Path -LiteralPath $oldManifest -PathType Leaf)) {
        if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
            [void](Assert-PfiPathWithinRoot -CandidatePath $manifestPath -AllowedRoot $InstallRoot)
            Remove-Item -LiteralPath $manifestPath -Force
        }
        Move-Item -LiteralPath $oldManifest -Destination $manifestPath
    }
    if (-not $SkipRegistry -and $null -ne $previousManifest) {
        try { [void](Register-PfiContextMenu -Manifest $previousManifest -InstallRoot $InstallRoot) }
        catch { [Console]::Error.WriteLine('WARNING: Previous context menu could not be restored automatically.') }
    }
    exit 20
}
finally {
    if (Test-Path -LiteralPath $stageRoot -PathType Container) {
        try {
            [void](Assert-PfiPathWithinRoot -CandidatePath $stageRoot -AllowedRoot $InstallRoot)
            Remove-Item -LiteralPath $stageRoot -Recurse -Force
        }
        catch {
            [Console]::Error.WriteLine(('WARNING: Could not remove validated staging directory: {0}' -f $_.Exception.Message))
        }
    }
}
