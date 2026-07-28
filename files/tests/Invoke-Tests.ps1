[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repoRoot 'scripts\Windows\PortableFolderIcons.Core.ps1')
Add-Type -AssemblyName System.Drawing

$script:Passed = 0
$script:Failed = 0

function Assert-Equal {
    param($Expected, $Actual, [string]$Name)
    if ($Expected -ceq $Actual) {
        $script:Passed++
        Write-Host ("  [PASS] {0}" -f $Name) -ForegroundColor Green
    }
    else {
        $script:Failed++
        Write-Host ("  [FAIL] {0}: expected <{1}> actual <{2}>" -f $Name, $Expected, $Actual) -ForegroundColor Red
    }
}

function Assert-True {
    param([bool]$Value, [string]$Name)
    Assert-Equal -Expected $true -Actual $Value -Name $Name
}

function Assert-Throws {
    param([scriptblock]$Action, [string]$Name)
    try {
        & $Action
        $script:Failed++
        Write-Host ("  [FAIL] {0}: expected an exception" -f $Name) -ForegroundColor Red
    }
    catch {
        $script:Passed++
        Write-Host ("  [PASS] {0}" -f $Name) -ForegroundColor Green
    }
}

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('PfiTests-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $testRoot)
try {
    Assert-Equal 'Blue' (ConvertTo-PfiMenuLabel 'Folder_Blue.ico') 'normalizes Folder_ prefix'
    Assert-Equal 'Work Projects' (ConvertTo-PfiMenuLabel 'Work__Projects.ico') 'normalizes underscores and whitespace'
    Assert-Equal 'MiXeD' (ConvertTo-PfiMenuLabel 'folder-MiXeD.ICO') 'preserves capitalization'
    Assert-Throws { ConvertTo-PfiMenuLabel 'Folder_.ico' } 'rejects empty label'

    $validIcon = Join-Path $repoRoot 'files\ICO-FIles\Folder_Blue.ico'
    $validResult = Test-PfiIcoFile $validIcon
    Assert-True $validResult.IsValid 'accepts valid ICO through .NET'
    Assert-Equal 64 $validResult.Hash.Length 'returns full SHA-256'

    $zero = Join-Path $testRoot 'zero.ico'
    [IO.File]::WriteAllBytes($zero, [byte[]]@())
    Assert-Equal $false (Test-PfiIcoFile $zero).IsValid 'rejects zero-byte ICO'
    $malformed = Join-Path $testRoot 'malformed.ico'
    [IO.File]::WriteAllText($malformed, 'not an icon')
    Assert-Equal $false (Test-PfiIcoFile $malformed).IsValid 'rejects malformed ICO'

    $locked = Join-Path $testRoot 'locked.ico'
    Copy-Item -LiteralPath $validIcon -Destination $locked
    $lockStream = [IO.File]::Open($locked, 'Open', 'ReadWrite', 'None')
    try { Assert-Equal $false (Test-PfiIcoFile $locked).IsValid 'rejects unreadable ICO' }
    finally { $lockStream.Dispose() }

    $source = Join-Path $testRoot 'source'
    $cache = Join-Path $testRoot 'cache'
    [void](New-Item -ItemType Directory -Path $source)
    [void](New-Item -ItemType Directory -Path $cache)
    Copy-Item $validIcon (Join-Path $source 'Folder_Blue.ico')
    Copy-Item $validIcon (Join-Path $source 'Blue.ico')
    $collisions = @(Get-PfiIconInventory $source $cache)
    Assert-Equal 2 @($collisions | Where-Object Status -eq 'Rejected').Count 'rejects both duplicate labels'

    Remove-Item (Join-Path $source 'Blue.ico')
    $inventory = @(Get-PfiIconInventory $source $cache)
    Assert-Equal 'Copy' $inventory[0].CacheAction 'plans deterministic cache copy'
    Copy-Item $validIcon (Join-Path $cache $inventory[0].CachedFile)
    $inventory = @(Get-PfiIconInventory $source $cache)
    Assert-Equal 'Reuse' $inventory[0].CacheAction 'reuses identical cached content'

    $manifestPath = Join-Path $testRoot 'manifest.json'
    $manifest = New-PfiManifest $inventory ([datetime]'2026-07-28T12:00:00Z')
    Write-PfiManifest $manifest $manifestPath
    $roundTrip = Read-PfiManifest $manifestPath
    Assert-Equal '0.1.0' $roundTrip.productVersion 'manifest round trip'
    [IO.File]::WriteAllText($manifestPath, '{bad')
    Assert-Throws { Read-PfiManifest $manifestPath } 'rejects corrupt manifest'

    $child = Join-Path $testRoot 'child'
    Assert-Equal ([IO.Path]::GetFullPath($child)) (Assert-PfiPathWithinRoot $child $testRoot) 'allows cleanup child'
    Assert-Throws { Assert-PfiPathWithinRoot $testRoot $testRoot } 'rejects cleanup root by default'
    Assert-Throws { Assert-PfiPathWithinRoot (Join-Path (Split-Path $testRoot -Parent) 'other') $testRoot } 'rejects outside cleanup path'

    $ownedRegistry = 'HKCU:\Software\Classes\Directory\shell\PortableFolderIcons'
    Assert-Throws { Assert-PfiRegistryPath 'HKCU:\Software\Classes\Directory\shell\Other' $ownedRegistry } 'rejects foreign registry path'

    $folder = Join-Path $testRoot 'spaces ünicode'
    [void](New-Item -ItemType Directory -Path $folder)
    Assert-Equal $folder (Assert-PfiSingleTarget @($folder)) 'accepts one Unicode folder'
    Assert-Throws { Assert-PfiSingleTarget @($folder, $folder) } 'rejects multiple targets'
    Assert-Throws { Assert-PfiSingleTarget @((Join-Path $testRoot 'missing')) } 'rejects missing target'

    $existing = "[.ShellClassInfo]`r`nInfoTip=Keep me`r`nIconFile=old.ico`r`nIconIndex=2`r`n[ViewState]`r`nFolderType=Generic`r`n"
    $applied = Set-PfiDesktopIniIconContent $existing 'C:\Icons\stable.ico,0'
    Assert-True ($applied.Contains('InfoTip=Keep me')) 'apply preserves unrelated shell key'
    Assert-True ($applied.Contains('[ViewState]')) 'apply preserves unrelated section'
    Assert-True ($applied.Contains('IconResource=C:\Icons\stable.ico,0')) 'apply writes IconResource'
    Assert-Equal $false ($applied.Contains('IconFile=')) 'apply removes legacy icon keys'

    $reset = Reset-PfiDesktopIniIconContent $applied
    Assert-True ($reset.Contains('InfoTip=Keep me')) 'reset preserves unrelated shell key'
    Assert-True ($reset.Contains('[ViewState]')) 'reset preserves unrelated section'
    Assert-Equal $false ($reset.Contains('IconResource=')) 'reset removes owned icon key'
    Assert-Equal '' (Reset-PfiDesktopIniIconContent "[.ShellClassInfo]`r`nIconResource=x,0`r`n") 'reset removes empty shell section'
    Assert-Equal $reset (Reset-PfiDesktopIniIconContent $reset) 'reset is idempotent'
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}

Write-Host ('Tests: {0} passed, {1} failed' -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
exit 0
