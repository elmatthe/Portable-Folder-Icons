[CmdletBinding()]
param(
    # Explicitly authorize launching the compiled C# harness for this run (equivalent to
    # PFI_GATE_NATIVE_HARNESS=allow). By default the harness is built or reused but NOT launched,
    # because endpoint security blocks unclassified builds; the run then ends BLOCKED (exit 3), never PASS.
    [switch]$AllowNativeHarness,
    # Withhold the launch even when authorized (kept for existing callers).
    [switch]$SkipNativeHarness
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repoRoot 'scripts\Windows\PortableFolderIcons.Core.ps1')
. (Join-Path $repoRoot 'scripts\Windows\PortableFolderIcons.Selection.ps1')
. (Join-Path $repoRoot 'scripts\Windows\PortableFolderIcons.Integration.ps1')
. (Join-Path $repoRoot 'scripts\Windows\PortableFolderIcons.Actions.ps1')
. (Join-Path $repoRoot 'scripts\Windows\PortableFolderIcons.Maintenance.ps1')
. (Join-Path $PSScriptRoot 'NativeHarness.Common.ps1')
$nativeLaunchAuthorized = Test-PfiNativeLaunchAuthorized -Allow:$AllowNativeHarness -Skip:$SkipNativeHarness
Add-Type -AssemblyName System.Drawing

$script:Passed = 0
$script:Failed = 0
$script:Blocked = New-Object System.Collections.Generic.List[string]

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

function Write-TestSelectionPayload {
    param(
        [string]$InstallRoot,
        [string]$Action,
        [string[]]$Paths,
        [string]$IconHash,
        [datetime]$CreatedUtc = [DateTime]::UtcNow,
        [string]$Token = ([guid]::NewGuid().ToString('N'))
    )

    $payload = [ordered]@{
        schemaVersion = 1
        token = $Token
        createdUtc = $CreatedUtc.ToUniversalTime().ToString('o')
        action = $Action
    }
    if ($Action -ceq 'Apply') { $payload.iconHash = $IconHash }
    $payload.paths = [string[]]$Paths
    $bytes = (New-Object Text.UTF8Encoding($false)).GetBytes(
        ($payload | ConvertTo-Json -Depth 5 -Compress)
    )
    $path = Get-PfiSelectionPayloadPath $InstallRoot $Token
    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force)
    [IO.File]::WriteAllBytes($path, $bytes)
    return [pscustomobject]@{
        Token = $Token
        Hash = Get-PfiSha256Bytes $bytes
        Path = $path
    }
}

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('PfiTests-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $testRoot)
$registryTestBase = $null
$registryTestSubcommands = $null
$registryTestIconChoices = $null
$registryTestBrokerClsid = $null
try {
    $selectionSourceRoot = Join-Path $repoRoot 'scripts\Windows\SelectionHandler'
    $selectionBuildManifest = Read-PfiSelectionBrokerBuildManifest `
        (Join-Path $selectionSourceRoot 'SelectionBroker.build.json') `
        (Join-Path $selectionSourceRoot 'PortableFolderIcons.SelectionBroker.cs')
    $selectionPlatform = if ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' }
    $selectionArtifact = Join-Path $selectionSourceRoot `
        ('PortableFolderIcons.SelectionBroker.' + $selectionPlatform + '.exe')
    $selectionArtifactInfo = Test-PfiSelectionBrokerArtifact `
        $selectionArtifact $selectionBuildManifest $selectionPlatform
    Assert-Equal $selectionPlatform $selectionArtifactInfo.Platform 'selection broker architecture matches this Windows installation'
    Assert-Equal '0.1.1.0' $selectionArtifactInfo.AssemblyVersion 'selection broker assembly version is current'

    $brokerHarnessDirectory = Join-Path $testRoot 'broker-harness'
    [void](New-Item -ItemType Directory -Path $brokerHarnessDirectory)
    # Built once per set of build inputs and reused from the ignored gate cache, so the binary keeps one identity
    # (and one endpoint-security classification) while its inputs are unchanged. See NativeHarness.Common.ps1.
    $brokerHarnessCacheRoot = Get-PfiNativeHarnessCacheRoot -RepoRoot $repoRoot
    $brokerHarnessBuild = Get-PfiNativeHarnessBuild -Platform $selectionPlatform -BrokerAssembly $selectionArtifact `
        -HarnessSource (Join-Path $repoRoot 'files\tests\SelectionBrokerHarness.cs') -CacheRoot $brokerHarnessCacheRoot
    Write-Host ("  Harness build: {0} {1} cache={2} sha256={3} {4}" -f $selectionPlatform, $brokerHarnessBuild.Status,
        $(if ($brokerHarnessBuild.CacheHit) { 'hit' } elseif ($brokerHarnessBuild.Compiled) { 'miss' } else { 'none' }),
        $brokerHarnessBuild.Sha256, $brokerHarnessBuild.Executable)
    Assert-Equal 'READY' $brokerHarnessBuild.Status 'selection broker handler-level harness compiles with inbox .NET Framework (or its verified cached build is reused)'
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
    Copy-Item -LiteralPath (Join-Path $repoRoot 'scripts\Windows\SelectionHandler') `
        -Destination (Join-Path $configurationRepo 'scripts\Windows\SelectionHandler') -Recurse
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
    $dryRunBrokerClsid = 'HKCU:\Software\Classes\CLSID\{' + [guid]::NewGuid().ToString().ToUpperInvariant() + '}'
    $brokerHash = [string]$selectionArtifactInfo.Sha256
    $registryPlan = @(Get-PfiRegistryPlan -Manifest $installedManifest `
        -InstallRoot $commandInstallRoot -RegistryRoot $registryRoot `
        -SubcommandsRoot $subcommandsRoot -SubcommandsReference $subcommandsReference `
        -IconChoicesRoot $iconChoicesRoot -IconChoicesReference $iconChoicesReference `
        -SelectionBrokerClsidRoot $dryRunBrokerClsid -SelectionBrokerHash $brokerHash `
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
    Assert-Equal 'Player' ($registryPlan | Where-Object {
        $_.Path -eq $registryRoot -and $_.Name -eq 'MultiSelectModel'
    }).Value 'registry enables COM Player multi-selection'
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
        $_.Path.StartsWith((Join-Path $iconChoicesRoot 'shell\PortableFolderIcons.Apply.'), [StringComparison]::OrdinalIgnoreCase) -and
        $_.Name -eq 'MUIVerb'
    }).Count 'every accepted ICO has exactly one stored submenu action'
    Assert-Equal 0 @($registryPlan | Where-Object {
        $_.Path.StartsWith((Join-Path $subcommandsRoot 'shell\PortableFolderIcons.Apply.'), [StringComparison]::OrdinalIgnoreCase)
    }).Count 'utility parent contains no direct icon actions'
    foreach ($utilityLabel in @('Reset to Default', 'Repair Portable Folder Icons', 'Uninstall Portable Folder Icons')) {
        Assert-Equal 1 @($registryPlan | Where-Object {
            $_.Name -eq 'MUIVerb' -and $_.Value -eq $utilityLabel -and
            $_.Path.StartsWith((Join-Path $subcommandsRoot 'shell'), [StringComparison]::OrdinalIgnoreCase)
        }).Count ("utility remains in short parent menu: {0}" -f $utilityLabel)
    }
    $delegateValues = @($registryPlan | Where-Object Name -eq 'DelegateExecute')
    Assert-Equal ($acceptedCount + 1) $delegateValues.Count 'Apply and Reset each use one shared COM selection broker'
    Assert-Equal 1 @($delegateValues | Select-Object -ExpandProperty Value -Unique).Count `
        'all selection verbs use one deterministic CLSID'
    Assert-Equal $script:PfiSelectionBrokerClsid $delegateValues[0].Value `
        'selection verbs register the project-owned broker CLSID'
    Assert-Equal $acceptedCount @($registryPlan | Where-Object {
        $_.Name -eq 'PfiAction' -and $_.Value -eq 'Apply'
    }).Count 'every Apply verb carries immutable action identity'
    Assert-Equal $acceptedCount @($registryPlan | Where-Object {
        $_.Name -eq 'PfiIconHash' -and $_.Value -cmatch '^[a-f0-9]{64}$'
    }).Count 'every Apply verb carries a full manifest hash identity'
    Assert-Equal 0 @($registryPlan | Where-Object {
        $_.Path -match '(?i)PortableFolderIcons\.(Apply|Reset).*\\command$' -and
        [string]$_.Value -match '(?i)(%1|TargetPath|\.ico(?:,0)?$)'
    }).Count 'selection verbs pass neither paths nor arbitrary ICO locations on a command line'
    $developerPlan = @(Get-PfiRegistryPlan -Manifest $installedManifest `
        -InstallRoot $commandInstallRoot -RegistryRoot $registryRoot `
        -SubcommandsRoot $subcommandsRoot -SubcommandsReference $subcommandsReference `
        -IconChoicesRoot $iconChoicesRoot -IconChoicesReference $iconChoicesReference `
        -SelectionBrokerClsidRoot $dryRunBrokerClsid -SelectionBrokerHash $brokerHash `
        -PowerShellPath 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' `
        -DeveloperMode $true)
    Assert-Equal (($registryPlan | Where-Object Name -eq 'DelegateExecute').Value -join ',') `
        (($developerPlan | Where-Object Name -eq 'DelegateExecute').Value -join ',') `
        'Developer Mode does not change selection transport or action identity'
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
        -IconChoicesReference $iconChoicesReference `
        -SelectionBrokerClsidRoot $dryRunBrokerClsid -SelectionBrokerHash $brokerHash)
    $installedCommands = @($installedRegistryPlan | Where-Object {
        $_.Name -eq '' -and $_.Path -like '*\command'
    } | Select-Object -ExpandProperty Value)
    Assert-Equal 2 $installedCommands.Count 'only Repair and Uninstall retain static command lines'
    Assert-Equal 2 @($installedCommands | Where-Object {
        $_.Contains('"' + (Join-Path (Join-Path $installRoot 'runtime') 'Invoke-PortableFolderIcons.ps1') + '"')
    }).Count 'Repair and Uninstall point directly to the installed dispatcher'
    Assert-Equal ($acceptedCount + 1) @($installedRegistryPlan | Where-Object Name -eq 'DelegateExecute').Count `
        'Apply and Reset avoid legacy process-per-target command transport'
    Assert-True (Test-Path -LiteralPath (Join-Path (Join-Path $installRoot 'runtime') 'Invoke-PortableFolderIcons.ps1') -PathType Leaf) 'installed action dispatcher exists'
    Assert-True (Test-Path -LiteralPath (Join-Path (Join-Path $installRoot 'runtime') 'Invoke-PortableFolderIcons.Hidden.vbs') -PathType Leaf) `
        'installed windowless launcher exists'
    Assert-True (Test-Path -LiteralPath (Join-Path (Join-Path (Join-Path $installRoot 'runtime') 'SelectionHandler') 'PortableFolderIcons.SelectionBroker.exe') -PathType Leaf) `
        'installed selection broker exists independently of the repository'
    Assert-Throws {
        Register-PfiContextMenu -Manifest $installedManifest -InstallRoot $installRoot `
            -RegistryRoot 'HKCU:\Software\Classes\Directory\shell\ForeignTool' `
            -SubcommandsRoot $subcommandsRoot -SubcommandsReference $subcommandsReference `
            -IconChoicesRoot $iconChoicesRoot -IconChoicesReference $iconChoicesReference `
            -SelectionBrokerClsidRoot $dryRunBrokerClsid -WhatIf
    } 'registration rejects foreign HKCU subtree'
    $dryRun = @(Register-PfiContextMenu -Manifest $installedManifest -InstallRoot $installRoot `
        -RegistryRoot $registryRoot -SubcommandsRoot $subcommandsRoot `
        -SubcommandsReference $subcommandsReference -IconChoicesRoot $iconChoicesRoot `
        -IconChoicesReference $iconChoicesReference -SelectionBrokerClsidRoot $dryRunBrokerClsid `
        -DirectoryShellRoot $registryRoot -WhatIf)
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
            -IconChoicesRoot $iconChoicesRoot -IconChoicesReference $iconChoicesReference `
            -SelectionBrokerClsidRoot $dryRunBrokerClsid -SelectionBrokerHash $brokerHash)
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
    $testBrokerClsid = 'HKCU:\Software\Classes\CLSID\{' + [guid]::NewGuid().ToString().ToUpperInvariant() + '}'
    $registryTestBrokerClsid = $testBrokerClsid
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

    $foreignBrokerClsid = 'HKCU:\Software\Classes\CLSID\{' + [guid]::NewGuid().ToString().ToUpperInvariant() + '}'
    [void](New-Item -Path (Join-Path $foreignBrokerClsid 'LocalServer32') -Force)
    Set-Item -LiteralPath $foreignBrokerClsid -Value 'Unrelated COM server'
    Set-Item -LiteralPath (Join-Path $foreignBrokerClsid 'LocalServer32') -Value '"C:\Unrelated\server.exe"'
    Assert-Throws {
        Register-PfiContextMenu -Manifest $installedManifest -InstallRoot $installRoot `
            -RegistryRoot $testParent -SubcommandsRoot $testSubcommands `
            -SubcommandsReference $testReference -IconChoicesRoot $testIconChoices `
            -IconChoicesReference $testIconChoicesReference `
            -SelectionBrokerClsidRoot $foreignBrokerClsid -DirectoryShellRoot $testDirectoryShell
    } 'registration refuses a malicious or unrelated CLSID lookalike'
    Assert-Equal 'Unrelated COM server' ([string](Get-Item $foreignBrokerClsid).GetValue('')) `
        'failed ownership guard preserves unrelated CLSID state exactly'
    Remove-Item -LiteralPath $foreignBrokerClsid -Recurse -Force

    [void](Register-PfiContextMenu -Manifest $installedManifest -InstallRoot $installRoot `
        -RegistryRoot $testParent -SubcommandsRoot $testSubcommands `
        -SubcommandsReference $testReference -IconChoicesRoot $testIconChoices `
        -IconChoicesReference $testIconChoicesReference `
        -SelectionBrokerClsidRoot $testBrokerClsid -DirectoryShellRoot $testDirectoryShell)
    Assert-Equal $testReference ([string](Get-Item -LiteralPath $testParent).GetValue('ExtendedSubCommandsKey')) 'live parent has cascade reference'
    Assert-Equal $false (Test-Path -LiteralPath (Join-Path $testParent 'command')) 'live parent has no command handler'
    Assert-True (Test-Path -LiteralPath (Join-Path $testSubcommands 'shell')) 'referenced submenu storage exists'
    Assert-Equal $testSubcommands ('HKCU:\Software\Classes\' +
        [string](Get-Item -LiteralPath $testParent).GetValue('ExtendedSubCommandsKey')) 'submenu storage matches parent reference'
    Assert-Equal $acceptedCount @(Get-ChildItem -LiteralPath (Join-Path $testIconChoices 'shell') |
        Where-Object PSChildName -like 'PortableFolderIcons.Apply.*').Count 'isolated registry contains every icon action'
    Assert-True (Test-Path -LiteralPath (Join-Path $testBrokerClsid 'LocalServer32')) `
        'isolated registration contains the project-owned LocalServer32'
    Assert-Equal $script:PfiSelectionBrokerOwner ([string](Get-Item $testBrokerClsid).GetValue('PfiOwner')) `
        'isolated COM registration has the exact ownership marker'
    Assert-Equal 0 @(Get-ChildItem -LiteralPath $testDirectoryShell |
        Where-Object PSChildName -like 'FolderColor_*' |
        Where-Object PSChildName -ne 'FolderColor_Custom').Count 'recognized legacy Color entries are removed'
    Assert-True (Test-Path -LiteralPath $unrelated) 'unrelated context-menu entry survives setup cleanup'
    Assert-True (Test-Path -LiteralPath $lookalike) 'unrecognized Color lookalike survives setup cleanup'

    # Read actual isolated registration, not a second hardcoded list of names.
    $contracts = @()
    foreach ($verbRoot in @((Join-Path $testIconChoices 'shell'), (Join-Path $testSubcommands 'shell'))) {
        foreach ($verb in @(Get-ChildItem -LiteralPath $verbRoot)) {
            $verbAction = [string]$verb.GetValue('PfiAction')
            if ($verbAction -in @('Apply', 'Reset')) {
                $contracts += ($verb.PSChildName + "`t" + $verbAction + "`t" + [string]$verb.GetValue('PfiIconHash'))
            }
        }
    }
    $contractsPath = Join-Path $brokerHarnessDirectory 'registered-contracts.tsv'
    [IO.File]::WriteAllLines($contractsPath, [string[]]$contracts, (New-Object Text.UTF8Encoding($false)))
    $harnessName = 'actual Apply/Reset registration initializes the broker; selection occurrence/order and invalid identities are covered'
    if (-not $nativeLaunchAuthorized) {
        $script:Blocked.Add("BLOCKED_BY_ENDPOINT_SECURITY (withheld, not launched): $harnessName")
        Write-Host ("  [BLOCKED] withheld compiled harness launch (authorize with -AllowNativeHarness or PFI_GATE_NATIVE_HARNESS=allow): {0}" -f $harnessName) -ForegroundColor Yellow
    }
    elseif ($brokerHarnessBuild.Status -ne 'READY') {
        Assert-Equal 'PASS' $brokerHarnessBuild.Status ("{0} [harness unavailable: {1}]" -f $harnessName, $brokerHarnessBuild.Detail)
    }
    else {
        $harnessPermission = Get-PfiNativeLaunchPermission -CacheRoot $brokerHarnessCacheRoot -Sha256 $brokerHarnessBuild.Sha256
        if (-not $harnessPermission.Permitted) {
            $script:Blocked.Add("BLOCKED_BY_ENDPOINT_SECURITY (previously blocked, not re-attempted): $harnessName :: $($harnessPermission.Reason)")
            Write-Host ("  [BLOCKED] {0}" -f $harnessPermission.Reason) -ForegroundColor Yellow
        }
        else {
            $harnessLaunch = Invoke-PfiNativeProcess -FilePath $brokerHarnessBuild.Executable -ArgumentList @($contractsPath) `
                -WorkingDirectory $brokerHarnessBuild.Directory -TimeoutSeconds 300
            $harnessOutcome = Get-PfiNativeOutcome -Launch $harnessLaunch -PassPattern '(?m)^Selection broker harness: (?<count>\d+) passed'
            Add-PfiNativeLaunchRecord -CacheRoot $brokerHarnessCacheRoot -Record ([ordered]@{ platform = $selectionPlatform; mode = 'suite'
                sha256 = $brokerHarnessBuild.Sha256; fingerprint = $brokerHarnessBuild.Fingerprint; status = $harnessOutcome.Status
                exit = $(if ($harnessLaunch.Started) { [string]$harnessLaunch.ExitCode } else { 'not-started:' + $harnessLaunch.StartErrorCode })
                assertions = $harnessOutcome.Assertions; detail = $harnessOutcome.Detail })
            Write-Host $harnessLaunch.StdOut
            if ($harnessOutcome.Status -eq 'BLOCKED_BY_ENDPOINT_SECURITY') {
                # Launch refused by the OS: a security-policy block, not a harness verdict.
                $script:Blocked.Add("BLOCKED_BY_ENDPOINT_SECURITY (launch denied): $harnessName :: $($harnessOutcome.Detail)")
                Write-Host ("  [BLOCKED] compiled harness launch denied: {0}" -f $harnessOutcome.Detail) -ForegroundColor Yellow
            }
            elseif ($harnessOutcome.Status -eq 'BLOCKED') {
                $script:Blocked.Add("BLOCKED (harness not executed): $harnessName :: $($harnessOutcome.Detail)")
                Write-Host ("  [BLOCKED] compiled harness not executed: {0}" -f $harnessOutcome.Detail) -ForegroundColor Yellow
            }
            else {
                # PASS needs exit 0 and the harness's own pass line; FAIL and CRASH are reported with their cause.
                Assert-Equal 'PASS' $harnessOutcome.Status ("{0} [{1}]" -f $harnessName, $harnessOutcome.Detail)
            }
        }
    }

    $firstRegistryState = Get-TestRegistrySnapshot @($testParent, $testSubcommands, $testIconChoices, $testBrokerClsid, $testDirectoryShell)
    [void](Register-PfiContextMenu -Manifest $installedManifest -InstallRoot $installRoot `
        -RegistryRoot $testParent -SubcommandsRoot $testSubcommands `
        -SubcommandsReference $testReference -IconChoicesRoot $testIconChoices `
        -IconChoicesReference $testIconChoicesReference `
        -SelectionBrokerClsidRoot $testBrokerClsid -DirectoryShellRoot $testDirectoryShell)
    $secondRegistryState = Get-TestRegistrySnapshot @($testParent, $testSubcommands, $testIconChoices, $testBrokerClsid, $testDirectoryShell)
    Assert-Equal $firstRegistryState $secondRegistryState 'repeated registration is idempotent'

    $reducedManifest = $installedManifest | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $removedEntry = @($reducedManifest.entries | Where-Object validationState -eq 'Accepted')[0]
    $reducedManifest.entries = @($reducedManifest.entries | Where-Object {
        $_.hash -ne $removedEntry.hash
    })
    [void](Register-PfiContextMenu -Manifest $reducedManifest -InstallRoot $installRoot `
        -RegistryRoot $testParent -SubcommandsRoot $testSubcommands `
        -SubcommandsReference $testReference -IconChoicesRoot $testIconChoices `
        -IconChoicesReference $testIconChoicesReference `
        -SelectionBrokerClsidRoot $testBrokerClsid -DirectoryShellRoot $testDirectoryShell)
    Assert-Equal ($acceptedCount - 1) @(Get-ChildItem -LiteralPath (Join-Path $testIconChoices 'shell') |
        Where-Object PSChildName -like 'PortableFolderIcons.Apply.*').Count 'rescan removes obsolete submenu action'
    Assert-Equal 0 @(Get-ChildItem -LiteralPath (Join-Path $testIconChoices 'shell') |
        Where-Object { [string]$_.GetValue('PfiIconHash') -ceq [string]$removedEntry.hash }).Count `
        'removed ICO hash is absent from submenu properties'

    $legacyBlue = Join-Path $testDirectoryShell 'FolderColor_Blue'
    [void](New-Item -Path (Join-Path $legacyBlue 'command') -Force)
    Set-Item -LiteralPath $legacyBlue -Value 'Color: Blue'
    Set-Item -LiteralPath (Join-Path $legacyBlue 'command') -Value (
        '"C:\Old\pwsh.exe" -File "C:\Old\Portable-Folder-Colours\SetFolderColor.ps1" ' +
        '-folderPath "%1" -iconPath "C:\Old\Portable-Folder-Colours\Folder_Blue.ico,0"'
    )
    Remove-PfiContextMenu -InstallRoot $installRoot -RegistryRoot $testParent `
        -SubcommandsRoot $testSubcommands -IconChoicesRoot $testIconChoices `
        -SelectionBrokerClsidRoot $testBrokerClsid `
        -DirectoryShellRoot $testDirectoryShell -Confirm:$false
    Assert-Equal $false (Test-Path -LiteralPath $testParent) 'uninstall removes current parent menu'
    Assert-Equal $false (Test-Path -LiteralPath $testSubcommands) 'uninstall removes submenu storage'
    Assert-Equal $false (Test-Path -LiteralPath $testIconChoices) 'uninstall removes icon chooser storage'
    Assert-Equal $false (Test-Path -LiteralPath $testBrokerClsid) 'uninstall removes exact owned COM registration'
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

    $zeroBatch = Invoke-PfiBatchAction -Action Reset -TargetPath @() `
        -InstallRoot $installRoot -SkipRefresh
    Assert-Equal 0 $zeroBatch.SelectedCount 'zero-target batch is represented without inventing a target'
    Assert-Equal 0 $zeroBatch.AttemptedCount 'zero-target batch performs no operation'

    foreach ($selectionCount in @(1, 2, 10, 30, 100)) {
        $selectionFolders = New-Object System.Collections.Generic.List[string]
        foreach ($selectionIndex in 1..$selectionCount) {
            $selectionFolder = Join-Path $testRoot `
                ('Batch-{0:D3}-{1:D3}' -f $selectionCount, $selectionIndex)
            [void](New-Item -ItemType Directory -Path $selectionFolder)
            $selectionFolders.Add($selectionFolder)
        }
        $selectionResult = Invoke-PfiBatchAction -Action Reset `
            -TargetPath $selectionFolders.ToArray() -InstallRoot $installRoot -SkipRefresh
        Assert-Equal $selectionCount $selectionResult.SelectedCount `
            ("batch preserves selected count {0}" -f $selectionCount)
        Assert-Equal $selectionCount $selectionResult.SuccessCount `
            ("batch processes all {0} targets sequentially" -f $selectionCount)
        Assert-Equal (($selectionFolders.ToArray()) -join [char]30) `
            ((@($selectionResult.Results | Select-Object -ExpandProperty InputPath)) -join [char]30) `
            ("batch preserves occurrence/order for {0} targets" -f $selectionCount)
    }

    $specialBatchFolders = @(
        (Join-Path $testRoot 'Batch spaces'),
        (Join-Path $testRoot 'Batch üñîçødé'),
        (Join-Path $testRoot 'Batch & ampersand'),
        (Join-Path $testRoot "Batch O'Brien"),
        (Join-Path $testRoot 'Batch (parentheses)'),
        (Join-Path $testRoot 'Batch % percent'),
        (Join-Path $testRoot 'Batch ! exclamation')
    )
    foreach ($specialBatchFolder in $specialBatchFolders) {
        [void](New-Item -ItemType Directory -Path $specialBatchFolder)
    }
    $specialBatch = Invoke-PfiBatchAction -Action Apply -TargetPath $specialBatchFolders `
        -IconHash $actionEntry.hash -InstallRoot $installRoot -SkipRefresh
    Assert-Equal $specialBatchFolders.Count $specialBatch.SuccessCount `
        'multi-folder Apply supports shell-sensitive and Unicode paths'
    $repeatedSpecialBatch = Invoke-PfiBatchAction -Action Apply -TargetPath $specialBatchFolders `
        -IconHash $actionEntry.hash -InstallRoot $installRoot -SkipRefresh
    Assert-Equal $specialBatchFolders.Count $repeatedSpecialBatch.SuccessCount `
        'repeating the same multi-folder Apply action remains safe'
    $specialReset = Invoke-PfiBatchAction -Action Reset -TargetPath $specialBatchFolders `
        -InstallRoot $installRoot -SkipRefresh
    Assert-Equal $specialBatchFolders.Count $specialReset.SuccessCount `
        'multi-folder Reset supports the same shell-sensitive selection'
    $longFolder = Join-Path $testRoot (('Long Path Segment ' * 7).Trim() + '-ü')
    [void](New-Item -ItemType Directory -Path $longFolder)
    $lookalikeLatin = Join-Path $testRoot 'Lookalike o'
    $lookalikeGreek = Join-Path $testRoot ('Lookalike ' + [char]0x03BF)
    [void](New-Item -ItemType Directory -Path $lookalikeLatin)
    [void](New-Item -ItemType Directory -Path $lookalikeGreek)
    $identityBatch = Invoke-PfiBatchAction -Action Reset `
        -TargetPath @($longFolder, $lookalikeLatin, $lookalikeGreek) `
        -InstallRoot $installRoot -SkipRefresh
    Assert-Equal 3 $identityBatch.SuccessCount 'currently supported long and lookalike paths process independently'
    Assert-Equal ($longFolder + [char]30 + $lookalikeLatin + [char]30 + $lookalikeGreek) `
        (($identityBatch.Results.InputPath) -join [char]30) `
        'long and identical-looking distinct paths are not normalized into one target'

    $mixedFirst = Join-Path $testRoot 'Mixed First'
    $mixedLater = Join-Path $testRoot 'Mixed Later'
    [void](New-Item -ItemType Directory -Path $mixedFirst)
    [void](New-Item -ItemType Directory -Path $mixedLater)
    $missingMiddle = Join-Path $testRoot 'Mixed Missing'
    $mixedResult = Invoke-PfiBatchAction -Action Reset `
        -TargetPath @($mixedFirst, $missingMiddle, $mixedLater) `
        -InstallRoot $installRoot -SkipRefresh
    Assert-Equal 3 $mixedResult.SelectedCount 'mixed batch retains every supplied occurrence'
    Assert-Equal 2 $mixedResult.SuccessCount 'mixed batch continues to a valid later target'
    Assert-Equal 1 $mixedResult.RejectedCount 'mixed batch reports invalid target independently'
    Assert-Equal 'Succeeded,Rejected,Succeeded' (($mixedResult.Results.Status) -join ',') `
        'mixed batch preserves ordered per-target outcomes'

    $failureFolders = @(
        (Join-Path $testRoot 'Failure One'),
        (Join-Path $testRoot 'Failure Middle'),
        (Join-Path $testRoot 'Failure Later')
    )
    foreach ($failureFolder in $failureFolders) {
        [void](New-Item -ItemType Directory -Path $failureFolder)
    }
    [IO.File]::WriteAllText((Join-Path $failureFolders[1] 'desktop.ini'), "[broken`r`n")
    $middleFailure = Invoke-PfiBatchAction -Action Apply -TargetPath $failureFolders `
        -IconHash $actionEntry.hash -InstallRoot $installRoot -SkipRefresh -WarningAction SilentlyContinue
    Assert-Equal 'Succeeded,Failed,Succeeded' (($middleFailure.Results.Status) -join ',') `
        'one middle operation failure does not prevent a later Apply'
    Assert-Equal 2 $middleFailure.SuccessCount 'successful targets are not rolled back after another failure'
    Assert-True (Test-Path -LiteralPath (Join-Path $failureFolders[2] 'desktop.ini')) `
        'later target is actually customized after a middle failure'

    foreach ($failureFolder in @($failureFolders[0], $failureFolders[2])) {
        $failureIni = Join-Path $failureFolder 'desktop.ini'
        [IO.File]::SetAttributes($failureIni, [IO.FileAttributes]::Normal)
        [IO.File]::WriteAllText($failureIni, "[broken`r`n")
    }
    $allFailure = Invoke-PfiBatchAction -Action Apply -TargetPath $failureFolders `
        -IconHash $actionEntry.hash -InstallRoot $installRoot -SkipRefresh -WarningAction SilentlyContinue
    Assert-Equal 3 $allFailure.FailureCount 'all-target failure is aggregated after every attempt'
    Assert-Equal 3 $allFailure.AttemptedCount 'all failing targets are attempted sequentially'
    $allFailureText = Format-PfiAggregateResult $allFailure
    foreach ($failureFolder in $failureFolders) {
        Assert-True ($allFailureText.Contains($failureFolder)) `
            'aggregate result never silently hides a failed folder'
    }

    $payloadSpecialPaths = @($specialBatchFolders + $specialBatchFolders[1])
    $validPayloadInfo = Write-TestSelectionPayload $installRoot Apply $payloadSpecialPaths $actionEntry.hash
    $validPayload = Read-PfiSelectionPayload $installRoot $validPayloadInfo.Token $validPayloadInfo.Hash
    Assert-Equal ($payloadSpecialPaths -join [char]30) ($validPayload.Paths -join [char]30) `
        'payload round trip preserves Unicode, shell characters, order, and duplicate occurrence'
    Assert-Equal $actionEntry.hash $validPayload.IconHash 'payload round trip preserves manifest icon identity'
    Assert-True (Remove-PfiSelectionPayload $installRoot $validPayloadInfo.Token) `
        'consumed payload is removed from the exact owned request directory'
    Assert-Equal $false (Test-Path -LiteralPath $validPayloadInfo.Path) 'payload cleanup removes only the consumed file'

    Assert-Throws {
        Read-PfiSelectionPayload $installRoot ([guid]::NewGuid().ToString('N')) ('0' * 64)
    } 'missing payload is rejected safely'
    Assert-Throws {
        Read-PfiSelectionPayload $installRoot '../escape' ('0' * 64)
    } 'payload token cannot escape the owned request directory'

    $malformedToken = [guid]::NewGuid().ToString('N')
    $malformedPath = Get-PfiSelectionPayloadPath $installRoot $malformedToken
    [IO.File]::WriteAllText($malformedPath, '{bad json', (New-Object Text.UTF8Encoding($false)))
    $malformedBytes = [IO.File]::ReadAllBytes($malformedPath)
    Assert-Throws {
        Read-PfiSelectionPayload $installRoot $malformedToken (Get-PfiSha256Bytes $malformedBytes)
    } 'malformed payload is rejected without evaluation'

    $stalePayload = Write-TestSelectionPayload $installRoot Reset @($mixedFirst) '' `
        ([DateTime]::UtcNow.AddMinutes(-30))
    Assert-Throws {
        Read-PfiSelectionPayload $installRoot $stalePayload.Token $stalePayload.Hash
    } 'stale payload is rejected by a bounded age check'
    $invalidActionPayload = Write-TestSelectionPayload $installRoot Bogus @($mixedFirst) ''
    Assert-Throws {
        Read-PfiSelectionPayload $installRoot $invalidActionPayload.Token $invalidActionPayload.Hash
    } 'invalid payload action is rejected'
    $invalidHashPayload = Write-TestSelectionPayload $installRoot Apply @($mixedFirst) 'bad'
    Assert-Throws {
        Read-PfiSelectionPayload $installRoot $invalidHashPayload.Token $invalidHashPayload.Hash
    } 'invalid payload icon hash is rejected'
    $emptyPayload = Write-TestSelectionPayload -InstallRoot $installRoot -Action Reset `
        -Paths ([string[]]@()) -IconHash ''
    Assert-Throws {
        Read-PfiSelectionPayload $installRoot $emptyPayload.Token $emptyPayload.Hash
    } 'empty payload selection is rejected safely'
    $tamperedPayload = Write-TestSelectionPayload $installRoot Reset @($mixedFirst) ''
    [IO.File]::AppendAllText($tamperedPayload.Path, 'tamper')
    Assert-Throws {
        Read-PfiSelectionPayload $installRoot $tamperedPayload.Token $tamperedPayload.Hash
    } 'payload tampering is detected by the broker-supplied SHA-256'

    $concurrentA = Write-TestSelectionPayload $installRoot Reset @($mixedFirst, $mixedLater) ''
    $concurrentB = Write-TestSelectionPayload $installRoot Reset @($mixedLater, $mixedFirst) ''
    Assert-True ($concurrentA.Token -cne $concurrentB.Token) 'concurrent payload identities are collision-safe'
    Assert-Equal ($mixedFirst + [char]30 + $mixedLater) `
        ((Read-PfiSelectionPayload $installRoot $concurrentA.Token $concurrentA.Hash).Paths -join [char]30) `
        'first concurrent payload remains independent'
    Assert-Equal ($mixedLater + [char]30 + $mixedFirst) `
        ((Read-PfiSelectionPayload $installRoot $concurrentB.Token $concurrentB.Hash).Paths -join [char]30) `
        'second concurrent payload remains independent'

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
    $runtimeSources = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'scripts\Windows') -File -Filter '*.ps1' -Recurse)
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
    Assert-True ($integrationText.Contains("'DelegateExecute' `$script:PfiSelectionBrokerClsid")) `
        'Apply and Reset route through the shared COM selection broker'
    Assert-True ($integrationText.Contains("'MultiSelectModel' 'Player'")) `
        'selection verbs opt into the uncapped COM Player selection model'
    $hiddenLauncherText = Get-Content -LiteralPath (
        Join-Path $repoRoot 'scripts\Windows\Invoke-PortableFolderIcons.Hidden.vbs'
    ) -Raw
    Assert-True ($hiddenLauncherText.Contains('shell.Run(command, 0, True)')) `
        'windowless launcher uses hidden window style and waits for completion'
    Assert-True ($hiddenLauncherText.Contains('-SelectionToken')) `
        'windowless launcher supports the fixed-size selection payload token'
    Assert-True ($hiddenLauncherText.Contains('-PayloadHash')) `
        'windowless launcher authenticates the selection payload by SHA-256'
    Assert-True ($hiddenLauncherText.Contains('EncodeUtf16Hex(targetPath)')) `
        'windowless launcher retains backward-compatible single-target Unicode transport'

    $brokerSourceText = Get-Content -LiteralPath (
        Join-Path $repoRoot 'scripts\Windows\SelectionHandler\PortableFolderIcons.SelectionBroker.cs'
    ) -Raw
    foreach ($interfaceName in @('IExecuteCommand', 'IObjectWithSelection', 'IInitializeCommand', 'IShellItemArray')) {
        Assert-True ($brokerSourceText.Contains($interfaceName)) `
            ('selection broker implements the documented ' + $interfaceName + ' contract')
    }
    Assert-True ($brokerSourceText.Contains('Guid.NewGuid().ToString("N")')) `
        'every selection payload receives a collision-resistant invocation token'
    Assert-True ($brokerSourceText.Contains('DataContractJsonSerializer')) `
        'selection payload serialization is structured Unicode JSON rather than executable source'
    Assert-True ($brokerSourceText.Contains('SelectionTransport.ReadAll(new ShellSelectionPathSource(selection))')) `
        'the handler enumerates the entire supplied selection through its tested seam'
    Assert-Equal $false ($brokerSourceText.Contains('HKLM')) `
        'selection broker contains no machine-wide registry dependency'

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
    if ($null -ne $registryTestBrokerClsid -and (Test-Path -LiteralPath $registryTestBrokerClsid)) {
        Remove-Item -LiteralPath $registryTestBrokerClsid -Recurse -Force
    }
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

Write-Host ('Tests: {0} passed, {1} failed, {2} blocked' -f $script:Passed, $script:Failed, $script:Blocked.Count)
foreach ($blockedCheck in $script:Blocked) { Write-Host ('  BLOCKED: {0}' -f $blockedCheck) }
if ($script:Failed -gt 0) { exit 1 }
if ($script:Blocked.Count -gt 0) { exit 3 }
exit 0
