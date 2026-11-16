[CmdletBinding()]
param(
    # Build each harness once (or reuse the verified cached build) and report its identity; launch nothing.
    [switch]$BuildOnly,
    # Defaults to files\dev-work\verification-gate\cache\native-harness (ignored).
    [string]$CacheRoot
)

# Focused x64/x86 run of the compiled selection-broker harness: registration-derived Apply/Reset initialization and
# the native VARIANT ABI. Launching a compiled harness needs PFI_GATE_NATIVE_HARNESS=allow (endpoint security blocked
# fresh builds on 2026-11-16); without it this runner withholds the launch and reports BLOCKED_BY_ENDPOINT_SECURITY.
# Each platform reports one "PFI-NATIVE-BUILD" line and, unless -BuildOnly, one "PFI-NATIVE-RESULT" line.
# Exit: 0 PASS, 1 FAIL, 2 BLOCKED, 3 BLOCKED_BY_ENDPOINT_SECURITY, 5 CRASH.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repoRoot 'scripts\Windows\PortableFolderIcons.Core.ps1')
. (Join-Path $repoRoot 'scripts\Windows\PortableFolderIcons.Integration.ps1')
. (Join-Path $PSScriptRoot 'NativeHarness.Common.ps1')
if ([string]::IsNullOrWhiteSpace($CacheRoot)) { $CacheRoot = Get-PfiNativeHarnessCacheRoot -RepoRoot $repoRoot }
$sourceRoot = Join-Path $repoRoot 'scripts\Windows\SelectionHandler'
$harnessSource = Join-Path $PSScriptRoot 'SelectionBrokerHarness.cs'
$buildManifest = Read-PfiSelectionBrokerBuildManifest `
    (Join-Path $sourceRoot 'SelectionBroker.build.json') `
    (Join-Path $sourceRoot 'PortableFolderIcons.SelectionBroker.cs')
$launchAllowed = $env:PFI_GATE_NATIVE_HARNESS -eq 'allow'
$testRoot = $null
$manifest = $null
if (-not $BuildOnly -and $launchAllowed) {
    # Evidence and registration-derived contracts are needed only when a harness will actually run.
    $testRoot = Join-Path $repoRoot ('files\test-logs\selection-focused-' + [guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $testRoot)
    $inventory = @(Get-PfiIconInventory -SourceDirectory (Join-Path $repoRoot 'files\ICO-Files') `
        -CacheDirectory (Join-Path $testRoot 'icons'))
    $rejected = @($inventory | Where-Object Status -ne 'Accepted')
    if ($rejected.Count -ne 0) { throw 'Current source ICO inventory contains rejected entries.' }
    $manifest = New-PfiManifest -Inventory $inventory
}
$statuses = @()

foreach ($platform in @('x64', 'x86')) {
    $artifact = Join-Path $sourceRoot ('PortableFolderIcons.SelectionBroker.' + $platform + '.exe')
    $identity = Test-PfiSelectionBrokerArtifact $artifact $buildManifest $platform
    $build = Get-PfiNativeHarnessBuild -Platform $platform -BrokerAssembly $artifact -HarnessSource $harnessSource -CacheRoot $CacheRoot
    $relative = [string]$build.Executable
    if ($relative.StartsWith($repoRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { $relative = $relative.Substring($repoRoot.Length + 1) }
    Write-Host (Format-PfiNativeLine -Kind 'BUILD' -Fields ([ordered]@{ platform = $platform; status = $build.Status
        cache = $(if ($build.CacheHit) { 'hit' } elseif ($build.Compiled) { 'miss' } else { 'none' })
        sha256 = $build.Sha256; fingerprint = $build.Fingerprint; path = $relative }) -Detail ($build.Reason + $(if ($build.Detail) { '; ' + $build.Detail } else { '' })))
    if ($build.Status -ne 'READY') { $statuses += $build.Status; continue }
    if ($BuildOnly) { $statuses += 'PASS'; continue }

    $fields = [ordered]@{ platform = $platform; mode = 'focused'; status = ''; exit = ''; assertions = ''; sha256 = $build.Sha256
        cache = $(if ($build.CacheHit) { 'hit' } else { 'miss' }); fingerprint = $build.Fingerprint }
    if (-not $launchAllowed) {
        $fields.status = 'BLOCKED_BY_ENDPOINT_SECURITY'
        Write-Host (Format-PfiNativeLine -Kind 'RESULT' -Fields $fields -Detail 'withheld, not launched: set PFI_GATE_NATIVE_HARNESS=allow after an authorized security decision')
        $statuses += $fields.status
        continue
    }
    $permission = Get-PfiNativeLaunchPermission -CacheRoot $CacheRoot -Sha256 $build.Sha256
    if (-not $permission.Permitted) {
        $fields.status = 'BLOCKED_BY_ENDPOINT_SECURITY'
        Write-Host (Format-PfiNativeLine -Kind 'RESULT' -Fields $fields -Detail $permission.Reason)
        $statuses += $fields.status
        continue
    }

    $plan = @(Get-PfiRegistryPlan -Manifest $manifest -InstallRoot $testRoot -SelectionBrokerHash $identity.Sha256)
    $contracts = @($plan | Where-Object Name -eq 'PfiAction' | ForEach-Object {
        $verbPath = $_.Path
        $hash = @($plan | Where-Object { $_.Path -eq $verbPath -and $_.Name -eq 'PfiIconHash' })
        (Split-Path -Leaf $verbPath) + "`t" + $_.Value + "`t" + $(if ($hash.Count -eq 1) { $hash[0].Value } else { '' })
    })
    $contractsPath = Join-Path $testRoot ('contracts-' + $platform + '.tsv')
    [IO.File]::WriteAllLines($contractsPath, [string[]]$contracts, (New-Object Text.UTF8Encoding($false)))
    $launch = Invoke-PfiNativeProcess -FilePath $build.Executable -ArgumentList @($contractsPath) -WorkingDirectory $build.Directory `
        -TimeoutSeconds 300 -StdOutPath (Join-Path $testRoot ('harness-' + $platform + '.out.txt')) `
        -StdErrPath (Join-Path $testRoot ('harness-' + $platform + '.err.txt'))
    $outcome = Get-PfiNativeOutcome -Launch $launch -PassPattern '(?m)^Selection broker harness: (?<count>\d+) passed'
    $fields.status = $outcome.Status
    $fields.exit = $(if ($launch.Started) { [string]$launch.ExitCode } else { 'not-started:' + $launch.StartErrorCode })
    $fields.assertions = [string]$outcome.Assertions
    Add-PfiNativeLaunchRecord -CacheRoot $CacheRoot -Record ([ordered]@{ platform = $platform; mode = 'focused'; sha256 = $build.Sha256
        fingerprint = $build.Fingerprint; status = $outcome.Status; exit = $fields.exit; assertions = $outcome.Assertions; detail = $outcome.Detail })
    Write-Host (Format-PfiNativeLine -Kind 'RESULT' -Fields $fields -Detail $outcome.Detail)
    $statuses += $outcome.Status
}
if ($testRoot) { Write-Host ('Focused evidence: ' + $testRoot) }
foreach ($status in @('FAIL', 'CRASH', 'BLOCKED_BY_ENDPOINT_SECURITY', 'BLOCKED')) {
    if ($statuses -contains $status) { exit $script:PfiNativeExitCodes[$status] }
}
exit 0
