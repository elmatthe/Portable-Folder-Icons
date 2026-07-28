[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repoRoot 'scripts\Windows\PortableFolderIcons.Core.ps1')
. (Join-Path $repoRoot 'scripts\Windows\PortableFolderIcons.Integration.ps1')
. (Join-Path $repoRoot 'scripts\Windows\PortableFolderIcons.Actions.ps1')
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

    $installRoot = Join-Path $testRoot 'stable install ünicode'
    $installer = Join-Path $repoRoot 'scripts\Windows\Install-PortableFolderIcons.ps1'
    $windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    & $windowsPowerShell -NoLogo -NoProfile -ExecutionPolicy Bypass -File $installer `
        -RepositoryRoot $repoRoot -InstallRoot $installRoot -SkipRegistry *> $null
    Assert-Equal 0 $LASTEXITCODE 'installer succeeds in path with spaces and Unicode'
    $installedManifest = Read-PfiManifest (Join-Path $installRoot 'manifest.json')
    Assert-Equal 10 @($installedManifest.entries | Where-Object validationState -eq 'Accepted').Count 'installer imports ten valid ICOs'
    $cachedBefore = @(Get-ChildItem -LiteralPath (Join-Path $installRoot 'icons') -Filter '*.ico').Count
    & $windowsPowerShell -NoLogo -NoProfile -ExecutionPolicy Bypass -File $installer `
        -RepositoryRoot $repoRoot -InstallRoot $installRoot -SkipRegistry *> $null
    Assert-Equal 0 $LASTEXITCODE 'installer rerun is idempotent'
    Assert-Equal $cachedBefore @(Get-ChildItem -LiteralPath (Join-Path $installRoot 'icons') -Filter '*.ico').Count 'installer preserves hash cache on rerun'

    $commandInstallRoot = 'C:\Users\Test User\Local & Data (β)%!'
    $registryRoot = 'HKCU:\Software\PortableFolderIcons\Tests\DryRun'
    $registryPlan = @(Get-PfiRegistryPlan -Manifest $installedManifest `
        -InstallRoot $commandInstallRoot -RegistryRoot $registryRoot `
        -PowerShellPath 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe')
    Assert-Equal 10 @($registryPlan | Where-Object { $_.Name -eq 'MUIVerb' -and $_.Value -in @(
        'Black', 'Blue', 'Gray', 'Green', 'Orange', 'Pink', 'Purple', 'Red', 'Teal', 'Yellow'
    ) }).Count 'registry plan contains ten icon verbs'
    $iconLabels = @($registryPlan | Where-Object {
        $_.Name -eq 'MUIVerb' -and $_.Value -notlike '*Portable*' -and $_.Value -ne 'Folder Icons' -and $_.Value -ne 'Reset to Default'
    } | Select-Object -ExpandProperty Value)
    Assert-Equal 'Black,Blue,Gray,Green,Orange,Pink,Purple,Red,Teal,Yellow' ($iconLabels -join ',') 'registry icon verbs are alphabetic'
    Assert-Equal 'Single' ($registryPlan | Where-Object Name -eq 'MultiSelectModel').Value 'registry enforces single selection'
    $applyCommand = ($registryPlan | Where-Object {
        $_.Name -eq '' -and $_.Value -match ' -Action Apply '
    } | Select-Object -First 1).Value
    Assert-True ($applyCommand.Contains('"' + $commandInstallRoot + '\runtime\Invoke-PortableFolderIcons.ps1"')) 'registry command quotes stable runtime path'
    Assert-True ($applyCommand.EndsWith(' -TargetPath "%1"')) 'registry passes target as a fixed argument'
    Assert-Equal $false ($applyCommand.Contains('-Command')) 'registry never interpolates target into PowerShell code'
    Assert-True (@($registryPlan | Where-Object { $_.Value -eq 'Repair Portable Folder Icons' }).Count -eq 1) 'registry includes Repair'
    Assert-True (@($registryPlan | Where-Object { $_.Value -eq 'Uninstall Portable Folder Icons' }).Count -eq 1) 'registry includes Uninstall'
    Assert-Throws {
        Register-PfiContextMenu -Manifest $installedManifest -InstallRoot $installRoot `
            -RegistryRoot 'HKCU:\Software\Classes\Directory\shell\ForeignTool' -WhatIf
    } 'registration rejects foreign HKCU subtree'
    $dryRun = @(Register-PfiContextMenu -Manifest $installedManifest -InstallRoot $installRoot `
        -RegistryRoot $registryRoot -WhatIf)
    Assert-Equal $registryPlan.Count $dryRun.Count 'dry-run registration returns the complete disposable registry plan'

    $actionFolder = Join-Path $testRoot 'Action Target (ü)'
    [void](New-Item -ItemType Directory -Path $actionFolder)
    $actionIni = Join-Path $actionFolder 'desktop.ini'
    [IO.File]::WriteAllText(
        $actionIni,
        "[.ShellClassInfo]`r`nInfoTip=Preserve this`r`n[ViewState]`r`nFolderType=Generic`r`n"
    )
    $actionEntry = @($installedManifest.entries | Where-Object validationState -eq 'Accepted')[0]
    [void](Invoke-PfiApply -TargetPath @($actionFolder) -IconHash $actionEntry.hash `
        -InstallRoot $installRoot -SkipRefresh)
    $afterApply = [IO.File]::ReadAllText($actionIni)
    Assert-True ($afterApply.Contains('InfoTip=Preserve this')) 'filesystem apply preserves unrelated desktop.ini key'
    Assert-True ($afterApply.Contains('[ViewState]')) 'filesystem apply preserves unrelated desktop.ini section'
    Assert-True (($afterApply -match 'IconResource=.*\\icons\\[a-f0-9]{64}\.ico,0')) 'filesystem apply uses stable cached hash path'
    $iniBytes = [IO.File]::ReadAllBytes($actionIni)
    Assert-True ($iniBytes.Length -ge 2 -and $iniBytes[0] -eq 0xFF -and $iniBytes[1] -eq 0xFE) 'filesystem apply writes UTF-16LE BOM'
    Assert-True (([IO.File]::GetAttributes($actionIni) -band [IO.FileAttributes]::Hidden) -ne 0) 'filesystem apply sets desktop.ini Hidden'
    Assert-True (([IO.File]::GetAttributes($actionIni) -band [IO.FileAttributes]::System) -ne 0) 'filesystem apply sets desktop.ini System'
    Assert-True (([IO.File]::GetAttributes($actionFolder) -band [IO.FileAttributes]::ReadOnly) -ne 0) 'filesystem apply sets only required folder ReadOnly bit'

    [void](Invoke-PfiReset -TargetPath @($actionFolder) -SkipRefresh)
    $afterReset = [IO.File]::ReadAllText($actionIni)
    Assert-True ($afterReset.Contains('InfoTip=Preserve this')) 'filesystem reset preserves unrelated desktop.ini key'
    Assert-True ($afterReset.Contains('[ViewState]')) 'filesystem reset preserves unrelated desktop.ini section'
    Assert-Equal $false ($afterReset.Contains('IconResource=')) 'filesystem reset removes icon customization'
    [void](Invoke-PfiReset -TargetPath @($actionFolder) -SkipRefresh)
    Assert-True (Test-Path -LiteralPath $actionIni) 'filesystem reset is idempotent with unrelated content'

    $emptyFolder = Join-Path $testRoot 'Empty Reset'
    [void](New-Item -ItemType Directory -Path $emptyFolder)
    [void](Invoke-PfiApply -TargetPath @($emptyFolder) -IconHash $actionEntry.hash `
        -InstallRoot $installRoot -SkipRefresh)
    [void](Invoke-PfiReset -TargetPath @($emptyFolder) -SkipRefresh)
    Assert-Equal $false (Test-Path -LiteralPath (Join-Path $emptyFolder 'desktop.ini')) 'reset deletes desktop.ini only when otherwise empty'

    $malformedFolder = Join-Path $testRoot 'Malformed Existing Ini'
    [void](New-Item -ItemType Directory -Path $malformedFolder)
    $malformedIni = Join-Path $malformedFolder 'desktop.ini'
    [IO.File]::WriteAllText($malformedIni, "[broken`r`nKeep=This")
    Assert-Throws {
        Invoke-PfiApply -TargetPath @($malformedFolder) -IconHash $actionEntry.hash `
            -InstallRoot $installRoot -SkipRefresh
    } 'apply rejects malformed existing desktop.ini'
    Assert-Equal "[broken`r`nKeep=This" ([IO.File]::ReadAllText($malformedIni)) 'malformed desktop.ini remains unchanged'

    $corruptCachePath = Join-Path (Join-Path $installRoot 'icons') $actionEntry.cachedFilename
    [IO.File]::WriteAllText($corruptCachePath, 'corrupt')
    $integrityFolder = Join-Path $testRoot 'Integrity Target'
    [void](New-Item -ItemType Directory -Path $integrityFolder)
    Assert-Throws {
        Invoke-PfiApply -TargetPath @($integrityFolder) -IconHash $actionEntry.hash `
            -InstallRoot $installRoot -SkipRefresh
    } 'apply rejects cached ICO with wrong hash'
    Assert-Equal $false (Test-Path -LiteralPath (Join-Path $integrityFolder 'desktop.ini')) 'hash failure leaves target unchanged'
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}

Write-Host ('Tests: {0} passed, {1} failed' -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
exit 0
