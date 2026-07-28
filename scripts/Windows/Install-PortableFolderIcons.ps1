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

$sourceIcons = Join-Path $RepositoryRoot 'files\ICO-FIles'
$sourceScripts = Join-Path $RepositoryRoot 'scripts\Windows'
$runtimePath = Join-Path $InstallRoot 'runtime'
$iconsPath = Join-Path $InstallRoot 'icons'
$manifestPath = Join-Path $InstallRoot 'manifest.json'
$stageRoot = Join-Path $InstallRoot ('.stage-' + [guid]::NewGuid().ToString('N'))
$stageRuntime = Join-Path $stageRoot 'runtime'
$oldRuntime = Join-Path $InstallRoot ('.runtime-old-' + [guid]::NewGuid().ToString('N'))
$runtimeMoved = $false
$runtimeActivated = $false

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
    if ($runtimeSources.Count -lt 2) {
        throw 'The staged runtime is incomplete.'
    }
    foreach ($source in $runtimeSources) {
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
    Move-Item -LiteralPath $stageRuntime -Destination $runtimePath
    $runtimeActivated = $true
    Move-Item -LiteralPath $stagedManifest -Destination $manifestPath -Force

    if ($runtimeMoved -and (Test-Path -LiteralPath $oldRuntime -PathType Container)) {
        [void](Assert-PfiPathWithinRoot -CandidatePath $oldRuntime -AllowedRoot $InstallRoot)
        Remove-Item -LiteralPath $oldRuntime -Recurse -Force
        $runtimeMoved = $false
    }

    Write-SetupSummary -Inventory $inventory
    Write-Host ''
    Write-Host 'Installed paths'
    Write-Host '---------------'
    [pscustomobject][ordered]@{
        Runtime = $runtimePath
        Icons = $iconsPath
        Manifest = $manifestPath
        Registry = if ($SkipRegistry) { 'Skipped by request' } else { 'Registration is added in Phase 3' }
    } | Format-List | Out-Host
    exit 0
}
catch {
    [Console]::Error.WriteLine(('ERROR: {0}' -f $_.Exception.Message))
    if (-not $runtimeActivated -and $runtimeMoved -and
        (Test-Path -LiteralPath $oldRuntime -PathType Container) -and
        -not (Test-Path -LiteralPath $runtimePath)) {
        Move-Item -LiteralPath $oldRuntime -Destination $runtimePath
        $runtimeMoved = $false
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
