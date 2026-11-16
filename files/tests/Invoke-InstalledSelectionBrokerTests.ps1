[CmdletBinding()]
param()

# Opt-in developer smoke test. Requires a normal-mode repository setup first;
# never runs from verify.ps1 and never mutates non-fixture folder targets.
# It uses the live installation and launches the cached compiled harness, so it needs both opt-ins for one run:
# PFI_GATE_INSTALLED_COM=allow and PFI_GATE_NATIVE_HARNESS=allow. It reports one "PFI-NATIVE-RESULT" line.
# Exit: 0 PASS, 1 FAIL, 2 BLOCKED, 3 BLOCKED_BY_ENDPOINT_SECURITY, 4 NOT RUN, 5 CRASH.
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $PSScriptRoot 'NativeHarness.Common.ps1')
if ($env:PFI_GATE_INSTALLED_COM -ne 'allow') {
    Write-Host 'NOT RUN: set PFI_GATE_INSTALLED_COM=allow to exercise the live installation.'
    exit 4
}
if ($env:PFI_GATE_NATIVE_HARNESS -ne 'allow') {
    Write-Host 'BLOCKED_BY_ENDPOINT_SECURITY (withheld): this test launches the compiled harness; set PFI_GATE_NATIVE_HARNESS=allow after an authorized security decision.'
    exit 3
}
$installRoot = Join-Path $env:LOCALAPPDATA 'Portable-Folder-Icons'
. (Join-Path $repoRoot 'scripts\Windows\PortableFolderIcons.Core.ps1')
. (Join-Path $repoRoot 'scripts\Windows\PortableFolderIcons.Integration.ps1')
. (Join-Path $repoRoot 'scripts\Windows\PortableFolderIcons.Maintenance.ps1')
$fields = [ordered]@{ platform = ''; mode = 'installed'; status = 'FAIL'; exit = ''; sha256 = ''; cache = '' }
try {
    $installed = Test-PfiInstalledRuntime $installRoot
    if ($installed.Settings.developerMode) { throw 'The automated COM smoke test requires normal mode; Developer Mode UI needs manual acceptance.' }
    if (-not (Test-PfiSelectionBrokerRegistryOwnership $script:PfiProductionSelectionBrokerClsidRoot $installRoot)) {
        throw 'Installed COM registration ownership is invalid.'
    }
    $testRoot = Join-Path $repoRoot ('files\test-logs\installed-selection-' + [guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $testRoot)
    $platform = $installed.SelectionBroker.Platform
    $fields.platform = $platform
    # The harness references the installed broker itself; identical broker bytes share the repository's cached build.
    $cacheRoot = Get-PfiNativeHarnessCacheRoot -RepoRoot $repoRoot
    $build = Get-PfiNativeHarnessBuild -Platform $platform -HarnessSource (Join-Path $PSScriptRoot 'SelectionBrokerHarness.cs') -CacheRoot $cacheRoot `
        -BrokerAssembly (Join-Path $installRoot 'runtime\SelectionHandler\PortableFolderIcons.SelectionBroker.exe')
    $fields.sha256 = $build.Sha256
    $fields.cache = $(if ($build.CacheHit) { 'hit' } elseif ($build.Compiled) { 'miss' } else { 'none' })
    if ($build.Status -ne 'READY') {
        $fields.status = $build.Status
        Write-Host (Format-PfiNativeLine -Kind 'RESULT' -Fields $fields -Detail ('harness unavailable: ' + $build.Detail))
        exit $script:PfiNativeExitCodes[$build.Status]
    }
    $permission = Get-PfiNativeLaunchPermission -CacheRoot $cacheRoot -Sha256 $build.Sha256
    if (-not $permission.Permitted) {
        $fields.status = 'BLOCKED_BY_ENDPOINT_SECURITY'
        Write-Host (Format-PfiNativeLine -Kind 'RESULT' -Fields $fields -Detail $permission.Reason)
        exit 3
    }
    $folders = @((Join-Path $testRoot "First % ! & (ü) O'Brien"), (Join-Path $testRoot 'Second ü'))
    foreach ($folder in $folders) {
        [void](New-Item -ItemType Directory -Path $folder)
        [IO.File]::WriteAllText((Join-Path $folder 'desktop.ini'), "[.ShellClassInfo]`r`nInfoTip=Preserve this`r`n[ViewState]`r`nFolderType=Generic`r`n", [Text.Encoding]::Unicode)
    }
    $pathFile = Join-Path $testRoot 'paths.txt'
    [IO.File]::WriteAllLines($pathFile, [string[]]$folders, (New-Object Text.UTF8Encoding($false)))
    $apply = Get-ChildItem -LiteralPath (Join-Path $script:PfiProductionIconChoicesRoot 'shell') | Where-Object {
        [string]$_.GetValue('PfiAction') -ceq 'Apply'
    } | Select-Object -First 1
    $reset = Get-ChildItem -LiteralPath (Join-Path $script:PfiProductionSubcommandsRoot 'shell') | Where-Object {
        [string]$_.GetValue('PfiAction') -ceq 'Reset'
    } | Select-Object -First 1
    if ($null -eq $apply -or $null -eq $reset) { throw 'Installed Apply/Reset registration is missing.' }
    $passed = 0
    $requestsRoot = Join-Path $installRoot 'state\requests'
    $requestsBefore = @(Get-ChildItem -LiteralPath $requestsRoot -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
    $invocation = 0
    foreach ($verb in @($apply, $reset, $reset)) {
        $invocation++
        $action = [string]$verb.GetValue('PfiAction')
        $relativeKey = $verb.Name.Substring('HKEY_CURRENT_USER\'.Length)
        $launch = Invoke-PfiNativeProcess -FilePath $build.Executable -WorkingDirectory $build.Directory -TimeoutSeconds 120 `
            -ArgumentList @('--invoke-installed', $relativeKey, $pathFile) `
            -StdOutPath (Join-Path $testRoot ("invoke-$invocation.out.txt")) -StdErrPath (Join-Path $testRoot ("invoke-$invocation.err.txt"))
        $outcome = Get-PfiNativeOutcome -Launch $launch -PassPattern '(?m)^Installed COM dispatch accepted: '
        $fields.exit = $(if ($launch.Started) { [string]$launch.ExitCode } else { 'not-started:' + $launch.StartErrorCode })
        Add-PfiNativeLaunchRecord -CacheRoot $cacheRoot -Record ([ordered]@{ platform = $platform; mode = 'installed'; sha256 = $build.Sha256
            fingerprint = $build.Fingerprint; status = $outcome.Status; exit = $fields.exit; detail = $outcome.Detail })
        if ($outcome.Status -ne 'PASS') {
            # A blocked launch stops here: the same binary is not launched again in this run.
            $fields.status = $outcome.Status
            Write-Host (Format-PfiNativeLine -Kind 'RESULT' -Fields $fields -Detail ("$action invocation $invocation`: " + $outcome.Detail))
            exit $script:PfiNativeExitCodes[$outcome.Status]
        }
        $deadline = [DateTime]::UtcNow.AddSeconds(30)
        do {
            $complete = $true
            foreach ($folder in $folders) {
                $content = [IO.File]::ReadAllText((Join-Path $folder 'desktop.ini'))
                $hasIcon = $content.Contains('IconResource=')
                if (($action -eq 'Apply') -ne $hasIcon) { $complete = $false }
            }
            $pending = @(Get-ChildItem -LiteralPath $requestsRoot -File -ErrorAction SilentlyContinue | Where-Object Name -notin $requestsBefore)
            $brokers = @(Get-Process -Name 'PortableFolderIcons.SelectionBroker' -ErrorAction SilentlyContinue)
            if ($pending.Count -gt 0 -or $brokers.Count -gt 0) { $complete = $false }
            if (-not $complete) { Start-Sleep -Milliseconds 100 }
        } while (-not $complete -and [DateTime]::UtcNow -lt $deadline)
        if (-not $complete) { throw "Installed $action did not complete within 30 seconds." }
        foreach ($folder in $folders) {
            $content = [IO.File]::ReadAllText((Join-Path $folder 'desktop.ini'))
            if (-not $content.Contains('InfoTip=Preserve this') -or -not $content.Contains('[ViewState]')) {
                throw 'Installed dispatch changed unrelated desktop.ini content.'
            }
            if ($action -eq 'Apply') {
                $resource = [regex]::Match($content, '(?m)^IconResource=(.*),0\s*$').Groups[1].Value
                if ((Get-PfiSha256 $resource) -cne [string]$verb.GetValue('PfiIconHash')) {
                    throw 'Installed Apply did not use the registered icon identity.'
                }
            }
            $passed++
        }
        Write-Host ("Installed {0} verified on both fixture folders; unrelated INI content preserved." -f $action)
        Write-Host 'Request cleanup and COM broker exit confirmed.'
    }
    $fields.status = 'PASS'
    Write-Host (Format-PfiNativeLine -Kind 'RESULT' -Fields $fields -Detail ("{0} filesystem outcomes passed; evidence {1}" -f $passed, $testRoot))
    Write-Host ("Installed smoke: {0} filesystem outcomes passed. Evidence: {1}" -f $passed, $testRoot)
    exit 0
}
catch {
    $fields.status = 'FAIL'
    Write-Host (Format-PfiNativeLine -Kind 'RESULT' -Fields $fields -Detail ('check failed: ' + $_.Exception.Message))
    exit 1
}
