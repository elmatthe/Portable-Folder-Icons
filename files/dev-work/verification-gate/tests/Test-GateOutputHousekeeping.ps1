# Gate check c-0008: safeguards of the gate-output housekeeping helper (helpers\Remove-GateOutputs.ps1).
#
# Builds a disposable fake "files\dev-work\verification-gate\outputs" tree inside this run's temp folder (itself under
# the real, ignored outputs folder) and proves: a dry run deletes nothing; -Apply removes only unretained immediate
# child directories; RETAIN.md, possibly active runs, loose files and anything containing a link are kept; a link is
# never followed; unexpected roots, roots outside the repository, linked roots and unsafe -Name values are refused.
# A dry run against the real outputs folder must delete nothing. Exit: 0 PASS, 1 FAIL.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\..'))
$helper = Join-Path (Split-Path -Parent $PSScriptRoot) 'helpers\Remove-GateOutputs.ps1'
$realOutputs = Join-Path (Split-Path -Parent $PSScriptRoot) 'outputs'
$windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

$script:Passed = 0
$script:Failed = 0
function Assert-Equal {
    param($Expected, $Actual, [string]$Name)
    if ($Expected -ceq $Actual) { $script:Passed++; Write-Host ("  [PASS] {0}" -f $Name) }
    else { $script:Failed++; Write-Host ("  [FAIL] {0}: expected <{1}> actual <{2}>" -f $Name, $Expected, $Actual) }
}
function Assert-True { param([bool]$Value, [string]$Name) Assert-Equal $true $Value $Name }

$base = $env:VERIFY_TEMP_DIR
$ownBase = $false
if ([string]::IsNullOrWhiteSpace($base)) {
    # Run directly: use a self-removing folder under the real (ignored) outputs folder.
    $base = Join-Path $realOutputs ('housekeeping-selftest-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
    $ownBase = $true
}
$work = Join-Path $base ('hk-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
$junctions = New-Object Collections.Generic.List[string]

function New-FakeOutputs([string]$Name) {
    $root = Join-Path $work ($Name + '\files\dev-work\verification-gate\outputs')
    [void](New-Item -ItemType Directory -Path $root -Force)
    return $root
}
function New-File([string]$Path, [string]$Text = 'x') {
    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force)
    [IO.File]::WriteAllText($Path, $Text)
}
function New-Junction([string]$Path, [string]$Target) {
    [void](New-Item -ItemType Junction -Path $Path -Value $Target)
    $junctions.Add($Path)
}
function Invoke-Helper([string[]]$Arguments) {
    # Local Continue: a child's stderr must never become a terminating error here (see c-0007, 2026-11-16).
    $ErrorActionPreference = 'Continue'
    $output = & $windowsPowerShell -NoLogo -NoProfile -ExecutionPolicy Bypass -File $helper @Arguments 2>&1 | ForEach-Object { "$_" }
    [pscustomobject]@{ Exit = $LASTEXITCODE; Text = ($output -join "`n") }
}

try {
    Write-Host '1. Fixture'
    $outputs = New-FakeOutputs 'repo'
    $complete = Join-Path $outputs '20261116T000000Z-aaaaaa'
    New-File (Join-Path $complete 'summary.md'); New-File (Join-Path $complete 'results.json'); New-File (Join-Path $complete 'logs\c-0001.log')
    $activeRun = Join-Path $outputs '20261116T000001Z-bbbbbb'
    New-File (Join-Path $activeRun 'logs\c-0001.log')
    $staleRun = Join-Path $outputs '20261116T000002Z-cccccc'
    New-File (Join-Path $staleRun 'logs\c-0001.log')
    foreach ($item in @((Join-Path $staleRun 'logs\c-0001.log'), (Join-Path $staleRun 'logs'), $staleRun)) {
        (Get-Item -LiteralPath $item -Force).LastWriteTimeUtc = [DateTime]::UtcNow.AddDays(-2)
    }
    $retained = Join-Path $outputs 'retained-evidence'
    New-File (Join-Path $retained 'RETAIN.md') 'Reason: pending manual gate. Remove after M01 passes.'
    New-File (Join-Path $retained 'note.md') 'keep me'
    $phase = Join-Path $outputs 'phase-x'
    New-File (Join-Path $phase 'diagnostics\a.txt')
    $sentinel = Join-Path $work 'sentinel'
    New-File (Join-Path $sentinel 'must-survive.txt') 'sentinel'
    $linked = Join-Path $outputs 'linked'
    New-File (Join-Path $linked 'plain.txt')
    New-Junction (Join-Path $linked 'to-sentinel') $sentinel
    New-File (Join-Path $outputs 'verify-state.json') '{}'
    New-File (Join-Path $outputs 'loose.txt')
    Assert-True (Test-Path -LiteralPath $helper -PathType Leaf) 'the helper exists in the gate helpers folder'

    Write-Host '2. Dry run (default) deletes nothing'
    $dry = Invoke-Helper @('-OutputsRoot', $outputs)
    Assert-Equal 0 $dry.Exit 'dry run exits 0'
    foreach ($path in @($complete, $activeRun, $staleRun, $retained, $phase, $linked)) { Assert-True (Test-Path -LiteralPath $path) ("dry run keeps {0}" -f (Split-Path -Leaf $path)) }
    Assert-True ($dry.Text -match 'DRY RUN') 'dry run says it is a dry run'
    Assert-True ($dry.Text -match 'would remove\s+20261116T000000Z-aaaaaa') 'dry run lists a completed run as removable'

    Write-Host '3. Unsafe -Name values are refused before anything is deleted'
    foreach ($bad in @('..\repo', 'phase-x\diagnostics', 'C:\Windows', '.', 'missing-dir', 'verify-state.json')) {
        $refused = Invoke-Helper @('-OutputsRoot', $outputs, '-Name', $bad, '-Apply')
        Assert-Equal 2 $refused.Exit ("-Name '{0}' is refused" -f $bad)
    }
    Assert-True (Test-Path -LiteralPath $phase) 'refused names deleted nothing'

    Write-Host '4. Unsafe roots are refused'
    $wrongLeaf = Split-Path -Parent $outputs
    Assert-Equal 2 (Invoke-Helper @('-OutputsRoot', $wrongLeaf, '-Apply')).Exit 'a root that is not ...\verification-gate\outputs is refused'
    $outside = Join-Path $env:SystemRoot 'Temp\pfi-not-created\files\dev-work\verification-gate\outputs'
    Assert-Equal 2 (Invoke-Helper @('-OutputsRoot', $outside, '-Apply')).Exit 'a root outside the repository outputs folder is refused'
    Assert-Equal $false (Test-Path -LiteralPath $outside) 'nothing is created outside the repository'
    Assert-Equal 2 (Invoke-Helper @('-OutputsRoot', (Join-Path $repoRoot 'files'), '-Apply')).Exit 'the files folder itself is refused'
    $linkedRootParent = Join-Path $work 'linkedroot\files\dev-work\verification-gate'
    [void](New-Item -ItemType Directory -Path $linkedRootParent -Force)
    $sentinel2 = Join-Path $work 'sentinel2'
    New-File (Join-Path $sentinel2 '20261116T000009Z-dddddd\summary.md') 'sentinel2'
    New-Junction (Join-Path $linkedRootParent 'outputs') $sentinel2
    Assert-Equal 2 (Invoke-Helper @('-OutputsRoot', (Join-Path $linkedRootParent 'outputs'), '-Apply')).Exit 'a linked outputs root is refused'
    Assert-True (Test-Path -LiteralPath (Join-Path $sentinel2 '20261116T000009Z-dddddd\summary.md')) 'the target of a linked root is untouched'

    Write-Host '5. -Apply removes only verified disposable directories'
    $apply = Invoke-Helper @('-OutputsRoot', $outputs, '-Apply')
    Assert-Equal 0 $apply.Exit 'apply exits 0'
    Assert-Equal $false (Test-Path -LiteralPath $complete) 'a completed run is removed'
    Assert-Equal $false (Test-Path -LiteralPath $staleRun) 'an old incomplete run is removed'
    Assert-Equal $false (Test-Path -LiteralPath $phase) 'an unretained evidence folder is removed'
    Assert-True (Test-Path -LiteralPath $activeRun) 'a recent incomplete (possibly active) run is kept'
    Assert-True (Test-Path -LiteralPath (Join-Path $retained 'note.md')) 'a folder with RETAIN.md is kept with its contents'
    Assert-True (Test-Path -LiteralPath (Join-Path $linked 'plain.txt')) 'a folder containing a link is refused, not deleted'
    Assert-Equal 'sentinel' ([IO.File]::ReadAllText((Join-Path $sentinel 'must-survive.txt'))) 'a link target outside outputs is never touched'
    Assert-True (Test-Path -LiteralPath (Join-Path $outputs 'verify-state.json')) 'the status index is kept'
    Assert-True (Test-Path -LiteralPath (Join-Path $outputs 'loose.txt')) 'loose files are never deleted'
    Assert-True ($apply.Text -match 'retained\s+retained-evidence') 'the report names what was retained'
    Assert-True ($apply.Text -match 'refused\s+linked') 'the report names what was refused'

    Write-Host '6. -Name narrows the scope; a retained folder stays retained'
    New-File (Join-Path $outputs 'one\a.txt'); New-File (Join-Path $outputs 'two\a.txt')
    $named = Invoke-Helper @('-OutputsRoot', $outputs, '-Name', 'one,retained-evidence', '-Apply')
    Assert-Equal 0 $named.Exit 'a named cleanup exits 0'
    Assert-Equal $false (Test-Path -LiteralPath (Join-Path $outputs 'one')) 'the named folder is removed'
    Assert-True (Test-Path -LiteralPath (Join-Path $outputs 'two')) 'an unnamed folder is kept'
    Assert-True (Test-Path -LiteralPath (Join-Path $retained 'RETAIN.md')) 'naming a retained folder does not remove it'

    Write-Host '7. Dry run against the real outputs folder deletes nothing'
    $before = @(Get-ChildItem -LiteralPath $realOutputs -Force | ForEach-Object Name | Sort-Object) -join '|'
    $real = Invoke-Helper @()
    $after = @(Get-ChildItem -LiteralPath $realOutputs -Force | ForEach-Object Name | Sort-Object) -join '|'
    Assert-Equal 0 $real.Exit 'the default root resolves and a dry run succeeds'
    Assert-Equal $before $after 'a dry run on the real outputs folder changes nothing'
}
finally {
    foreach ($junction in $junctions) { if (Test-Path -LiteralPath $junction) { [IO.Directory]::Delete($junction) } }
    if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
    if ($ownBase -and (Test-Path -LiteralPath $base)) { Remove-Item -LiteralPath $base -Recurse -Force }
}

Write-Host ('Housekeeping safeguards: {0} passed, {1} failed' -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
exit 0
