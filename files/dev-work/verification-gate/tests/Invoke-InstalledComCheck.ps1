# Gate check c-0004 (optional, opt-in): actual installed x64 COM Apply/Reset dispatch on fresh repository
# fixtures, via the developer runner files\tests\Invoke-InstalledSelectionBrokerTests.ps1.
# It reads the real installed registration, activates the real installed broker and launches the cached compiled
# harness (also subject to the endpoint-security decision). It never runs by default.
# Opt in only deliberately, for one run: PFI_GATE_INSTALLED_COM=allow AND PFI_GATE_NATIVE_HARNESS=allow.
#
# 2026-11-16: this wrapper used to capture the runner with *> under -ErrorAction Stop, so a denied harness launch
# (runner stderr "failed to run: Access is denied") became a terminating error here and was reported as FAIL. It now
# uses Invoke-PfiNativeProcess; regression coverage is check c-0007.
# Exit: 0 PASS, 1 FAIL, 2 BLOCKED, 3 BLOCKED_BY_ENDPOINT_SECURITY, 4 NOT RUN (no opt-in), 5 CRASH.
param(
    # Test seam for c-0007 only: replaces the runner with a stub. The gate never passes it.
    [string]$RunnerScript
)
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\..'))
if ($env:PFI_GATE_INSTALLED_COM -ne 'allow') {
    Write-Host 'NOT RUN: installed-COM smoke test is opt-in (set PFI_GATE_INSTALLED_COM=allow). It uses the live installation.'
    exit 4
}
if ($env:PFI_GATE_NATIVE_HARNESS -ne 'allow') {
    Write-Host 'BLOCKED_BY_ENDPOINT_SECURITY (withheld): this test launches the compiled harness; see c-0002.'
    exit 3
}
$artifacts = $env:VERIFY_ARTIFACTS_DIR
if ([string]::IsNullOrWhiteSpace($artifacts)) { Write-Host 'BLOCKED: run through files\dev-work\verification-gate\verify.ps1'; exit 2 }
. (Join-Path $repoRoot 'files\tests\NativeHarness.Common.ps1')
if ([string]::IsNullOrWhiteSpace($RunnerScript)) { $RunnerScript = Join-Path $repoRoot 'files\tests\Invoke-InstalledSelectionBrokerTests.ps1' }

$windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$runner = Invoke-PfiNativeProcess -FilePath $windowsPowerShell -TimeoutSeconds 840 `
    -ArgumentList @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $RunnerScript) `
    -StdOutPath (Join-Path $artifacts 'installed-com.log') -StdErrPath (Join-Path $artifacts 'installed-com.stderr.log')
Write-Host $runner.StdOut
if (-not [string]::IsNullOrWhiteSpace($runner.StdErr)) { Write-Host ('stderr: ' + $runner.StdErr) }
Write-Host ("Runner exit: {0}" -f (Format-PfiNativeExitCode $runner.ExitCode))
$results = ConvertFrom-PfiNativeLine -Kind 'RESULT' -Text $runner.StdOut
$verdict = Resolve-PfiNativeCheckResult -Runner $runner -Results $results -ExpectedCount 1
Write-Host ("{0}: {1}" -f $verdict.Status, $verdict.Detail)
exit $verdict.Exit
