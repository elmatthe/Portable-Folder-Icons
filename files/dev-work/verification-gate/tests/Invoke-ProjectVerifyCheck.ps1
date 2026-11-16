# Gate checks c-0001 and c-0006, under Windows PowerShell 5.1:
#   -Target Suite     c-0001: the deterministic PowerShell suite, files\tests\Invoke-Tests.ps1 (functional behaviour).
#   -Target Verifier  c-0006: the project's authoritative verifier, scripts\verify.ps1 (suite again, plus required
#                     files, root layout, parsing, every ICO, docs, security scan and git diff --check).
#
# Both tools are called exactly as a user would call them, with no native flag, so every gate run exercises their
# default: the compiled C# harness is built or reused but its launch is withheld (endpoint security blocked
# unclassified builds on 2026-11-16); check c-0002 owns that result. When the withheld launch is the ONLY blocked
# item, this check speaks for everything else it ran. If a harness launch is recorded without authorization, this
# check FAILS (regression guard for the default). With PFI_GATE_NATIVE_HARNESS=allow (only after an authorized
# security review) the inherited environment authorizes the launch.
#
# Every [FAIL] line is labelled BASELINE (listed in known-baseline.tsv) or NEW. Labels never change the
# result: any failure keeps this check FAIL.
# Exit: 0 PASS, 1 FAIL, 2 BLOCKED, 3 BLOCKED_BY_ENDPOINT_SECURITY.
param([Parameter(Mandatory = $true)][ValidateSet('Suite', 'Verifier')][string]$Target)
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\..'))
$artifacts = $env:VERIFY_ARTIFACTS_DIR
if ([string]::IsNullOrWhiteSpace($artifacts)) { Write-Host 'BLOCKED: run through files\dev-work\verification-gate\verify.ps1'; exit 2 }
$allowNative = $env:PFI_GATE_NATIVE_HARNESS -eq 'allow'
$toolScript = if ($Target -eq 'Suite') { 'files\tests\Invoke-Tests.ps1' } else { 'scripts\verify.ps1' }
$log = Join-Path $artifacts ("project-{0}.log" -f $Target.ToLowerInvariant())
$arguments = @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $repoRoot $toolScript))
$windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
Write-Host ("Command: powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File {0}  (no native flag; launch {1})" -f $toolScript, $(if ($allowNative) { 'authorized by PFI_GATE_NATIVE_HARNESS=allow' } else { 'withheld by default' }))
$launchHistory = Join-Path $repoRoot 'files\dev-work\verification-gate\cache\native-harness\launch-history.jsonl'
$launchesBefore = if (Test-Path -LiteralPath $launchHistory) { @(Get-Content -LiteralPath $launchHistory).Count } else { 0 }
& $windowsPowerShell @arguments *> $log
$toolExit = $LASTEXITCODE
$launchesAfter = if (Test-Path -LiteralPath $launchHistory) { @(Get-Content -LiteralPath $launchHistory).Count } else { 0 }
$lines = @(Get-Content -LiteralPath $log)
$unauthorizedLaunch = (-not $allowNative) -and (($launchesAfter -gt $launchesBefore) -or
    @($lines | Where-Object { $_ -match '^Selection broker harness: \d+ passed|compiled harness launch denied|harness not executed' }).Count -gt 0)

$known = @()
foreach ($row in @(Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'known-baseline.tsv') | Where-Object { $_.Trim() -and -not $_.StartsWith('#') })) {
    $f = $row.Split("`t")
    $known += [pscustomobject]@{ Id = $f[0]; Line = $f[1]; FirstSeen = $f[2]; Classification = $f[3] }
}
$failLines = @($lines | Where-Object { $_ -match '^\s*\[FAIL\]' } | ForEach-Object { ($_ -replace '^\s*\[FAIL\]\s*', '').Trim() })
$blockedLines = @($lines | Where-Object { $_ -match '^\s*BLOCKED: ' } | ForEach-Object { ($_ -replace '^\s*BLOCKED:\s*', '').Trim() } | Sort-Object -Unique)
$suite = @($lines | Where-Object { $_ -match '^Tests: ' }) | Select-Object -Last 1
$harness = @($lines | Where-Object { $_ -match '^Selection broker harness: ' }) | Select-Object -Last 1
$result = @($lines | Where-Object { $_ -match '^RESULT: ' }) | Select-Object -Last 1

$report = @("# $($Target): $toolScript", '', "- Exit: $toolExit $(if ($result) { "($result)" })", "- PowerShell suite: $suite",
    "- C# harness: $(if ($harness) { $harness } elseif ($allowNative) { 'no result line (see log)' } else { 'launch withheld by default (no authorization); result owned by c-0002' })",
    "- Harness launches recorded during this check: $($launchesAfter - $launchesBefore)$(if ($unauthorizedLaunch) { ' -- UNAUTHORIZED' })", '',
    '| Item | Label |', '|---|---|')
$newFailures = 0
foreach ($failure in $failLines) {
    $match = @($known | Where-Object { $_.Line -ceq $failure })
    if ($match.Count -gt 0) { $label = "BASELINE $($match[0].Id) since $($match[0].FirstSeen)" } else { $label = 'NEW'; $newFailures++ }
    $report += "| FAIL: $($failure.Replace('|', '\|')) | $label |"
    Write-Host ("  [FAIL] {0} -- {1}" -f $failure, $label)
}
foreach ($b in $blockedLines) { $report += "| BLOCKED: $($b.Replace('|', '\|')) | BLOCKED |"; Write-Host "  [BLOCKED] $b" }
[IO.File]::WriteAllLines((Join-Path $artifacts ("project-{0}-classification.md" -f $Target.ToLowerInvariant())), [string[]]$report, (New-Object Text.UTF8Encoding($false)))
Write-Host ("{0} {1}; failures {2} ({3} NEW, {4} BASELINE); blocked {5}" -f $suite, $result, $failLines.Count, $newFailures, ($failLines.Count - $newFailures), $blockedLines.Count)

if ($unauthorizedLaunch) {
    Write-Host '  [FAIL] a compiled harness was launched without authorization (the default must withhold it) -- NEW'
    exit 1
}
# Suite exits 0/1/3; verifier exits 0/1/2. A failure always wins.
if ($toolExit -eq 0) { exit 0 }
if ($toolExit -eq 1 -or $failLines.Count -gt 0) { exit 1 }
if ($toolExit -in @(2, 3)) {
    $withheldOnly = (-not $allowNative) -and $blockedLines.Count -gt 0 -and
        @($blockedLines | Where-Object { $_ -notmatch '^BLOCKED_BY_ENDPOINT_SECURITY \(withheld, not launched\)' }).Count -eq 0
    if ($withheldOnly) { Write-Host 'All executed checks passed; the withheld harness launch is reported by c-0002.'; exit 0 }
    if (@($blockedLines | Where-Object { $_ -match 'BLOCKED_BY_ENDPOINT_SECURITY' }).Count -gt 0) { exit 3 }
    exit 2
}
exit 1
