# Gate check c-0007: the verification infrastructure around compiled test executables.
#
# Proves, without launching any compiled test harness:
#   1. Outcome classification: PASS needs exit 0 AND a pass line; assertion failures, crashes, security-policy
#      launch denials, missing executables and timeouts are distinct, and none of them can become PASS.
#   2. Real process capture with inbox signed programs only (powershell.exe): stdout/stderr, exit codes,
#      argument quoting, a missing executable (never launched) and a timeout.
#   3. Wrapper result resolution for c-0002/c-0004, and both gate wrappers end to end with stub runners, including
#      the 2026-11-16 defect where a runner's stderr under -ErrorAction Stop turned a launch denial into FAIL.
#   4. Harness build cache in a disposable cache root: first build, reuse without recompiling, separate x64/x86
#      identities, invalidation on input change, rejection of a tampered artifact or record, compile failure.
#      Only csc.exe runs; the cached harness is never executed here.
#   5. Launch guard: a hash recorded as blocked is not launched again until reclassification is acknowledged.
# Exit: 0 PASS, 1 FAIL.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\..'))
. (Join-Path $repoRoot 'files\tests\NativeHarness.Common.ps1')

$script:Passed = 0
$script:Failed = 0
function Assert-Equal {
    param($Expected, $Actual, [string]$Name)
    if ($Expected -ceq $Actual) { $script:Passed++; Write-Host ("  [PASS] {0}" -f $Name) }
    else { $script:Failed++; Write-Host ("  [FAIL] {0}: expected <{1}> actual <{2}>" -f $Name, $Expected, $Actual) }
}
function Assert-True {
    param([bool]$Value, [string]$Name)
    Assert-Equal $true $Value $Name
}

$tempBase = $env:VERIFY_TEMP_DIR
if ([string]::IsNullOrWhiteSpace($tempBase)) { $tempBase = Join-Path $repoRoot 'files\test-logs' }
$work = Join-Path $tempBase ('native-infra-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
[void](New-Item -ItemType Directory -Path $work)
$windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$utf8 = New-Object Text.UTF8Encoding($false)

Write-Host '1. Outcome classification'
function New-Launch {
    param([bool]$Started = $true, $StartErrorCode = $null, $ExitCode = 0, [string]$StdOut = '', [string]$StdErr = '', [bool]$TimedOut = $false)
    [pscustomobject]@{ Started = $Started; StartErrorCode = $StartErrorCode; StartError = 'synthetic'; ExitCode = $ExitCode
        TimedOut = $TimedOut; StdOut = $StdOut; StdErr = $StdErr; DurationSeconds = 0 }
}
$harnessPass = '(?m)^Selection broker harness: (?<count>\d+) passed'
$cases = @(
    @{ Name = 'exit 0 with pass line'; Launch = (New-Launch -StdOut "Selection broker harness: 358 passed`r`n"); Status = 'PASS' },
    @{ Name = 'exit 0 without pass line'; Launch = (New-Launch -StdOut 'nothing ran'); Status = 'FAIL' },
    @{ Name = 'exit 0 with zero assertions'; Launch = (New-Launch -StdOut 'Selection broker harness: 0 passed'); Status = 'FAIL' },
    @{ Name = 'exit 1'; Launch = (New-Launch -ExitCode 1 -StdOut 'Selection broker harness: 10 passed'); Status = 'FAIL' },
    @{ Name = 'unhandled InvalidOperationException (harness assertion)'; Launch = (New-Launch -ExitCode -532462766 -StdErr "Unhandled Exception: System.InvalidOperationException: The broker rejected the registered verb: X`r`n   at Main"); Status = 'FAIL' },
    @{ Name = 'unhandled FileNotFoundException (crash)'; Launch = (New-Launch -ExitCode -532462766 -StdErr 'Unhandled Exception: System.IO.FileNotFoundException: Could not load file or assembly'); Status = 'CRASH' },
    @{ Name = 'unhandled CLR exception without stderr'; Launch = (New-Launch -ExitCode -532462766); Status = 'CRASH' },
    @{ Name = 'access violation 0xC0000005'; Launch = (New-Launch -ExitCode -1073741819); Status = 'CRASH' },
    @{ Name = 'launch denied, Win32 5'; Launch = (New-Launch -Started $false -StartErrorCode 5 -ExitCode $null); Status = 'BLOCKED_BY_ENDPOINT_SECURITY' },
    @{ Name = 'launch denied by policy, Win32 1260'; Launch = (New-Launch -Started $false -StartErrorCode 1260 -ExitCode $null); Status = 'BLOCKED_BY_ENDPOINT_SECURITY' },
    @{ Name = 'code integrity violation, Win32 4551'; Launch = (New-Launch -Started $false -StartErrorCode 4551 -ExitCode $null); Status = 'BLOCKED_BY_ENDPOINT_SECURITY' },
    @{ Name = 'missing executable, Win32 2'; Launch = (New-Launch -Started $false -StartErrorCode 2 -ExitCode $null); Status = 'BLOCKED' },
    @{ Name = 'timed out'; Launch = (New-Launch -TimedOut $true -ExitCode $null -StdOut 'Selection broker harness: 5 passed'); Status = 'BLOCKED' },
    @{ Name = 'started with unknown exit code'; Launch = (New-Launch -ExitCode $null -StdOut 'Selection broker harness: 5 passed'); Status = 'FAIL' }
)
foreach ($case in $cases) {
    $outcome = Get-PfiNativeOutcome -Launch $case.Launch -PassPattern $harnessPass
    Assert-Equal $case.Status $outcome.Status ("classifies {0} as {1}" -f $case.Name, $case.Status)
}
Assert-Equal 358 (Get-PfiNativeOutcome -Launch $cases[0].Launch -PassPattern $harnessPass).Assertions 'PASS reports the executed assertion count'
Assert-True ((Get-PfiNativeOutcome -Launch $cases[4].Launch -PassPattern $harnessPass).Detail -match 'assertion') 'an assertion failure is labelled as an assertion, not a crash'
Assert-True ((Get-PfiNativeOutcome -Launch $cases[5].Launch -PassPattern $harnessPass).Detail -match 'FileNotFoundException') 'a crash names the exception type'
Assert-True ((Get-PfiNativeOutcome -Launch $cases[7].Launch -PassPattern $harnessPass).Detail -match '0xC0000005') 'a crash names the NTSTATUS code'

Write-Host '2. Real process capture (inbox powershell.exe only)'
$capture = Invoke-PfiNativeProcess -FilePath $windowsPowerShell -TimeoutSeconds 60 -ArgumentList @('-NoLogo', '-NoProfile', '-Command',
    "[Console]::Out.WriteLine('to-stdout'); [Console]::Error.WriteLine('to-stderr'); exit 7")
Assert-Equal $true $capture.Started 'a real child process starts'
Assert-Equal 7 $capture.ExitCode 'the real exit code is captured'
Assert-True ($capture.StdOut -match 'to-stdout') 'stdout is captured'
Assert-True ($capture.StdErr -match 'to-stderr') 'stderr is captured without becoming a terminating error'
Assert-Equal 'FAIL' (Get-PfiNativeOutcome -Launch $capture -PassPattern 'to-stdout').Status 'a nonzero exit is never PASS even when the pass text is present'

$echoScript = Join-Path $work 'echo-args.ps1'
[IO.File]::WriteAllText($echoScript, 'foreach ($a in $args) { [Console]::Out.WriteLine("<" + $a + ">") }', $utf8)
$tricky = @('plain', 'with space', 'quote"inside', 'trailing\', 'C:\dir with space\')
$echo = Invoke-PfiNativeProcess -FilePath $windowsPowerShell -TimeoutSeconds 60 -ArgumentList (@('-NoLogo', '-NoProfile', '-File', $echoScript) + $tricky)
$expectedEcho = ($tricky | ForEach-Object { '<' + $_ + '>' }) -join "`n"
Assert-Equal $expectedEcho (($echo.StdOut -replace "`r", '').Trim()) 'arguments with spaces, quotes and trailing backslashes arrive intact'

$missing = Join-Path $work 'does-not-exist.exe'
$missingLaunch = Invoke-PfiNativeProcess -FilePath $missing -TimeoutSeconds 10
Assert-Equal $false $missingLaunch.Started 'a missing executable is not started'
Assert-Equal 2 $missingLaunch.StartErrorCode 'a missing executable reports Win32 2'
Assert-Equal 'BLOCKED' (Get-PfiNativeOutcome -Launch $missingLaunch -PassPattern '.').Status 'a missing executable is BLOCKED, never PASS'
Assert-Equal $false (Test-Path -LiteralPath $missing) 'nothing is created at the missing executable path'

$slow = Invoke-PfiNativeProcess -FilePath $windowsPowerShell -TimeoutSeconds 2 -ArgumentList @('-NoLogo', '-NoProfile', '-Command', 'Start-Sleep -Seconds 30')
Assert-Equal $true $slow.TimedOut 'a hung process times out'
Assert-Equal 'BLOCKED' (Get-PfiNativeOutcome -Launch $slow -PassPattern '.').Status 'a timeout is BLOCKED, never PASS'
Assert-Equal 0 @(Get-Process -Id $slow.ProcessId -ErrorAction SilentlyContinue).Count 'the timed-out process was stopped'

$envProbe = Invoke-PfiNativeProcess -FilePath $windowsPowerShell -TimeoutSeconds 60 -Environment @{ PFI_TEST_SET = 'yes'; PATHEXT_UNUSED_PFI = $null } `
    -ArgumentList @('-NoLogo', '-NoProfile', '-Command', '[Console]::Out.WriteLine($env:PFI_TEST_SET)')
Assert-Equal 'yes' $envProbe.StdOut.Trim() 'a per-launch environment reaches only the child'
Assert-Equal $null $env:PFI_TEST_SET 'the per-launch environment does not leak into this process'

Write-Host '3. Wrapper result resolution'
function New-Result([string]$Platform, [string]$Status, [string]$Mode = 'focused') {
    @{ platform = $Platform; status = $Status; mode = $Mode; exit = '0' }
}
$runner0 = New-Launch -ExitCode 0
$resolutions = @(
    @{ Name = 'both platforms PASS'; Runner = $runner0; Results = @((New-Result 'x64' 'PASS'), (New-Result 'x86' 'PASS')); Exit = 0 },
    @{ Name = 'runner exit 0 without result lines'; Runner = $runner0; Results = @(); Exit = 1 },
    @{ Name = 'one platform missing'; Runner = $runner0; Results = @((New-Result 'x64' 'PASS')); Exit = 1 },
    @{ Name = 'x64 PASS, x86 blocked'; Runner = (New-Launch -ExitCode 3); Results = @((New-Result 'x64' 'PASS'), (New-Result 'x86' 'BLOCKED_BY_ENDPOINT_SECURITY')); Exit = 3 },
    @{ Name = 'assertion failure'; Runner = (New-Launch -ExitCode 1); Results = @((New-Result 'x64' 'FAIL'), (New-Result 'x86' 'PASS')); Exit = 1 },
    @{ Name = 'crash'; Runner = (New-Launch -ExitCode 5); Results = @((New-Result 'x64' 'CRASH'), (New-Result 'x86' 'PASS')); Exit = 5 },
    @{ Name = 'failure outranks a block'; Runner = (New-Launch -ExitCode 1); Results = @((New-Result 'x64' 'BLOCKED_BY_ENDPOINT_SECURITY'), (New-Result 'x86' 'FAIL')); Exit = 1 },
    @{ Name = 'old runner shape: denial text, no lines'; Runner = (New-Launch -ExitCode 1 -StdErr "Program 'SelectionBrokerHarness.x64.exe' failed to run: Access is denied"); Results = @(); Exit = 3 },
    @{ Name = 'runner itself denied'; Runner = (New-Launch -Started $false -StartErrorCode 5 -ExitCode $null); Results = @(); Exit = 3 },
    @{ Name = 'runner timed out'; Runner = (New-Launch -TimedOut $true -ExitCode $null); Results = @(); Exit = 2 },
    @{ Name = 'runner exit 1 with PASS lines'; Runner = (New-Launch -ExitCode 1); Results = @((New-Result 'x64' 'PASS'), (New-Result 'x86' 'PASS')); Exit = 1 }
)
foreach ($case in $resolutions) {
    $verdict = Resolve-PfiNativeCheckResult -Runner $case.Runner -Results $case.Results -ExpectedPlatforms @('x64', 'x86')
    Assert-Equal $case.Exit $verdict.Exit ("resolves '{0}' to exit {1}" -f $case.Name, $case.Exit)
}
$single = Resolve-PfiNativeCheckResult -Runner $runner0 -Results @((New-Result 'x64' 'PASS' 'installed')) -ExpectedCount 1
Assert-Equal 0 $single.Exit 'installed mode: one PASS line from a clean runner is PASS'
$parsed = @(ConvertFrom-PfiNativeLine -Kind 'RESULT' -Text ("noise`r`n" + (Format-PfiNativeLine -Kind 'RESULT' -Fields ([ordered]@{ platform = 'x64'; status = 'PASS'; path = 'C:\a b%c\x.exe' }) -Detail 'free text = ok') + "`r`n"))
Assert-Equal 1 $parsed.Count 'result lines are parsed out of surrounding output'
Assert-Equal 'C:\a b%c\x.exe' $parsed[0].path 'a value with spaces and percent signs round-trips'
Assert-Equal 'free text = ok' $parsed[0].detail 'free-text detail round-trips'

Write-Host '4. Gate wrappers end to end with stub runners'
$stubRoot = Join-Path $work 'stubs'
[void](New-Item -ItemType Directory -Path $stubRoot)
function New-StubRunner {
    param([string]$Name, [string[]]$Out = @(), [string[]]$Err = @(), [int]$Exit = 0)
    $path = Join-Path $stubRoot ($Name + '.ps1')
    $marker = Join-Path $stubRoot ($Name + '.invoked.txt')
    $lines = @('param([switch]$BuildOnly)',
        ('[IO.File]::AppendAllText(''{0}'', (''BuildOnly='' + [bool]$BuildOnly + [Environment]::NewLine))' -f $marker.Replace("'", "''")))
    foreach ($o in $Out) { $lines += ('[Console]::Out.WriteLine(''{0}'')' -f $o.Replace("'", "''")) }
    foreach ($e in $Err) { $lines += ('[Console]::Error.WriteLine(''{0}'')' -f $e.Replace("'", "''")) }
    $lines += "exit $Exit"
    [IO.File]::WriteAllLines($path, [string[]]$lines, $utf8)
    [pscustomobject]@{ Path = $path; Marker = $marker }
}
function Invoke-GateWrapper {
    param([string]$Wrapper, $Stub, [bool]$Native, [bool]$Installed, [bool]$Artifacts = $true)
    $artifactDir = Join-Path $work ('artifacts-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    [void](New-Item -ItemType Directory -Path $artifactDir)
    $environment = @{
        VERIFY_ARTIFACTS_DIR = $(if ($Artifacts) { $artifactDir } else { $null })
        PFI_GATE_NATIVE_HARNESS = $(if ($Native) { 'allow' } else { $null })
        PFI_GATE_INSTALLED_COM = $(if ($Installed) { 'allow' } else { $null })
        PFI_GATE_NATIVE_RECLASSIFIED = $null
    }
    $launch = Invoke-PfiNativeProcess -FilePath $windowsPowerShell -TimeoutSeconds 120 -Environment $environment -ArgumentList @(
        '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot $Wrapper), '-RunnerScript', $Stub.Path)
    [pscustomobject]@{ Exit = $launch.ExitCode; Launch = $launch; Invoked = (Test-Path -LiteralPath $Stub.Marker)
        Marker = $(if (Test-Path -LiteralPath $Stub.Marker) { [IO.File]::ReadAllText($Stub.Marker).Trim() } else { '' }); ArtifactDir = $artifactDir }
}
$denial = "Program 'SelectionBrokerHarness.x64.exe' failed to run: Access is denied"
$line = { param($p, $s) Format-PfiNativeLine -Kind 'RESULT' -Fields ([ordered]@{ platform = $p; mode = 'focused'; status = $s; exit = '0' }) -Detail 'stub' }
$build = { param($p, $s) Format-PfiNativeLine -Kind 'BUILD' -Fields ([ordered]@{ platform = $p; status = $s; cache = 'hit'; sha256 = ('a' * 64) }) -Detail 'stub' }
$installedLine = { param($s) Format-PfiNativeLine -Kind 'RESULT' -Fields ([ordered]@{ platform = 'x64'; mode = 'installed'; status = $s; exit = '0' }) -Detail 'stub' }

$wrapperCases = @(
    @{ Name = 'c-0002 default: builds only, withheld'; Wrapper = 'Invoke-NativeHarnessCheck.ps1'; Native = $false; Installed = $false
        Stub = (New-StubRunner 'n-default' -Out @((& $build 'x64' 'READY'), (& $build 'x86' 'READY'))); Exit = 3; Invoked = $true; Marker = 'BuildOnly=True' },
    @{ Name = 'c-0002 default: harness does not compile'; Wrapper = 'Invoke-NativeHarnessCheck.ps1'; Native = $false; Installed = $false
        Stub = (New-StubRunner 'n-buildfail' -Out @((& $build 'x64' 'FAIL'), (& $build 'x86' 'READY')) -Exit 1); Exit = 1; Invoked = $true },
    @{ Name = 'c-0002 opt-in: stderr denial with BLOCKED line'; Wrapper = 'Invoke-NativeHarnessCheck.ps1'; Native = $true; Installed = $false
        Stub = (New-StubRunner 'n-denied' -Out @((& $line 'x64' 'BLOCKED_BY_ENDPOINT_SECURITY')) -Err @($denial) -Exit 3); Exit = 3; Invoked = $true; Marker = 'BuildOnly=False' },
    @{ Name = 'c-0002 opt-in: stderr noise, exit 0, no evidence'; Wrapper = 'Invoke-NativeHarnessCheck.ps1'; Native = $true; Installed = $false
        Stub = (New-StubRunner 'n-noevidence' -Err @('warning text')); Exit = 1; Invoked = $true },
    @{ Name = 'c-0002 opt-in: both PASS'; Wrapper = 'Invoke-NativeHarnessCheck.ps1'; Native = $true; Installed = $false
        Stub = (New-StubRunner 'n-pass' -Out @((& $line 'x64' 'PASS'), (& $line 'x86' 'PASS')) -Err @('benign stderr')); Exit = 0; Invoked = $true },
    @{ Name = 'c-0002 opt-in: crash'; Wrapper = 'Invoke-NativeHarnessCheck.ps1'; Native = $true; Installed = $false
        Stub = (New-StubRunner 'n-crash' -Out @((& $line 'x64' 'CRASH'), (& $line 'x86' 'PASS')) -Exit 5); Exit = 5; Invoked = $true },
    @{ Name = 'c-0002 opt-in: old runner shape (throw, no lines)'; Wrapper = 'Invoke-NativeHarnessCheck.ps1'; Native = $true; Installed = $false
        Stub = (New-StubRunner 'n-oldshape' -Err @($denial) -Exit 1); Exit = 3; Invoked = $true },
    @{ Name = 'c-0002 without VERIFY_ARTIFACTS_DIR'; Wrapper = 'Invoke-NativeHarnessCheck.ps1'; Native = $true; Installed = $false; NoArtifacts = $true
        Stub = (New-StubRunner 'n-noartifacts' -Out @((& $line 'x64' 'PASS'), (& $line 'x86' 'PASS'))); Exit = 2; Invoked = $false },
    @{ Name = 'c-0004 without installed opt-in is NOT RUN'; Wrapper = 'Invoke-InstalledComCheck.ps1'; Native = $true; Installed = $false
        Stub = (New-StubRunner 'i-noinstalled' -Out @((& $installedLine 'PASS'))); Exit = 4; Invoked = $false },
    @{ Name = 'c-0004 without native opt-in is withheld'; Wrapper = 'Invoke-InstalledComCheck.ps1'; Native = $false; Installed = $true
        Stub = (New-StubRunner 'i-nonative' -Out @((& $installedLine 'PASS'))); Exit = 3; Invoked = $false },
    @{ Name = 'c-0004 old runner shape: stderr denial, exit 1 (2026-11-16 defect)'; Wrapper = 'Invoke-InstalledComCheck.ps1'; Native = $true; Installed = $true
        Stub = (New-StubRunner 'i-denied' -Err @("Program 'SelectionBrokerHarness.exe' failed to run: Access is denied") -Exit 1); Exit = 3; Invoked = $true },
    @{ Name = 'c-0004 stderr noise, exit 0, no evidence'; Wrapper = 'Invoke-InstalledComCheck.ps1'; Native = $true; Installed = $true
        Stub = (New-StubRunner 'i-noevidence' -Err @('warning text')); Exit = 1; Invoked = $true },
    @{ Name = 'c-0004 PASS'; Wrapper = 'Invoke-InstalledComCheck.ps1'; Native = $true; Installed = $true
        Stub = (New-StubRunner 'i-pass' -Out @((& $installedLine 'PASS')) -Err @('benign stderr')); Exit = 0; Invoked = $true },
    @{ Name = 'c-0004 assertion failure'; Wrapper = 'Invoke-InstalledComCheck.ps1'; Native = $true; Installed = $true
        Stub = (New-StubRunner 'i-fail' -Out @((& $installedLine 'FAIL')) -Exit 1); Exit = 1; Invoked = $true },
    @{ Name = 'c-0004 without VERIFY_ARTIFACTS_DIR'; Wrapper = 'Invoke-InstalledComCheck.ps1'; Native = $true; Installed = $true; NoArtifacts = $true
        Stub = (New-StubRunner 'i-noartifacts' -Out @((& $installedLine 'PASS'))); Exit = 2; Invoked = $false }
)
foreach ($case in $wrapperCases) {
    $run = Invoke-GateWrapper -Wrapper $case.Wrapper -Stub $case.Stub -Native $case.Native -Installed $case.Installed -Artifacts (-not $case.NoArtifacts)
    Assert-Equal $case.Exit $run.Exit ("{0}: exit {1}" -f $case.Name, $case.Exit)
    Assert-Equal $case.Invoked $run.Invoked ("{0}: runner {1}" -f $case.Name, $(if ($case.Invoked) { 'invoked' } else { 'not invoked' }))
    if ($case.Marker) { Assert-Equal $case.Marker $run.Marker ("{0}: runner mode {1}" -f $case.Name, $case.Marker) }
    if ($case.Name -eq 'c-0002 opt-in: both PASS') {
        Assert-True (Test-Path -LiteralPath (Join-Path $run.ArtifactDir 'native-harness-evidence.json')) 'c-0002 records machine-readable evidence'
    }
}

Write-Host '5. Harness build cache (disposable cache root; compile only, nothing executed)'
$cacheRoot = Join-Path $work 'cache'
$source = Join-Path $repoRoot 'files\tests\SelectionBrokerHarness.cs'
$broker64 = Join-Path $repoRoot 'scripts\Windows\SelectionHandler\PortableFolderIcons.SelectionBroker.x64.exe'
$broker86 = Join-Path $repoRoot 'scripts\Windows\SelectionHandler\PortableFolderIcons.SelectionBroker.x86.exe'

$inputsA = Get-PfiNativeHarnessBuildInputs -Platform x64 -BrokerAssembly $broker64 -HarnessSource $source
$inputsB = Get-PfiNativeHarnessBuildInputs -Platform x64 -BrokerAssembly $broker64 -HarnessSource $source
Assert-Equal $inputsA.Fingerprint $inputsB.Fingerprint 'the fingerprint is deterministic for unchanged inputs'
Assert-True ($inputsA.Fingerprint -cmatch '^[a-f0-9]{64}$') 'the fingerprint is a SHA-256'
$inputs86 = Get-PfiNativeHarnessBuildInputs -Platform x86 -BrokerAssembly $broker86 -HarnessSource $source
Assert-True ($inputsA.Fingerprint -cne $inputs86.Fingerprint) 'x64 and x86 have separate identities'
foreach ($field in @('harnessSource.sha256', 'broker.sha256', 'broker.assemblyName', 'compiler.sha256', 'compiler.fileVersion',
        'compilerResponseFile.sha256', 'coreLibrary.sha256', 'platform', 'switches')) {
    $variant = Get-PfiNativeHarnessBuildInputs -Platform x64 -BrokerAssembly $broker64 -HarnessSource $source
    $parts = $field.Split('.')
    if ($parts.Count -eq 1 -and $field -eq 'switches') { $variant.Inputs.switches = @($variant.Inputs.switches) + '/optimize+' }
    elseif ($parts.Count -eq 1) { $variant.Inputs[$field] = 'changed' }
    else { $variant.Inputs[$parts[0]][$parts[1]] = 'changed' }
    Assert-True ((Get-PfiNativeHarnessFingerprint -Inputs $variant.Inputs) -cne $inputsA.Fingerprint) ("changing {0} changes the cache key" -f $field)
}
$mismatch = Get-PfiNativeHarnessBuild -Platform x64 -BrokerAssembly $broker86 -HarnessSource $source -CacheRoot $cacheRoot
Assert-Equal 'FAIL' $mismatch.Status 'an x86 broker reference is refused for an x64 harness'

$first = Get-PfiNativeHarnessBuild -Platform x64 -BrokerAssembly $broker64 -HarnessSource $source -CacheRoot $cacheRoot
Assert-Equal 'READY' $first.Status 'first x64 build is ready'
Assert-Equal $false $first.CacheHit 'first x64 build is a cache miss'
Assert-Equal $true $first.Compiled 'first x64 build compiled'
Assert-True (Test-Path -LiteralPath $first.Executable -PathType Leaf) 'the built executable exists'
Assert-Equal '0x8664' $first.Machine 'the x64 build is an x64 PE'
Assert-Equal (Get-PfiNativeFileSha256 $first.Executable) $first.Sha256 'the recorded SHA-256 matches the file'
Assert-True ($first.Executable.StartsWith($cacheRoot + '\', [StringComparison]::OrdinalIgnoreCase)) 'the build lives under the cache root'
$firstWrite = (Get-Item -LiteralPath $first.Executable).LastWriteTimeUtc

$second = Get-PfiNativeHarnessBuild -Platform x64 -BrokerAssembly $broker64 -HarnessSource $source -CacheRoot $cacheRoot
Assert-Equal $true $second.CacheHit 'unchanged inputs are a cache hit'
Assert-Equal $false $second.Compiled 'a cache hit does not recompile'
Assert-Equal $first.Sha256 $second.Sha256 'a cache hit returns the same binary identity'
Assert-Equal $first.Executable $second.Executable 'a cache hit returns the same stable path'
Assert-Equal $firstWrite (Get-Item -LiteralPath $second.Executable).LastWriteTimeUtc 'a cache hit leaves the binary untouched'

$x86 = Get-PfiNativeHarnessBuild -Platform x86 -BrokerAssembly $broker86 -HarnessSource $source -CacheRoot $cacheRoot
Assert-Equal 'READY' $x86.Status 'x86 build is ready'
Assert-Equal '0x014C' $x86.Machine 'the x86 build is an x86 PE'
Assert-True ($x86.Directory -cne $first.Directory) 'x86 and x64 builds use separate cache entries'

$changedSource = Join-Path $work 'SelectionBrokerHarness.cs'
[IO.File]::WriteAllText($changedSource, [IO.File]::ReadAllText($source) + "`r`n// cache invalidation test`r`n", $utf8)
$changed = Get-PfiNativeHarnessBuild -Platform x64 -BrokerAssembly $broker64 -HarnessSource $changedSource -CacheRoot $cacheRoot
Assert-Equal $false $changed.CacheHit 'a changed harness source is a cache miss'
Assert-True ($changed.Fingerprint -cne $first.Fingerprint) 'a changed source has a new fingerprint'
Assert-True ($changed.Directory -cne $first.Directory) 'a changed source builds into a new entry'
$reverted = Get-PfiNativeHarnessBuild -Platform x64 -BrokerAssembly $broker64 -HarnessSource $source -CacheRoot $cacheRoot
Assert-Equal $true $reverted.CacheHit 'reverting the inputs reuses the earlier build'
Assert-Equal $first.Sha256 $reverted.Sha256 'the earlier build identity is unchanged'

$tampered = [IO.File]::ReadAllBytes($first.Executable) + [byte]0
[IO.File]::WriteAllBytes($first.Executable, $tampered)
$afterTamper = Get-PfiNativeHarnessBuild -Platform x64 -BrokerAssembly $broker64 -HarnessSource $source -CacheRoot $cacheRoot
Assert-Equal $false $afterTamper.CacheHit 'a tampered cached executable is never reused'
Assert-True ($afterTamper.Reason -match 'SHA-256') 'the miss reason names the hash mismatch'
Assert-Equal (Get-PfiNativeFileSha256 $afterTamper.Executable) $afterTamper.Sha256 'the replacement build matches its record'

[IO.File]::WriteAllText($afterTamper.RecordPath, '{', $utf8)
$afterRecord = Get-PfiNativeHarnessBuild -Platform x64 -BrokerAssembly $broker64 -HarnessSource $source -CacheRoot $cacheRoot
Assert-Equal $false $afterRecord.CacheHit 'a corrupt build record is never trusted'
Assert-Equal 'READY' $afterRecord.Status 'a corrupt record is replaced by a fresh build'

$badSource = Join-Path $work 'Broken.cs'
[IO.File]::WriteAllText($badSource, 'this is not C#', $utf8)
$broken = Get-PfiNativeHarnessBuild -Platform x64 -BrokerAssembly $broker64 -HarnessSource $badSource -CacheRoot $cacheRoot
Assert-Equal 'FAIL' $broken.Status 'a compile error is FAIL'
Assert-True ([string]::IsNullOrEmpty($broken.Executable) -or -not (Test-Path -LiteralPath $broken.Executable)) 'a failed compile leaves no cached executable'
Assert-Equal 0 @(Get-ChildItem -LiteralPath (Join-Path $cacheRoot 'x64') -Directory -Filter '.staging-*').Count 'a failed compile leaves no staging folder'
$noCompiler = Get-PfiNativeHarnessBuild -Platform x64 -BrokerAssembly $broker64 -HarnessSource $source -CacheRoot $cacheRoot -CompilerPath (Join-Path $work 'csc-missing.exe')
Assert-Equal 'BLOCKED' $noCompiler.Status 'a missing compiler is BLOCKED'

$events = @(Get-Content -LiteralPath (Join-Path $cacheRoot 'cache-events.jsonl') | ForEach-Object { $_ | ConvertFrom-Json })
Assert-True (@($events | Where-Object { $_.result -eq 'hit' }).Count -ge 2) 'cache hits are recorded'
Assert-True (@($events | Where-Object { $_.result -eq 'miss' }).Count -ge 3) 'cache misses are recorded with reasons'
Assert-Equal $false (Test-Path -LiteralPath (Join-Path $cacheRoot 'launch-history.jsonl')) 'building never launches a harness'

Write-Host '6. Launch guard for blocked binaries'
$guardRoot = Join-Path $work 'guard'
[void](New-Item -ItemType Directory -Path $guardRoot)
$blockedHash = 'b' * 64
$otherHash = 'c' * 64
Add-PfiNativeLaunchRecord -CacheRoot $guardRoot -Record ([ordered]@{ platform = 'x64'; mode = 'focused'; sha256 = $blockedHash; status = 'BLOCKED_BY_ENDPOINT_SECURITY'; exit = '' })
$savedReclassified = $env:PFI_GATE_NATIVE_RECLASSIFIED
try {
    $env:PFI_GATE_NATIVE_RECLASSIFIED = $null
    Assert-Equal $false (Get-PfiNativeLaunchPermission -CacheRoot $guardRoot -Sha256 $blockedHash).Permitted 'a hash recorded as blocked is not launched again'
    Assert-True ((Get-PfiNativeLaunchPermission -CacheRoot $guardRoot -Sha256 $blockedHash).Reason -match 'PFI_GATE_NATIVE_RECLASSIFIED') 'the refusal says how to acknowledge a reclassification'
    Assert-Equal $true (Get-PfiNativeLaunchPermission -CacheRoot $guardRoot -Sha256 $otherHash).Permitted 'an unrelated hash is not affected'
    $env:PFI_GATE_NATIVE_RECLASSIFIED = $otherHash + ',' + $blockedHash
    Assert-Equal $true (Get-PfiNativeLaunchPermission -CacheRoot $guardRoot -Sha256 $blockedHash).Permitted 'an acknowledged reclassification of that exact hash permits one launch'
    $env:PFI_GATE_NATIVE_RECLASSIFIED = $null
    Add-PfiNativeLaunchRecord -CacheRoot $guardRoot -Record ([ordered]@{ platform = 'x64'; mode = 'focused'; sha256 = $blockedHash; status = 'PASS'; exit = '0' })
    Assert-Equal $true (Get-PfiNativeLaunchPermission -CacheRoot $guardRoot -Sha256 $blockedHash).Permitted 'a later executed result supersedes the block'
}
finally { $env:PFI_GATE_NATIVE_RECLASSIFIED = $savedReclassified }

Write-Host '7. Default launch authorization for every verification entrypoint'
$savedNative = $env:PFI_GATE_NATIVE_HARNESS
try {
    $authorizationCases = @(
        @{ Name = 'no switch, no environment opt-in'; Env = $null; Allow = $false; Skip = $false; Expected = $false },
        @{ Name = 'PFI_GATE_NATIVE_HARNESS=allow'; Env = 'allow'; Allow = $false; Skip = $false; Expected = $true },
        @{ Name = 'PFI_GATE_NATIVE_HARNESS=ALLOW (same rule as the gate wrappers)'; Env = 'ALLOW'; Allow = $false; Skip = $false; Expected = $true },
        @{ Name = 'PFI_GATE_NATIVE_HARNESS=yes'; Env = 'yes'; Allow = $false; Skip = $false; Expected = $false },
        @{ Name = 'PFI_GATE_NATIVE_HARNESS with trailing space'; Env = 'allow '; Allow = $false; Skip = $false; Expected = $false },
        @{ Name = '-AllowNativeHarness'; Env = $null; Allow = $true; Skip = $false; Expected = $true },
        @{ Name = '-SkipNativeHarness overrides the environment opt-in'; Env = 'allow'; Allow = $false; Skip = $true; Expected = $false },
        @{ Name = '-SkipNativeHarness overrides -AllowNativeHarness'; Env = $null; Allow = $true; Skip = $true; Expected = $false }
    )
    foreach ($case in $authorizationCases) {
        $env:PFI_GATE_NATIVE_HARNESS = $case.Env
        Assert-Equal $case.Expected (Test-PfiNativeLaunchAuthorized -Allow:$case.Allow -Skip:$case.Skip) ("launch authorization: {0}" -f $case.Name)
    }
}
finally { $env:PFI_GATE_NATIVE_HARNESS = $savedNative }

# Both direct entrypoints must default to withholding: they expose -AllowNativeHarness and the suite decides through
# Test-PfiNativeLaunchAuthorized (the executed default path is also guarded in every gate run by c-0001 and c-0006).
foreach ($entry in @(@{ Path = 'files\tests\Invoke-Tests.ps1'; MustCall = $true }, @{ Path = 'scripts\verify.ps1'; MustCall = $false })) {
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot $entry.Path), [ref]$tokens, [ref]$errors)
    $parameters = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
    Assert-True ($parameters -contains 'AllowNativeHarness') ("{0} exposes an explicit -AllowNativeHarness" -f $entry.Path)
    Assert-True ($parameters -contains 'SkipNativeHarness') ("{0} still accepts -SkipNativeHarness" -f $entry.Path)
    $calls = @($ast.FindAll({ param($node) $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Test-PfiNativeLaunchAuthorized' }, $true))
    if ($entry.MustCall) { Assert-True ($calls.Count -ge 1) ("{0} decides launches with Test-PfiNativeLaunchAuthorized" -f $entry.Path) }
    else {
        $text = [IO.File]::ReadAllText((Join-Path $repoRoot $entry.Path))
        Assert-True ($text -match "'-AllowNativeHarness'") ("{0} forwards only an explicit -AllowNativeHarness to the suite" -f $entry.Path)
    }
}

Write-Host ('Native infrastructure: {0} passed, {1} failed' -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
exit 0
