[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repoRoot 'scripts\Windows\PortableFolderIcons.Core.ps1')
. (Join-Path $repoRoot 'scripts\Windows\PortableFolderIcons.Integration.ps1')
. (Join-Path $repoRoot 'scripts\Windows\PortableFolderIcons.Actions.ps1')
. (Join-Path $repoRoot 'scripts\Windows\PortableFolderIcons.Maintenance.ps1')
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

function Assert-BatchRepositoryRootBoundary {
    param([string]$CheckoutPath, [string]$Name)

    [void](New-Item -ItemType Directory -Path $CheckoutPath -Force)
    $captureScript = Join-Path $CheckoutPath 'Capture-Root.ps1'
    $captureBatch = Join-Path $CheckoutPath 'Capture-Root.bat'
    $captureOutput = Join-Path $CheckoutPath 'captured.txt'
    $captureScriptText = @'
param([string]$RepositoryRoot, [string]$OutputPath)
[IO.File]::WriteAllText(
    $OutputPath,
    $RepositoryRoot,
    (New-Object Text.UTF8Encoding($false))
)
'@
    $captureBatchText = @'
@echo off
setlocal DisableDelayedExpansion
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -File "%~dp0Capture-Root.ps1" -RepositoryRoot "%~dp0." -OutputPath "%~dp0captured.txt"
endlocal
'@
    [IO.File]::WriteAllText($captureScript, $captureScriptText, (New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText($captureBatch, $captureBatchText, (New-Object Text.ASCIIEncoding))
    & $env:ComSpec /d /c ('"{0}"' -f $captureBatch) *> $null
    $captured = [IO.File]::ReadAllText($captureOutput)
    Assert-Equal ([IO.Path]::GetFullPath($CheckoutPath)) ([IO.Path]::GetFullPath($captured)) $Name
}

function Get-TestRegistrySnapshot {
    param([string[]]$Roots)

    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($root in @($Roots | Sort-Object)) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        $keys = @((Get-Item -LiteralPath $root)) +
            @(Get-ChildItem -LiteralPath $root -Recurse)
        foreach ($key in @($keys | Sort-Object Name)) {
            $lines.Add('KEY=' + $key.Name)
            foreach ($valueName in @($key.GetValueNames() | Sort-Object)) {
                $lines.Add(('{0}={1}' -f $valueName, [string]$key.GetValue($valueName)))
            }
        }
    }
    return ($lines -join "`n")
}

function New-TestExplorerWindow {
    param([string]$LocationUrl, [long]$WindowHandle = 0)

    $window = [pscustomobject]@{
        LocationURL = $LocationUrl
        HWND = $WindowHandle
        Busy = $false
        Navigated = $false
        NavigatedUrl = ''
        NavigationHistory = New-Object System.Collections.Generic.List[string]
    }
    $window | Add-Member -MemberType ScriptMethod -Name Navigate2 -Value {
        param($Url)
        $this.Navigated = $true
        $this.NavigatedUrl = [string]$Url
        $this.NavigationHistory.Add([string]$Url)
        $this.LocationURL = [string]$Url
    }
    return $window
}

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('PfiTests-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $testRoot)
$registryTestBase = $null
$registryTestSubcommands = $null
$registryTestIconChoices = $null
try {
    $configPath = Join-Path $repoRoot 'config.toml'
    Assert-Equal $false (Read-PfiDeveloperModeConfig $configPath) 'Developer Mode defaults to false'
    foreach ($case in @(
        @{ Text = "[settings]`r`ndeveloper_mode = true`r`n"; Expected = $true; Name = 'strictly parses true' },
        @{ Text = "[settings]`r`ndeveloper_mode = false # normal`r`n"; Expected = $false; Name = 'strictly parses false' }
    )) {
        $casePath = Join-Path $testRoot (($case.Name -replace '\W', '-') + '.toml')
        [IO.File]::WriteAllText($casePath, $case.Text)
        Assert-Equal $case.Expected (Read-PfiDeveloperModeConfig $casePath) $case.Name
    }
    foreach ($case in @(
        "[settings]`r`ndeveloper_mode =`r`n",
        "[settings]`r`ndeveloper_mode = yes`r`n",
        "[settings]`r`ndeveloper_mode = False`r`n",
        "[settings]`r`ndeveloper_mode = false`r`ndeveloper_mode = true`r`n",
        "[project]`r`nname = `"missing setting`"`r`n"
    )) {
        $badPath = Join-Path $testRoot ('bad-' + [guid]::NewGuid().ToString('N') + '.toml')
        [IO.File]::WriteAllText($badPath, $case)
        Assert-Throws { Read-PfiDeveloperModeConfig $badPath } 'rejects malformed, missing, or duplicate Developer Mode setting'
    }

    Assert-Equal 'Blue' (ConvertTo-PfiMenuLabel 'Folder_Blue.ico') 'normalizes Folder_ prefix'
    Assert-Equal 'Work Projects' (ConvertTo-PfiMenuLabel 'Work__Projects.ico') 'normalizes underscores and whitespace'
    Assert-Equal 'MiXeD' (ConvertTo-PfiMenuLabel 'folder-MiXeD.ICO') 'preserves capitalization'
    Assert-Throws { ConvertTo-PfiMenuLabel 'Folder_.ico' } 'rejects empty label'

    $actualAcceptancePath = 'C:\Users\ematthew\Portable-User-Installs\Portable-Folder-Icons'
    Assert-Equal $actualAcceptancePath ([IO.Path]::GetFullPath($actualAcceptancePath + '\.')) 'actual acceptance path canonicalizes unchanged'
    Assert-BatchRepositoryRootBoundary (Join-Path $testRoot 'Checkout With Spaces') 'batch preserves checkout path containing spaces'
    Assert-BatchRepositoryRootBoundary (Join-Path $testRoot 'Checkout üñîçødé') 'batch preserves Unicode checkout path'
    Assert-Throws {
        [IO.Path]::GetFullPath($actualAcceptancePath + '"')
    } 'exact malformed trailing quote is rejected'
    $launcherText = Get-Content -LiteralPath (Join-Path $repoRoot 'Setup_and_Run-Portable-Folder-Icons.bat') -Raw
    Assert-True ($launcherText.Contains('-RepositoryRoot "%~dp0."')) 'launcher protects trailing batch directory separator'
    Assert-Equal $false ($launcherText.Contains('-RepositoryRoot "%~dp0"')) 'launcher does not use quote-escaping trailing separator pattern'

    $validIcon = Join-Path $repoRoot 'files\ICO-Files\Folder_Blue.ico'
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
    Assert-Equal '0.1.1' $roundTrip.productVersion 'manifest round trip'
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
    Assert-Equal "[ViewState]`r`nFolderType=Generic`r`n" (
        Reset-PfiDesktopIniIconContent "[.ShellClassInfo]`r`nIconResource=x,0`r`n[ViewState]`r`nFolderType=Generic`r`n"
    ) 'reset removes empty shell section before another section'
    Assert-Equal $reset (Reset-PfiDesktopIniIconContent $reset) 'reset is idempotent'

    $installRoot = Join-Path $testRoot 'stable install ünicode'
    $installer = Join-Path $repoRoot 'scripts\Windows\Install-PortableFolderIcons.ps1'
    $windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    & $windowsPowerShell -NoLogo -NoProfile -ExecutionPolicy Bypass -File $installer `
        -RepositoryRoot $repoRoot -InstallRoot $installRoot -SkipRegistry *> $null
    Assert-Equal 0 $LASTEXITCODE 'installer succeeds in path with spaces and Unicode'
    $installedSettings = Read-PfiInstalledSettings (Join-Path $installRoot 'settings.json')
    Assert-Equal $false $installedSettings.developerMode 'setup persists normal mode in installed settings'
    $installedManifest = Read-PfiManifest (Join-Path $installRoot 'manifest.json')
    $acceptedEntries = @($installedManifest.entries | Where-Object validationState -eq 'Accepted')
    $acceptedCount = $acceptedEntries.Count
    Assert-True ($acceptedCount -ge 1) 'installer imports every currently accepted ICO without a fixed inventory size'
    $cachedBefore = @(Get-ChildItem -LiteralPath (Join-Path $installRoot 'icons') -Filter '*.ico').Count
    & $windowsPowerShell -NoLogo -NoProfile -ExecutionPolicy Bypass -File $installer `
        -RepositoryRoot $repoRoot -InstallRoot $installRoot -SkipRegistry *> $null
    Assert-Equal 0 $LASTEXITCODE 'installer rerun is idempotent'
    Assert-Equal $cachedBefore @(Get-ChildItem -LiteralPath (Join-Path $installRoot 'icons') -Filter '*.ico').Count 'installer preserves hash cache on rerun'
    $configurationRepo = Join-Path $testRoot 'Configuration Checkout (ü)%!'
    [void](New-Item -ItemType Directory -Path (Join-Path $configurationRepo 'scripts\Windows') -Force)
    [void](New-Item -ItemType Directory -Path (Join-Path $configurationRepo 'files\ICO-Files') -Force)
    Copy-Item -Path (Join-Path $repoRoot 'scripts\Windows\*.ps1') `
        -Destination (Join-Path $configurationRepo 'scripts\Windows')
    Copy-Item -Path (Join-Path $repoRoot 'scripts\Windows\*.vbs') `
        -Destination (Join-Path $configurationRepo 'scripts\Windows')
    Copy-Item -Path (Join-Path $repoRoot 'files\ICO-Files\*.ico') `
        -Destination (Join-Path $configurationRepo 'files\ICO-Files')
    [IO.File]::WriteAllText(
        (Join-Path $configurationRepo 'config.toml'),
        "[settings]`r`ndeveloper_mode = true`r`n"
    )
    & $windowsPowerShell -NoLogo -NoProfile -ExecutionPolicy Bypass -File $installer `
        -RepositoryRoot $configurationRepo -InstallRoot $installRoot -SkipRegistry *> $null
    Assert-Equal 0 $LASTEXITCODE 'setup rerun accepts changed Developer Mode'
    Assert-Equal $true (Read-PfiInstalledSettings (Join-Path $installRoot 'settings.json')).developerMode `
        'setup rerun updates effective installed setting'
    $settingRepair = Invoke-PfiRepair -InstallRoot $installRoot -SkipRegistry
    Assert-Equal $true $settingRepair.DeveloperMode 'Repair preserves and reuses installed Developer Mode'
    [IO.File]::WriteAllText(
        (Join-Path $configurationRepo 'config.toml'),
        "[settings]`r`ndeveloper_mode = false`r`n"
    )
    & $windowsPowerShell -NoLogo -NoProfile -ExecutionPolicy Bypass -File $installer `
        -RepositoryRoot $configurationRepo -InstallRoot $installRoot -SkipRegistry *> $null
    Assert-Equal $false (Read-PfiInstalledSettings (Join-Path $installRoot 'settings.json')).developerMode `
        'setup rerun can return installed setting to normal mode'

    $commandInstallRoot = 'C:\Users\Test User\Local & Data (β)%!'
    $registryRoot = 'HKCU:\Software\PortableFolderIcons\Tests\DryRun'
    $subcommandsReference = 'PortableFolderIcons.Tests.DryRunSubcommands'
    $subcommandsRoot = 'HKCU:\Software\Classes\' + $subcommandsReference
    $iconChoicesReference = $subcommandsReference + '.IconChoices'
    $iconChoicesRoot = 'HKCU:\Software\Classes\' + $iconChoicesReference
    $registryPlan = @(Get-PfiRegistryPlan -Manifest $installedManifest `
        -InstallRoot $commandInstallRoot -RegistryRoot $registryRoot `
        -SubcommandsRoot $subcommandsRoot -SubcommandsReference $subcommandsReference `
        -IconChoicesRoot $iconChoicesRoot -IconChoicesReference $iconChoicesReference `
        -PowerShellPath 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe')
    Assert-Equal $acceptedCount @($registryPlan | Where-Object {
        $_.Path.StartsWith((Join-Path $iconChoicesRoot 'shell'), [StringComparison]::OrdinalIgnoreCase) -and
        $_.Name -eq 'MUIVerb'
    }).Count 'registry plan contains one icon verb per accepted ICO'
    $iconLabels = @($registryPlan | Where-Object {
        $_.Name -eq 'MUIVerb' -and
        $_.Path.StartsWith((Join-Path $iconChoicesRoot 'shell'), [StringComparison]::OrdinalIgnoreCase)
    } | Select-Object -ExpandProperty Value)
    $expectedLabels = @($acceptedEntries | Sort-Object menuLabel | Select-Object -ExpandProperty menuLabel)
    Assert-Equal ($expectedLabels -join ',') ($iconLabels -join ',') 'registry icon verbs are alphabetic'
    Assert-Equal 'Single' ($registryPlan | Where-Object Name -eq 'MultiSelectModel').Value 'registry enforces single selection'
    Assert-Equal $subcommandsReference (
        $registryPlan | Where-Object { $_.Path -eq $registryRoot -and $_.Name -eq 'ExtendedSubCommandsKey' }
    ).Value 'parent references the separate submenu store'
    $chooserPath = Join-Path (Join-Path $subcommandsRoot 'shell') 'Choice_0100_Icons'
    Assert-Equal 'Choose Folder Icon' ($registryPlan | Where-Object {
        $_.Path -eq $chooserPath -and $_.Name -eq 'MUIVerb'
    }).Value 'parent menu contains one icon chooser'
    Assert-Equal $iconChoicesReference ($registryPlan | Where-Object {
        $_.Path -eq $chooserPath -and $_.Name -eq 'ExtendedSubCommandsKey'
    }).Value 'icon chooser references separate scalable icon storage'
    Assert-Equal 0 @($registryPlan | Where-Object {
        $_.Path -eq (Join-Path $registryRoot 'command')
    }).Count 'parent has no executable command'
    Assert-Equal 0 @($registryPlan | Where-Object {
        $_.Path.StartsWith((Join-Path $registryRoot 'ExtendedSubCommandsKey'), [StringComparison]::OrdinalIgnoreCase)
    }).Count 'ExtendedSubCommandsKey is a value rather than a child key'
    Assert-Equal $acceptedCount @($registryPlan | Where-Object {
        $_.Path.StartsWith((Join-Path $iconChoicesRoot 'shell\Icon_'), [StringComparison]::OrdinalIgnoreCase) -and
        $_.Name -eq 'MUIVerb'
    }).Count 'every accepted ICO has exactly one stored submenu action'
    Assert-Equal 0 @($registryPlan | Where-Object {
        $_.Path.StartsWith((Join-Path $subcommandsRoot 'shell\Icon_'), [StringComparison]::OrdinalIgnoreCase)
    }).Count 'utility parent contains no direct icon actions'
    foreach ($utilityLabel in @('Reset to Default', 'Repair Portable Folder Icons', 'Uninstall Portable Folder Icons')) {
        Assert-Equal 1 @($registryPlan | Where-Object {
            $_.Name -eq 'MUIVerb' -and $_.Value -eq $utilityLabel -and
            $_.Path.StartsWith((Join-Path $subcommandsRoot 'shell'), [StringComparison]::OrdinalIgnoreCase)
        }).Count ("utility remains in short parent menu: {0}" -f $utilityLabel)
    }
    $applyCommand = ($registryPlan | Where-Object {
        $_.Name -eq '' -and $_.Value -match ' -Action Apply '
    } | Select-Object -First 1).Value
    Assert-True ($applyCommand.Contains('"' + $commandInstallRoot + '\runtime\Invoke-PortableFolderIcons.Hidden.vbs"')) `
        'normal registry command quotes installed windowless launcher path'
    Assert-True ($applyCommand -match '(?i)^"[A-Z]:\\Windows\\System32\\wscript\.exe" ') `
        'normal Apply uses windowless Windows Script Host'
    Assert-True ($applyCommand.EndsWith(' -TargetPath "%1"')) 'registry passes target as a fixed argument'
    Assert-Equal $false ($applyCommand.Contains('powershell.exe')) 'normal Apply does not create a PowerShell console process directly'
    $normalResetCommand = ($registryPlan | Where-Object {
        $_.Name -eq '' -and $_.Value -match ' -Action Reset '
    }).Value
    Assert-True ($normalResetCommand.Contains('Invoke-PortableFolderIcons.Hidden.vbs')) `
        'normal Reset uses the windowless launcher'
    Assert-Equal $false ($normalResetCommand.Contains('powershell.exe')) `
        'normal Reset does not create a PowerShell console process directly'
    $developerPlan = @(Get-PfiRegistryPlan -Manifest $installedManifest `
        -InstallRoot $commandInstallRoot -RegistryRoot $registryRoot `
        -SubcommandsRoot $subcommandsRoot -SubcommandsReference $subcommandsReference `
        -IconChoicesRoot $iconChoicesRoot -IconChoicesReference $iconChoicesReference `
        -PowerShellPath 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' `
        -DeveloperMode $true)
    $developerApply = ($developerPlan | Where-Object {
        $_.Name -eq '' -and $_.Value -match ' -Action Apply '
    } | Select-Object -First 1).Value
    $developerReset = ($developerPlan | Where-Object {
        $_.Name -eq '' -and $_.Value -match ' -Action Reset '
    }).Value
    Assert-Equal $false ($developerApply.Contains('-WindowStyle Hidden')) 'Developer Mode keeps Apply PowerShell window visible'
    Assert-Equal $false ($developerReset.Contains('-WindowStyle Hidden')) 'Developer Mode keeps Reset PowerShell window visible'
    foreach ($utility in @('Repair', 'Uninstall')) {
        $utilityCommand = ($developerPlan | Where-Object {
            $_.Name -eq '' -and $_.Value -match (' -Action ' + $utility + '(?: |$)')
        }).Value
        Assert-True ($utilityCommand.Contains('-WindowStyle Hidden')) ($utility + ' command remains hidden and interactive dialogs remain available')
    }
    Assert-True (@($registryPlan | Where-Object { $_.Value -eq 'Repair Portable Folder Icons' }).Count -eq 1) 'registry includes Repair'
    Assert-True (@($registryPlan | Where-Object { $_.Value -eq 'Uninstall Portable Folder Icons' }).Count -eq 1) 'registry includes Uninstall'
    $installedRegistryPlan = @(Get-PfiRegistryPlan -Manifest $installedManifest -InstallRoot $installRoot `
        -RegistryRoot $registryRoot -SubcommandsRoot $subcommandsRoot `
        -SubcommandsReference $subcommandsReference -IconChoicesRoot $iconChoicesRoot `
        -IconChoicesReference $iconChoicesReference)
    $installedCommands = @($installedRegistryPlan | Where-Object Name -eq '' | Select-Object -ExpandProperty Value)
    Assert-Equal ($acceptedCount + 3) $installedCommands.Count 'icon and utility actions each have one command'
    Assert-Equal 2 @($installedCommands | Where-Object {
        $_.Contains('"' + (Join-Path (Join-Path $installRoot 'runtime') 'Invoke-PortableFolderIcons.ps1') + '"')
    }).Count 'Repair and Uninstall point directly to the installed dispatcher'
    Assert-Equal ($acceptedCount + 1) @($installedCommands | Where-Object {
        $_.Contains('"' + (Join-Path (Join-Path $installRoot 'runtime') 'Invoke-PortableFolderIcons.Hidden.vbs') + '"')
    }).Count 'normal Apply and Reset point to the installed windowless launcher'
    Assert-True (Test-Path -LiteralPath (Join-Path (Join-Path $installRoot 'runtime') 'Invoke-PortableFolderIcons.ps1') -PathType Leaf) 'installed action dispatcher exists'
    Assert-True (Test-Path -LiteralPath (Join-Path (Join-Path $installRoot 'runtime') 'Invoke-PortableFolderIcons.Hidden.vbs') -PathType Leaf) `
        'installed windowless launcher exists'
    Assert-Throws {
        Register-PfiContextMenu -Manifest $installedManifest -InstallRoot $installRoot `
            -RegistryRoot 'HKCU:\Software\Classes\Directory\shell\ForeignTool' `
            -IconChoicesRoot $iconChoicesRoot -IconChoicesReference $iconChoicesReference -WhatIf
    } 'registration rejects foreign HKCU subtree'
    $dryRun = @(Register-PfiContextMenu -Manifest $installedManifest -InstallRoot $installRoot `
        -RegistryRoot $registryRoot -SubcommandsRoot $subcommandsRoot `
        -SubcommandsReference $subcommandsReference -IconChoicesRoot $iconChoicesRoot `
        -IconChoicesReference $iconChoicesReference -DirectoryShellRoot $registryRoot -WhatIf)
    Assert-Equal $registryPlan.Count $dryRun.Count 'dry-run registration returns the complete disposable registry plan'

    foreach ($syntheticCount in @(0, 1, 10, 30, 50)) {
        $syntheticEntries = @()
        for ($syntheticIndex = $syntheticCount; $syntheticIndex -gt 0; $syntheticIndex--) {
            $syntheticHash = ('{0:x}' -f $syntheticIndex).PadLeft(64, '0')
            $syntheticEntries += [pscustomobject]@{
                menuLabel = ('Icon {0:D3}' -f $syntheticIndex)
                originalFilename = ('Icon_{0:D3}.ico' -f $syntheticIndex)
                hash = $syntheticHash
                cachedFilename = ($syntheticHash + '.ico')
                validationState = 'Accepted'
            }
        }
        $syntheticManifest = [pscustomobject]@{ entries = $syntheticEntries }
        $syntheticPlan = @(Get-PfiRegistryPlan -Manifest $syntheticManifest `
            -InstallRoot $commandInstallRoot -RegistryRoot $registryRoot `
            -SubcommandsRoot $subcommandsRoot -SubcommandsReference $subcommandsReference `
            -IconChoicesRoot $iconChoicesRoot -IconChoicesReference $iconChoicesReference)
        $syntheticIconVerbs = @($syntheticPlan | Where-Object {
            $_.Name -eq 'MUIVerb' -and
            $_.Path.StartsWith((Join-Path $iconChoicesRoot 'shell'), [StringComparison]::OrdinalIgnoreCase)
        })
        Assert-Equal $syntheticCount $syntheticIconVerbs.Count `
            ("scalable chooser contains exactly {0} icon action(s)" -f $syntheticCount)
        Assert-Equal $(if ($syntheticCount -eq 0) { 0 } else { 1 }) @($syntheticPlan | Where-Object {
            $_.Path -eq $chooserPath -and $_.Name -eq 'MUIVerb'
        }).Count ("chooser presence is correct for {0} icon(s)" -f $syntheticCount)
        Assert-Equal 3 @($syntheticPlan | Where-Object {
            $_.Name -eq 'MUIVerb' -and $_.Value -in @(
                'Reset to Default', 'Repair Portable Folder Icons', 'Uninstall Portable Folder Icons'
            ) -and $_.Path.StartsWith((Join-Path $subcommandsRoot 'shell'), [StringComparison]::OrdinalIgnoreCase)
        }).Count ("all utilities remain in parent for {0} icon(s)" -f $syntheticCount)
        $syntheticLabels = @($syntheticIconVerbs | Select-Object -ExpandProperty Value)
        Assert-Equal (($syntheticLabels | Sort-Object) -join ',') ($syntheticLabels -join ',') `
            ("icon ordering is deterministic for {0} icon(s)" -f $syntheticCount)
    }

    $registryTestBase = 'HKCU:\Software\PortableFolderIcons\Tests\Cascade-' + [guid]::NewGuid().ToString('N')
    $testDirectoryShell = Join-Path $registryTestBase 'DirectoryShell'
    $testParent = Join-Path $testDirectoryShell 'PortableFolderIcons'
    $testReference = 'PortableFolderIcons.Tests.' + [guid]::NewGuid().ToString('N')
    $testSubcommands = 'HKCU:\Software\Classes\' + $testReference
    $registryTestSubcommands = $testSubcommands
    $testIconChoicesReference = $testReference + '.IconChoices'
    $testIconChoices = 'HKCU:\Software\Classes\' + $testIconChoicesReference
    $registryTestIconChoices = $testIconChoices
    $unrelated = Join-Path $testDirectoryShell 'UnrelatedTool'
    [void](New-Item -Path (Join-Path $unrelated 'command') -Force)
    Set-Item -LiteralPath $unrelated -Value 'Keep this integration'
    Set-Item -LiteralPath (Join-Path $unrelated 'command') -Value '"C:\Tools\keep.exe" "%1"'
    foreach ($color in @('Black', 'Blue', 'Gray', 'Green', 'Orange', 'Pink', 'Purple', 'Red', 'Teal', 'Yellow')) {
        $legacy = Join-Path $testDirectoryShell ('FolderColor_' + $color)
        [void](New-Item -Path (Join-Path $legacy 'command') -Force)
        Set-Item -LiteralPath $legacy -Value ('Color: ' + $color)
        Set-Item -LiteralPath (Join-Path $legacy 'command') -Value (
            '"C:\Old\pwsh.exe" -File "C:\Old\Portable-Folder-Colours\SetFolderColor.ps1" ' +
            '-folderPath "%1" -iconPath "C:\Old\Portable-Folder-Colours\Folder_' + $color + '.ico,0"'
        )
    }
    $lookalike = Join-Path $testDirectoryShell 'FolderColor_Custom'
    [void](New-Item -Path (Join-Path $lookalike 'command') -Force)
    Set-Item -LiteralPath $lookalike -Value 'Color: Custom'
    Set-Item -LiteralPath (Join-Path $lookalike 'command') -Value '"C:\ThirdParty\color.exe" "%1"'
    Assert-Equal 10 @(Get-PfiRecognizedLegacyContextMenuPaths -DirectoryShellRoot $testDirectoryShell).Count 'all exact legacy prototype entries are recognized'

    [void](Register-PfiContextMenu -Manifest $installedManifest -InstallRoot $commandInstallRoot `
        -RegistryRoot $testParent -SubcommandsRoot $testSubcommands `
        -SubcommandsReference $testReference -IconChoicesRoot $testIconChoices `
        -IconChoicesReference $testIconChoicesReference -DirectoryShellRoot $testDirectoryShell)
    Assert-Equal $testReference ([string](Get-Item -LiteralPath $testParent).GetValue('ExtendedSubCommandsKey')) 'live parent has cascade reference'
    Assert-Equal $false (Test-Path -LiteralPath (Join-Path $testParent 'command')) 'live parent has no command handler'
    Assert-True (Test-Path -LiteralPath (Join-Path $testSubcommands 'shell')) 'referenced submenu storage exists'
    Assert-Equal $testSubcommands ('HKCU:\Software\Classes\' +
        [string](Get-Item -LiteralPath $testParent).GetValue('ExtendedSubCommandsKey')) 'submenu storage matches parent reference'
    Assert-Equal $acceptedCount @(Get-ChildItem -LiteralPath (Join-Path $testIconChoices 'shell') |
        Where-Object PSChildName -like 'Icon_*').Count 'isolated registry contains ten icon actions'
    Assert-Equal 0 @(Get-ChildItem -LiteralPath $testDirectoryShell |
        Where-Object PSChildName -like 'FolderColor_*' |
        Where-Object PSChildName -ne 'FolderColor_Custom').Count 'recognized legacy Color entries are removed'
    Assert-True (Test-Path -LiteralPath $unrelated) 'unrelated context-menu entry survives setup cleanup'
    Assert-True (Test-Path -LiteralPath $lookalike) 'unrecognized Color lookalike survives setup cleanup'

    $firstRegistryState = Get-TestRegistrySnapshot @($testParent, $testSubcommands, $testIconChoices, $testDirectoryShell)
    [void](Register-PfiContextMenu -Manifest $installedManifest -InstallRoot $commandInstallRoot `
        -RegistryRoot $testParent -SubcommandsRoot $testSubcommands `
        -SubcommandsReference $testReference -IconChoicesRoot $testIconChoices `
        -IconChoicesReference $testIconChoicesReference -DirectoryShellRoot $testDirectoryShell)
    $secondRegistryState = Get-TestRegistrySnapshot @($testParent, $testSubcommands, $testIconChoices, $testDirectoryShell)
    Assert-Equal $firstRegistryState $secondRegistryState 'repeated registration is idempotent'

    $reducedManifest = $installedManifest | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $removedEntry = @($reducedManifest.entries | Where-Object validationState -eq 'Accepted')[0]
    $reducedManifest.entries = @($reducedManifest.entries | Where-Object {
        $_.hash -ne $removedEntry.hash
    })
    [void](Register-PfiContextMenu -Manifest $reducedManifest -InstallRoot $commandInstallRoot `
        -RegistryRoot $testParent -SubcommandsRoot $testSubcommands `
        -SubcommandsReference $testReference -IconChoicesRoot $testIconChoices `
        -IconChoicesReference $testIconChoicesReference -DirectoryShellRoot $testDirectoryShell)
    Assert-Equal ($acceptedCount - 1) @(Get-ChildItem -LiteralPath (Join-Path $testIconChoices 'shell') |
        Where-Object PSChildName -like 'Icon_*').Count 'rescan removes obsolete submenu action'
    Assert-Equal 0 @(Get-ChildItem -LiteralPath (Join-Path $testIconChoices 'shell') |
        Where-Object PSChildName -match ([regex]::Escape([string]$removedEntry.hash))).Count 'removed ICO hash is absent from submenu'

    $legacyBlue = Join-Path $testDirectoryShell 'FolderColor_Blue'
    [void](New-Item -Path (Join-Path $legacyBlue 'command') -Force)
    Set-Item -LiteralPath $legacyBlue -Value 'Color: Blue'
    Set-Item -LiteralPath (Join-Path $legacyBlue 'command') -Value (
        '"C:\Old\pwsh.exe" -File "C:\Old\Portable-Folder-Colours\SetFolderColor.ps1" ' +
        '-folderPath "%1" -iconPath "C:\Old\Portable-Folder-Colours\Folder_Blue.ico,0"'
    )
    Remove-PfiContextMenu -RegistryRoot $testParent -SubcommandsRoot $testSubcommands `
        -IconChoicesRoot $testIconChoices -DirectoryShellRoot $testDirectoryShell -Confirm:$false
    Assert-Equal $false (Test-Path -LiteralPath $testParent) 'uninstall removes current parent menu'
    Assert-Equal $false (Test-Path -LiteralPath $testSubcommands) 'uninstall removes submenu storage'
    Assert-Equal $false (Test-Path -LiteralPath $testIconChoices) 'uninstall removes icon chooser storage'
    Assert-Equal $false (Test-Path -LiteralPath $legacyBlue) 'uninstall removes recognized legacy menu'
    Assert-True (Test-Path -LiteralPath $unrelated) 'unrelated context-menu entry survives uninstall'
    Assert-True (Test-Path -LiteralPath $lookalike) 'unrecognized Color lookalike survives uninstall'

    $actionFolder = Join-Path $testRoot 'Action Target (ü)'
    [void](New-Item -ItemType Directory -Path $actionFolder)
    $actionIni = Join-Path $actionFolder 'desktop.ini'
    [IO.File]::WriteAllText(
        $actionIni,
        "[.ShellClassInfo]`r`nInfoTip=Preserve this`r`n[ViewState]`r`nFolderType=Generic`r`n"
    )
    $actionEntry = @($installedManifest.entries | Where-Object validationState -eq 'Accepted')[0]
    $actionApply = Invoke-PfiApply -TargetPath @($actionFolder) -IconHash $actionEntry.hash `
        -InstallRoot $installRoot -SkipRefresh
    $afterApply = [IO.File]::ReadAllText($actionIni)
    Assert-True ($afterApply.Contains('InfoTip=Preserve this')) 'filesystem apply preserves unrelated desktop.ini key'
    Assert-True ($afterApply.Contains('[ViewState]')) 'filesystem apply preserves unrelated desktop.ini section'
    Assert-True (($afterApply -match 'IconResource=.*\\icons\\applied\\[a-f0-9]{64}-[a-f0-9]{32}\.ico,0')) 'filesystem apply uses unique per-application resource path'
    Assert-Equal $actionEntry.hash (Get-PfiSha256 $actionApply.IconResource) 'generated application resource preserves selected ICO content'
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

    $specialFolder = Join-Path $testRoot "Refresh % ! O'Brien & (üñîçødé)"
    [void](New-Item -ItemType Directory -Path $specialFolder)
    $specialOriginalAttributes = [IO.File]::GetAttributes($specialFolder) -bor
        [IO.FileAttributes]::NotContentIndexed
    [IO.File]::SetAttributes($specialFolder, $specialOriginalAttributes)
    $generatedTestRoot = Join-Path (Join-Path $installRoot 'icons') 'applied'
    [void](New-Item -ItemType Directory -Path $generatedTestRoot -Force)
    $unrelatedGeneratedResource = Join-Path $generatedTestRoot (
        ('f' * 64) + '-' + [guid]::NewGuid().ToString('N') + '.ico'
    )
    Copy-Item -LiteralPath $validIcon -Destination $unrelatedGeneratedResource
    $refreshOrder = New-Object System.Collections.Generic.List[string]
    $refreshBoundary = {
        param($ChangedFolder, $DesktopIniChange)
        $refreshOrder.Add($DesktopIniChange)
        $changedIni = Join-Path $ChangedFolder 'desktop.ini'
        Assert-True (Test-Path -LiteralPath $changedIni -PathType Leaf) 'desktop.ini exists before refresh boundary'
        Assert-True (([IO.File]::GetAttributes($changedIni) -band [IO.FileAttributes]::Hidden) -ne 0) 'desktop.ini is Hidden before refresh boundary'
        Assert-True (([IO.File]::GetAttributes($changedIni) -band [IO.FileAttributes]::System) -ne 0) 'desktop.ini is System before refresh boundary'
        Assert-True (([IO.File]::GetAttributes($ChangedFolder) -band [IO.FileAttributes]::ReadOnly) -ne 0) 'folder is ReadOnly before refresh boundary'
        return [pscustomobject]@{ RefreshSucceeded = $true }
    }
    $firstRefreshApply = Invoke-PfiApply -TargetPath @($specialFolder) `
        -IconHash $installedManifest.entries[0].hash -InstallRoot $installRoot `
        -RefreshAction $refreshBoundary
    Assert-Equal 'Create' $refreshOrder[0] 'initial apply refresh follows completed desktop.ini creation'
    Assert-Equal $true $firstRefreshApply.RefreshSucceeded 'initial apply reports successful refresh boundary'
    $firstAppliedResource = $firstRefreshApply.IconResource
    Assert-True (([IO.File]::GetAttributes($specialFolder) -band [IO.FileAttributes]::NotContentIndexed) -ne 0) 'apply preserves unrelated folder attributes'
    $specialIni = Join-Path $specialFolder 'desktop.ini'
    [IO.File]::SetAttributes(
        $specialIni,
        ([IO.File]::GetAttributes($specialIni) -bor [IO.FileAttributes]::NotContentIndexed)
    )

    $identityHandle = [IO.File]::Open(
        $specialIni,
        [IO.FileMode]::Open,
        [IO.FileAccess]::Read,
        [IO.FileShare]::ReadWrite
    )
    try {
        $secondRefreshApply = Invoke-PfiApply -TargetPath @($specialFolder) `
            -IconHash $installedManifest.entries[1].hash -InstallRoot $installRoot `
            -RefreshAction $refreshBoundary
    }
    finally {
        $identityHandle.Dispose()
    }
    Assert-Equal 'Update' $refreshOrder[1] 'different-icon apply refreshes an existing customization'
    Assert-Equal $true $secondRefreshApply.Applied 'existing desktop.ini is updated without replacing its open file identity'
    Assert-True (-not $secondRefreshApply.IconResource.Equals(
        $firstAppliedResource,
        [StringComparison]::OrdinalIgnoreCase
    )) 'different-icon apply receives a new resource identity'
    # Explorer can still be resolving the previous IconResource when the next
    # Apply lands. Deleting it there makes the folder fall back to the plain
    # default icon permanently, so the superseded resource must survive.
    Assert-True (Test-Path -LiteralPath $firstAppliedResource) 'superseded generated resource is retained for Explorer'
    Assert-Equal $firstAppliedResource $secondRefreshApply.SupersededIconResource 'apply reports the resource it superseded'
    Assert-True (Test-Path -LiteralPath $unrelatedGeneratedResource) 'generated-resource cleanup preserves unrelated folder resources'
    Assert-True (([IO.File]::ReadAllText((Join-Path $specialFolder 'desktop.ini'))).Contains(
        ($secondRefreshApply.IconResource + ',0')
    )) 'different-icon apply commits the new versioned resource before refresh'
    Assert-Equal ([string]$installedManifest.entries[1].hash) `
        (Get-PfiSha256 $secondRefreshApply.IconResource) `
        'different-icon generated resource contains the requested ICO'
    Assert-True (([IO.File]::GetAttributes($specialIni) -band [IO.FileAttributes]::NotContentIndexed) -ne 0) 'different-icon apply preserves unrelated desktop.ini attributes'

    $notificationLog = New-Object System.Collections.Generic.List[object]
    $notificationBoundary = {
        param($EventId, $Flags, $Path, $TargetKind)
        $notificationLog.Add([pscustomobject]@{
            EventId = [long]$EventId
            Flags = [uint32]$Flags
            Path = [string]$Path
            TargetKind = [string]$TargetKind
        })
    }
    $matchingWindow = New-TestExplorerWindow ((New-Object Uri(
        ([IO.Path]::GetFullPath((Split-Path -Parent $specialFolder)) + '\')
    )).AbsoluteUri) 101
    $otherWindow = New-TestExplorerWindow ((New-Object Uri(
        ([IO.Path]::GetFullPath($specialFolder) + '\')
    )).AbsoluteUri) 202
    $windowBoundary = { @($matchingWindow, $otherWindow) }
    $refreshResult = Send-PfiExplorerRefresh -FolderPath $specialFolder `
        -DesktopIniChange Update -NotificationAction $notificationBoundary `
        -ExplorerWindowsProvider $windowBoundary
    Assert-Equal 4 $refreshResult.NotificationsIssued 'refresh issues desktop.ini, folder, and parent notifications'
    Assert-Equal '8192,2048,8192,4096' (($notificationLog.EventId) -join ',') 'refresh uses update-item, attributes, update-item, and updated-dir events'
    Assert-Equal 'Pidl,Pidl,Pidl,Pidl' (($notificationLog.TargetKind) -join ',') 'existing refresh targets use canonical PIDLs'
    Assert-Equal '4096,4096,4096,4096' (($notificationLog.Flags) -join ',') 'PIDL notifications use synchronous flush'
    Assert-Equal ([IO.Path]::GetFullPath((Join-Path $specialFolder 'desktop.ini'))) $notificationLog[0].Path 'refresh targets desktop.ini'
    Assert-Equal ([IO.Path]::GetFullPath($specialFolder).TrimEnd('\')) $notificationLog[1].Path 'refresh targets customized folder attributes'
    Assert-Equal ([IO.Path]::GetFullPath((Split-Path -Parent $specialFolder)).TrimEnd('\')) $notificationLog[3].Path 'refresh targets parent directory'
    Assert-Equal $true $matchingWindow.Navigated 'Explorer view displaying parent is fully reloaded'
    Assert-Equal 2 $matchingWindow.NavigationHistory.Count 'full reload navigates the matched tab away and back'
    Assert-Equal $matchingWindow.LocationURL $matchingWindow.NavigatedUrl 'full reload returns to the parent location'
    Assert-Equal $false $otherWindow.Navigated 'Explorer view displaying customized folder is not reloaded'
    Assert-Equal 1 $refreshResult.MatchedExplorerWindows 'only the parent Explorer view is selected'
    Assert-Equal 101 $refreshResult.RefreshedWindowHandles[0] 'refresh result identifies the exact matched Explorer window'
    Assert-Equal 'NavigateAwayAndBack' $refreshResult.ViewRefreshMechanism 'refresh uses targeted away-and-back navigation'
    [PortableFolderIcons.NativeMethods]::ValidatePidl($specialFolder)
    Assert-Equal 0 ([PortableFolderIcons.NativeMethods]::OutstandingPidls) 'canonical PIDL allocation is released'

    $failedRefreshBoundary = {
        param($ChangedFolder, $DesktopIniChange)
        return [pscustomobject]@{
            RefreshSucceeded = $false
            Warnings = @('simulated refresh failure')
        }
    }
    $failedRefreshApply = Invoke-PfiApply -TargetPath @($specialFolder) `
        -IconHash $installedManifest.entries[2].hash -InstallRoot $installRoot `
        -RefreshAction $failedRefreshBoundary
    Assert-Equal $true $failedRefreshApply.Applied 'refresh failure does not report icon application failure'
    Assert-Equal $false $failedRefreshApply.RefreshSucceeded 'refresh failure is reported separately'

    $resetRefreshChanges = New-Object System.Collections.Generic.List[string]
    $resetRefreshBoundary = {
        param($ChangedFolder, $DesktopIniChange)
        $resetRefreshChanges.Add($DesktopIniChange)
        Assert-Equal $false (Test-Path -LiteralPath (Join-Path $ChangedFolder 'desktop.ini')) 'reset deletes owned-only desktop.ini before refresh'
        return [pscustomobject]@{ RefreshSucceeded = $true }
    }
    [void](Invoke-PfiReset -TargetPath @($specialFolder) -InstallRoot $installRoot `
        -RefreshAction $resetRefreshBoundary)
    Assert-Equal 'Delete' $resetRefreshChanges[0] 'reset uses equivalent deleted-desktop.ini refresh handling'
    Assert-Equal $false (Test-Path -LiteralPath $secondRefreshApply.IconResource) 'reset removes the selected folder owned generated resource'
    $notificationLog.Clear()
    [void](Send-PfiExplorerRefresh -FolderPath $specialFolder -DesktopIniChange Delete `
        -NotificationAction $notificationBoundary -ExplorerWindowsProvider { @() })
    Assert-Equal 'Path,Pidl,Pidl,Pidl' (($notificationLog.TargetKind) -join ',') 'deleted desktop.ini uses its former path while existing folder items use PIDLs'
    Assert-Equal 4101 $notificationLog[0].Flags 'deleted desktop.ini path notification uses Unicode synchronous flush'

    $postResetApply = Invoke-PfiApply -TargetPath @($specialFolder) `
        -IconHash $installedManifest.entries[3].hash -InstallRoot $installRoot `
        -RefreshAction $refreshBoundary
    Assert-True (([IO.File]::ReadAllText($specialIni)).Contains(
        ($postResetApply.IconResource + ',0')
    )) 'Apply A then Reset then Apply B stores B as current state'
    Assert-Equal ([string]$installedManifest.entries[3].hash) `
        (Get-PfiSha256 $postResetApply.IconResource) `
        'post-reset Apply resource contains B'
    $rapidFinalApply = Invoke-PfiApply -TargetPath @($specialFolder) `
        -IconHash $installedManifest.entries[4].hash -InstallRoot $installRoot `
        -RefreshAction $refreshBoundary
    Assert-True (([IO.File]::ReadAllText($specialIni)).Contains(
        ($rapidFinalApply.IconResource + ',0')
    )) 'multiple rapid colors leave the final requested icon current'
    $finalExpectedHash = [string]$installedManifest.entries[4].hash
    Assert-Equal $finalExpectedHash (Get-PfiSha256 $rapidFinalApply.IconResource) `
        'final rapid color resource contains cache content with the requested hash'
    Assert-Equal $true ($postResetApply.Applied -and $rapidFinalApply.Applied) 'post-reset and rapid sequential applies complete'

    # ---------------------------------------------------------------------
    # Explorer icon-staleness regressions.
    # These cover the defects found by measuring what Explorer actually paints:
    # premature deletion of a resource Explorer still resolves, refresh success
    # reported when nothing was reloaded, and a reload that strands the view.
    # ---------------------------------------------------------------------
    Assert-Equal 'C:\Icons\Blue.ico' (Get-PfiDesktopIniIconResourcePath "[.ShellClassInfo]`r`nIconResource=C:\Icons\Blue.ico,0`r`n") 'icon resource path is read back without its index'
    Assert-Equal 'C:\Icons\No Index.ico' (Get-PfiDesktopIniIconResourcePath "[.ShellClassInfo]`r`nIconResource=C:\Icons\No Index.ico`r`n") 'icon resource path without an index is read back intact'
    Assert-Equal '' (Get-PfiDesktopIniIconResourcePath "[.ShellClassInfo]`r`nInfoTip=None`r`n") 'absent icon resource reads back as empty'
    Assert-Equal '' (Get-PfiDesktopIniIconResourcePath '') 'empty desktop.ini reads back as empty'

    # Blue -> Red -> Reset -> Black, the required manual acceptance sequence,
    # asserting resource retention and identity at every step.
    $sequenceFolder = Join-Path $testRoot 'Sequence Target (üñî)'
    [void](New-Item -ItemType Directory -Path $sequenceFolder)
    $sequenceIni = Join-Path $sequenceFolder 'desktop.ini'
    $sequenceEntries = @($installedManifest.entries | Where-Object validationState -eq 'Accepted')
    $applyBlue = Invoke-PfiApply -TargetPath @($sequenceFolder) -IconHash $sequenceEntries[0].hash `
        -InstallRoot $installRoot -SkipRefresh
    Assert-Equal '' $applyBlue.SupersededIconResource 'first apply supersedes nothing'
    $applyRed = Invoke-PfiApply -TargetPath @($sequenceFolder) -IconHash $sequenceEntries[1].hash `
        -InstallRoot $installRoot -SkipRefresh
    Assert-True (Test-Path -LiteralPath $applyBlue.IconResource) 'sequential apply retains the immediately superseded resource'
    Assert-True (-not $applyRed.IconResource.Equals($applyBlue.IconResource, [StringComparison]::OrdinalIgnoreCase)) 'each apply produces a distinct resource identity'
    $applyGreen = Invoke-PfiApply -TargetPath @($sequenceFolder) -IconHash $sequenceEntries[2].hash `
        -InstallRoot $installRoot -SkipRefresh
    Assert-True (Test-Path -LiteralPath $applyRed.IconResource) 'third apply retains the second resource'
    # Explorer can lag several applies behind, so no generation is safe to
    # reclaim while the folder is still customized.
    Assert-True (Test-Path -LiteralPath $applyBlue.IconResource) 'resources more than one generation old are still retained'
    Assert-True (([IO.File]::ReadAllText($sequenceIni)).Contains($applyGreen.IconResource + ',0')) 'desktop.ini references the newest resource'
    $sequencePrefix = Get-PfiFolderResourcePrefix $sequenceFolder
    $unrelatedBeforeReset = Join-Path (Join-Path (Join-Path $installRoot 'icons') 'applied') (
        ('e' * 64) + '-' + [guid]::NewGuid().ToString('N') + '.ico'
    )
    Copy-Item -LiteralPath $validIcon -Destination $unrelatedBeforeReset
    [void](Invoke-PfiReset -TargetPath @($sequenceFolder) -InstallRoot $installRoot -SkipRefresh)
    # Reset is the point where reclaiming is safe: the customization is gone, so
    # no resource can still be referenced.
    Assert-Equal $false (Test-Path -LiteralPath $applyBlue.IconResource) 'reset reclaims the oldest resource owned by the folder'
    Assert-Equal $false (Test-Path -LiteralPath $applyRed.IconResource) 'reset reclaims intermediate resources owned by the folder'
    Assert-Equal $false (Test-Path -LiteralPath $applyGreen.IconResource) 'reset reclaims every resource owned by the folder'
    Assert-Equal 0 (@(Get-ChildItem -LiteralPath (Join-Path (Join-Path $installRoot 'icons') 'applied') -File -Filter ($sequencePrefix + '*.ico')).Count) 'reset leaves no resource owned by the folder'
    Assert-True (Test-Path -LiteralPath $unrelatedBeforeReset) 'reset preserves resources owned by other folders'
    Assert-Equal $false (Test-Path -LiteralPath $sequenceIni) 'reset removes the owned-only desktop.ini'
    $applyBlack = Invoke-PfiApply -TargetPath @($sequenceFolder) -IconHash $sequenceEntries[3].hash `
        -InstallRoot $installRoot -SkipRefresh
    Assert-True (([IO.File]::ReadAllText($sequenceIni)).Contains($applyBlack.IconResource + ',0')) 'apply after reset stores the newly requested icon'
    Assert-Equal ([string]$sequenceEntries[3].hash) (Get-PfiSha256 $applyBlack.IconResource) 'apply after reset writes the requested ICO content'
    Assert-True (([IO.File]::GetAttributes($sequenceFolder) -band [IO.FileAttributes]::ReadOnly) -ne 0) 'apply after reset restores the folder ReadOnly bit'

    # Canonical per-folder hashing keeps one folder's cleanup away from another's.
    $prefixA = Get-PfiFolderResourcePrefix 'C:\Parent\Child'
    Assert-Equal $prefixA (Get-PfiFolderResourcePrefix 'C:\Parent\Child\') 'resource prefix ignores a trailing separator'
    Assert-Equal $prefixA (Get-PfiFolderResourcePrefix 'C:\PARENT\CHILD') 'resource prefix is case canonical'
    Assert-Equal $prefixA (Get-PfiFolderResourcePrefix 'C:\Parent\Other\..\Child') 'resource prefix canonicalizes traversal'
    Assert-True (-not $prefixA.Equals((Get-PfiFolderResourcePrefix 'C:\Parent\Child2'), [StringComparison]::Ordinal)) 'distinct folders receive distinct resource prefixes'
    Assert-True ($prefixA -match '^[a-f0-9]{64}$') 'resource prefix is a full SHA-256 hex digest'

    # A refresh that matched a view but reloaded nothing must not report success.
    $strandedWindow = New-TestExplorerWindow ((New-Object Uri(
        ([IO.Path]::GetFullPath((Split-Path -Parent $sequenceFolder)) + '\')
    )).AbsoluteUri) 303
    $failingReload = { param($ExplorerWindow, $LocationUrl, $TemporaryLocationUrl, $ExpectedLocationPath, $TemporaryLocationPath)
        throw 'simulated reload failure' }
    $unreloadedRefresh = Send-PfiExplorerRefresh -FolderPath $sequenceFolder `
        -DesktopIniChange Update -NotificationAction { param($EventId, $Flags, $Path, $TargetKind) } `
        -ExplorerWindowsProvider { @($strandedWindow) } -FullViewRefreshAction $failingReload `
        -WarningAction SilentlyContinue
    Assert-Equal 1 $unreloadedRefresh.MatchedExplorerWindows 'the parent view is still matched when its reload fails'
    Assert-Equal 0 $unreloadedRefresh.RefreshedExplorerWindows 'a failed reload is not counted as refreshed'
    Assert-Equal $false $unreloadedRefresh.RefreshSucceeded 'refresh does not report success when a matched view was not reloaded'
    Assert-Equal $false $unreloadedRefresh.ViewReloadPerformed 'no view reload is reported when none completed'

    # With no view of the parent open there is nothing to reload; that is normal
    # and must still be distinguishable from having reloaded something.
    $noWindowRefresh = Send-PfiExplorerRefresh -FolderPath $sequenceFolder `
        -DesktopIniChange Update -NotificationAction { param($EventId, $Flags, $Path, $TargetKind) } `
        -ExplorerWindowsProvider { @() }
    Assert-Equal 0 $noWindowRefresh.MatchedExplorerWindows 'no matching view is reported when the parent is not open'
    Assert-Equal $true $noWindowRefresh.RefreshSucceeded 'notifications alone succeed when no view is open'
    Assert-Equal $false $noWindowRefresh.ViewReloadPerformed 'no view reload is claimed when the parent is not open'

    # The reload must leave the view at the original parent even when the
    # outbound navigation fails, otherwise the tab is stranded one level up.
    $strandTestWindow = New-TestExplorerWindow ((New-Object Uri(
        ([IO.Path]::GetFullPath((Split-Path -Parent $sequenceFolder)) + '\')
    )).AbsoluteUri) 404
    $expectedReturnUrl = $strandTestWindow.LocationURL
    $strandTestWindow | Add-Member -MemberType NoteProperty -Name OutboundAttempts -Value 0 -Force
    $strandTestWindow | Add-Member -MemberType ScriptMethod -Name Navigate2 -Force -Value {
        param($Url)
        $this.Navigated = $true
        $this.NavigatedUrl = [string]$Url
        $this.NavigationHistory.Add([string]$Url)
        $this.LocationURL = [string]$Url
        # Fail only the outbound leg, the way a real navigation can time out.
        if ($this.OutboundAttempts -eq 0) {
            $this.OutboundAttempts = 1
            throw 'simulated outbound navigation failure'
        }
    }
    $strandRefresh = $null
    try {
        $strandRefresh = Send-PfiExplorerRefresh -FolderPath $sequenceFolder `
            -DesktopIniChange Update -NotificationAction { param($EventId, $Flags, $Path, $TargetKind) } `
            -ExplorerWindowsProvider { @($strandTestWindow) } -WarningAction SilentlyContinue
    }
    catch { }
    Assert-Equal $expectedReturnUrl $strandTestWindow.LocationURL 'a failed outbound navigation still returns the view to the original parent'
    Assert-Equal $false $strandRefresh.RefreshSucceeded 'a reload that failed midway is reported as unsuccessful'

    # Repair must never delete generated resources: it cannot prove they are
    # unreferenced, and deleting a referenced one breaks the folder for good.
    $repairRetentionRoot = Join-Path (Join-Path $installRoot 'icons') 'applied'
    $repairRetentionBefore = @(Get-ChildItem -LiteralPath $repairRetentionRoot -File -Filter '*.ico').Count
    $repairRetention = Invoke-PfiRepair -InstallRoot $installRoot -SkipRegistry
    Assert-Equal $repairRetentionBefore (@(Get-ChildItem -LiteralPath $repairRetentionRoot -File -Filter '*.ico').Count) 'repair retains every generated resource'
    Assert-Equal $repairRetentionBefore $repairRetention.GeneratedResources 'repair reports the generated resource count it observed'

    # PIDL lifetime: the notification path must not leak across a full refresh.
    Assert-Equal 0 ([PortableFolderIcons.NativeMethods]::OutstandingPidls) 'no PIDL allocation is outstanding after refresh regressions'

    $dispatcherText = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\Windows\Invoke-PortableFolderIcons.ps1') -Raw
    Assert-True ($dispatcherText.IndexOf('$actionResult = Invoke-PfiApply') -lt
        $dispatcherText.IndexOf('[void][Windows.MessageBox]::Show(')) 'success dialog is ordered after Apply and refresh completion'
    Assert-True ($dispatcherText.Contains('but Explorer could not be refreshed automatically')) 'dispatcher distinguishes refresh warning from apply failure'
    # The dispatcher may report what it did; it may not assert what is on screen,
    # because nothing in the product verifies rendered pixels.
    Assert-True ($dispatcherText.Contains('Press F5, navigate away and back, or open a new Explorer window/view')) `
        'Developer Mode Apply completion states the accepted refresh workaround'
    Assert-Equal $false ($dispatcherText.Contains("'Apply completed successfully.'")) 'Apply completion does not claim unverified visual success'
    Assert-True ($dispatcherText.Contains('($null -eq $actionResult -or $actionResult.RefreshSucceeded)')) `
        'normal mode suppresses successful Apply and Reset completion MessageBox'
    Assert-True ($dispatcherText.IndexOf('if (-not $developerMode -and') -lt
        $dispatcherText.IndexOf('$completionMessage =')) 'normal-mode completion suppression precedes completion dialog construction'
    Assert-True ($dispatcherText.Contains('[Windows.MessageBoxImage]::Error')) 'error dialog remains available in normal mode'
    Assert-True ($dispatcherText.Contains('Read-PfiInstalledSettings')) 'dispatcher uses installed settings instead of repository config'

    # Constraints that must hold across the whole runtime.
    $runtimeSources = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'scripts\Windows') -File -Filter '*.ps1')
    foreach ($source in $runtimeSources) {
        $sourceText = Get-Content -LiteralPath $source.FullName -Raw
        Assert-Equal $false ($sourceText -match '(?i)Stop-Process\s+.*explorer') ('no Explorer process termination in ' + $source.Name)
        Assert-Equal $false ($sourceText -match '(?i)taskkill') ('no taskkill in ' + $source.Name)
        Assert-Equal $false ($sourceText -match '(?i)IconCache|thumbcache') ('no global icon-cache manipulation in ' + $source.Name)
        Assert-Equal $false ($sourceText -match '(?i)#Requires\s+-RunAsAdministrator') ('no elevation requirement in ' + $source.Name)
    }
    # The apply/reset/refresh path must never pace itself with a delay: it waits
    # on real conditions only. The uninstall cleanup helper is excluded because
    # its sleep is a bounded poll for the parent process to exit, which is a real
    # condition and cannot be expressed any other way from a detached process.
    foreach ($source in @($runtimeSources | Where-Object { $_.Name -ne 'Cleanup-PortableFolderIcons.ps1' })) {
        $sourceText = Get-Content -LiteralPath $source.FullName -Raw
        Assert-Equal $false ($sourceText -match '(?i)Start-Sleep') ('no fixed timing delay in ' + $source.Name)
    }
    $cleanupText = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\Windows\Cleanup-PortableFolderIcons.ps1') -Raw
    Assert-True ($cleanupText -match '(?s)for \(\$attempt.*?Get-Process -Id \$ParentProcessId.*?break') 'uninstall cleanup sleep is a bounded poll on parent process exit'
    $integrationText = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\Windows\PortableFolderIcons.Integration.ps1') -Raw
    Assert-True ($integrationText.Contains("if (`$Action -in @('Apply', 'Reset') -and -not `$DeveloperMode)")) `
        'normal Apply and Reset route through the windowless launcher'
    $hiddenLauncherText = Get-Content -LiteralPath (
        Join-Path $repoRoot 'scripts\Windows\Invoke-PortableFolderIcons.Hidden.vbs'
    ) -Raw
    Assert-True ($hiddenLauncherText.Contains('shell.Run(command, 0, True)')) `
        'windowless launcher uses hidden window style and waits for completion'
    Assert-True ($hiddenLauncherText.Contains('EncodeUtf16Hex(targetPath)')) `
        'windowless launcher transports shell-sensitive Unicode targets as hex'

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

    $repairResult = Invoke-PfiRepair -InstallRoot $installRoot -SkipRegistry
    Assert-Equal $acceptedCount $repairResult.ValidatedIcons 'repair validates all installed cached icons'
    Assert-Equal $false $repairResult.ImportedRepositoryIcons 'repair never claims repository import'

    $manifestBeforeConflict = [IO.File]::ReadAllText((Join-Path $installRoot 'manifest.json'))
    Write-PfiInstalledSettings (New-PfiInstalledSettings -DeveloperMode $true) (Join-Path $installRoot 'settings.json')
    $corruptCachePath = Join-Path (Join-Path $installRoot 'icons') $actionEntry.cachedFilename
    [IO.File]::WriteAllText($corruptCachePath, 'corrupt')
    $integrityFolder = Join-Path $testRoot 'Integrity Target'
    [void](New-Item -ItemType Directory -Path $integrityFolder)
    Assert-Throws {
        Invoke-PfiApply -TargetPath @($integrityFolder) -IconHash $actionEntry.hash `
            -InstallRoot $installRoot -SkipRefresh
    } 'apply rejects cached ICO with wrong hash'
    Assert-Equal $false (Test-Path -LiteralPath (Join-Path $integrityFolder 'desktop.ini')) 'hash failure leaves target unchanged'
    Assert-Throws { Invoke-PfiRepair -InstallRoot $installRoot -SkipRegistry } 'repair reports corrupt installed cache'
    $savedPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & $windowsPowerShell -NoLogo -NoProfile -ExecutionPolicy Bypass -File $installer `
        -RepositoryRoot $repoRoot -InstallRoot $installRoot -SkipRegistry *> $null
    $conflictExit = $LASTEXITCODE
    $ErrorActionPreference = $savedPreference
    Assert-True ($conflictExit -ne 0) 'setup fails safely on hash-filename cache conflict'
    Assert-Equal $manifestBeforeConflict ([IO.File]::ReadAllText((Join-Path $installRoot 'manifest.json'))) 'cache conflict preserves active manifest'
    Assert-Equal $true (Read-PfiInstalledSettings (Join-Path $installRoot 'settings.json')).developerMode `
        'failed setup preserves previous installed setting'

    $duplicateIniFolder = Join-Path $testRoot 'Duplicate Shell Sections'
    [void](New-Item -ItemType Directory -Path $duplicateIniFolder)
    [IO.File]::WriteAllText(
        (Join-Path $duplicateIniFolder 'desktop.ini'),
        "[.ShellClassInfo]`r`nInfoTip=One`r`n[.shellclassinfo]`r`nInfoTip=Two`r`n"
    )
    Assert-Throws {
        Invoke-PfiReset -TargetPath @($duplicateIniFolder) -SkipRefresh
    } 'reset rejects duplicate shell sections instead of partially editing'

    # Recreate a clean cache in a second test-owned root for uninstall behavior.
    $uninstallRoot = Join-Path $testRoot 'stable install ünicode'
    Remove-Item -LiteralPath $uninstallRoot -Recurse -Force
    & $windowsPowerShell -NoLogo -NoProfile -ExecutionPolicy Bypass -File $installer `
        -RepositoryRoot $repoRoot -InstallRoot $uninstallRoot -SkipRegistry *> $null
    $uninstallIconCount = @(Get-ChildItem -LiteralPath (Join-Path $uninstallRoot 'icons') -Filter '*.ico').Count
    $uninstallResult = Invoke-PfiUninstall -InstallRoot $uninstallRoot -Confirmed -SkipRegistry
    Assert-Equal $true $uninstallResult.CachePreserved 'uninstall preserves cache by default'
    Assert-Equal $false (Test-Path -LiteralPath (Join-Path $uninstallRoot 'runtime')) 'uninstall removes runtime'
    Assert-Equal $false (Test-Path -LiteralPath (Join-Path $uninstallRoot 'manifest.json')) 'uninstall removes active manifest'
    Assert-Equal $false (Test-Path -LiteralPath (Join-Path $uninstallRoot 'settings.json')) 'uninstall removes installed settings'
    Assert-Equal $uninstallIconCount @(Get-ChildItem -LiteralPath (Join-Path $uninstallRoot 'icons') -Filter '*.ico').Count 'uninstall leaves cached icons intact'
    [void](Invoke-PfiUninstall -InstallRoot $uninstallRoot -Confirmed -SkipRegistry)
    Assert-True (Test-Path -LiteralPath (Join-Path $uninstallRoot 'icons')) 'second uninstall is safe'

    & $windowsPowerShell -NoLogo -NoProfile -ExecutionPolicy Bypass -File $installer `
        -RepositoryRoot $repoRoot -InstallRoot $uninstallRoot -SkipRegistry *> $null
    [void](Invoke-PfiUninstall -InstallRoot $uninstallRoot -Confirmed -PurgeCache -SkipRegistry)
    Assert-Equal $false (Test-Path -LiteralPath (Join-Path $uninstallRoot 'icons')) 'explicit purge removes cache'
}
finally {
    if ($null -ne $registryTestIconChoices -and (Test-Path -LiteralPath $registryTestIconChoices)) {
        Remove-Item -LiteralPath $registryTestIconChoices -Recurse -Force
    }
    if ($null -ne $registryTestSubcommands -and (Test-Path -LiteralPath $registryTestSubcommands)) {
        Remove-Item -LiteralPath $registryTestSubcommands -Recurse -Force
    }
    if ($null -ne $registryTestBase -and (Test-Path -LiteralPath $registryTestBase)) {
        Remove-Item -LiteralPath $registryTestBase -Recurse -Force
    }
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}

Write-Host ('Tests: {0} passed, {1} failed' -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
exit 0
