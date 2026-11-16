# Gate check c-0002: the compiled C# selection-broker harness (registration-derived initialization and native
# VARIANT ABI, x64 and x86), run by files\tests\Invoke-SelectionBrokerTests.ps1.
#
# Default (no opt-in): the runner builds each harness once, or reuses the verified cached build for unchanged inputs
# (files\dev-work\verification-gate\cache\native-harness), reports its path, SHA-256 and cache hit/miss, and launches
# nothing. Result: BLOCKED_BY_ENDPOINT_SECURITY (exit 3, withheld), or FAIL (exit 1) if a harness does not build.
# With PFI_GATE_NATIVE_HARNESS=allow (only after an authorized security decision): the cached harnesses are launched
# once each. PASS requires the runner to exit 0 AND a PASS line with a positive assertion count for x64 and x86.
#
# History: WatchGuard blocked SelectionBrokerHarness.x64.exe 35482483... and later b2eaad08... on 2026-11-16. Run
# 20261116T161427Z-965594 recorded this check as FAIL because the old wrapper captured the runner's stderr under
# -ErrorAction Stop; its CORRECTION.md records the true result. The runner is now captured with
# Invoke-PfiNativeProcess, which never turns stderr into a terminating error.
# Exit: 0 PASS, 1 FAIL, 2 BLOCKED, 3 BLOCKED_BY_ENDPOINT_SECURITY, 5 CRASH (a FAIL that is not an assertion verdict).
param(
    # Test seam for c-0007 only: replaces the runner with a stub. The gate never passes it.
    [string]$RunnerScript
)
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\..'))
. (Join-Path $repoRoot 'files\tests\NativeHarness.Common.ps1')
if ([string]::IsNullOrWhiteSpace($RunnerScript)) { $RunnerScript = Join-Path $repoRoot 'files\tests\Invoke-SelectionBrokerTests.ps1' }
$artifacts = $env:VERIFY_ARTIFACTS_DIR
if ([string]::IsNullOrWhiteSpace($artifacts)) { Write-Host 'BLOCKED: run through files\dev-work\verification-gate\verify.ps1'; exit 2 }

$allowLaunch = $env:PFI_GATE_NATIVE_HARNESS -eq 'allow'
$arguments = @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $RunnerScript)
if (-not $allowLaunch) { $arguments += '-BuildOnly' }
$windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
Write-Host ("Mode: {0}" -f $(if ($allowLaunch) { 'EXECUTE (PFI_GATE_NATIVE_HARNESS=allow)' } else { 'build/reuse only; launch withheld' }))
$runner = Invoke-PfiNativeProcess -FilePath $windowsPowerShell -ArgumentList $arguments -TimeoutSeconds 840 `
    -StdOutPath (Join-Path $artifacts 'native-harness.log') -StdErrPath (Join-Path $artifacts 'native-harness.stderr.log')
Write-Host $runner.StdOut
if (-not [string]::IsNullOrWhiteSpace($runner.StdErr)) { Write-Host ('stderr: ' + $runner.StdErr) }
Write-Host ("Runner exit: {0}" -f (Format-PfiNativeExitCode $runner.ExitCode))

$builds = ConvertFrom-PfiNativeLine -Kind 'BUILD' -Text $runner.StdOut
$results = ConvertFrom-PfiNativeLine -Kind 'RESULT' -Text $runner.StdOut
if ($allowLaunch) { $verdict = Resolve-PfiNativeCheckResult -Runner $runner -Results $results -ExpectedPlatforms @('x64', 'x86') }
else { $verdict = Resolve-PfiNativeBuildOnlyResult -Runner $runner -Builds $builds -ExpectedPlatforms @('x64', 'x86') }

$evidence = [ordered]@{
    check = 'c-0002'
    mode = $(if ($allowLaunch) { 'execute' } else { 'build-only' })
    runner = [ordered]@{ script = $RunnerScript; started = $runner.Started; startErrorCode = $runner.StartErrorCode; exitCode = $runner.ExitCode
        timedOut = $runner.TimedOut; durationSeconds = $runner.DurationSeconds }
    builds = $builds
    results = $results
    verdict = [ordered]@{ status = $verdict.Status; exit = $verdict.Exit; detail = $verdict.Detail }
}
[IO.File]::WriteAllText((Join-Path $artifacts 'native-harness-evidence.json'), ($evidence | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
Write-Host ("{0}: {1}" -f $verdict.Status, $verdict.Detail)
exit $verdict.Exit
