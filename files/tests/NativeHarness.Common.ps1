# Developer-only helpers for the compiled C# selection-broker test harness. Not part of the installed runtime.
#
# Used by files\tests\Invoke-Tests.ps1, Invoke-SelectionBrokerTests.ps1, Invoke-InstalledSelectionBrokerTests.ps1 and
# the gate wrappers for c-0002/c-0004. Windows PowerShell 5.1.
#
# Why this exists (2026-11-16): the inbox .NET Framework compiler is not deterministic, so rebuilding the harness on
# every run produced a new PE timestamp, MVID and SHA-256 each time, and endpoint security classified each build as a
# new unknown program. The harness is now built once per set of build inputs and reused from an ignored cache while
# those inputs are unchanged. A cached build is NOT a security approval: only an executed run establishes a result.
#
# Outcome statuses: PASS, FAIL (assertion or check failure), CRASH (abnormal termination, not an assertion verdict),
# BLOCKED_BY_ENDPOINT_SECURITY (the OS refused the launch), BLOCKED (a prerequisite is missing, or a timeout),
# NOT RUN (an opt-in was not given). Only PASS is a pass.
# Dot-sourced into callers, so it deliberately sets no StrictMode or preference variables.

$script:PfiNativeCacheSchema = 'pfi-native-harness-cache/1'
$script:PfiNativeExitCodes = @{ 'PASS' = 0; 'FAIL' = 1; 'BLOCKED' = 2; 'BLOCKED_BY_ENDPOINT_SECURITY' = 3; 'NOT RUN' = 4; 'CRASH' = 5 }
# Win32 errors from CreateProcess that mean the launch itself was refused by policy or a security product:
# ERROR_ACCESS_DENIED, ERROR_VIRUS_INFECTED, ERROR_VIRUS_DELETED, ERROR_ACCESS_DISABLED_BY_POLICY,
# ERROR_SYSTEM_INTEGRITY_POLICY_VIOLATION.
$script:PfiNativeSecurityStartErrors = @(5, 225, 226, 1260, 4551)
$script:PfiClrUnhandledException = -532462766  # 0xE0434352

function Test-PfiNativeLaunchAuthorized {
    # Compiled test executables are launched only with explicit authorization for the run: -AllowNativeHarness on the
    # entrypoint, or PFI_GATE_NATIVE_HARNESS=allow (the same rule as the gate wrappers). -SkipNativeHarness always
    # withholds. Without authorization the harness may be built or reused, but never launched.
    param([switch]$Allow, [switch]$Skip)
    if ($Skip) { return $false }
    return ([bool]$Allow -or ([string]$env:PFI_GATE_NATIVE_HARNESS -eq 'allow'))
}

function Get-PfiNativeFileSha256 {
    param([Parameter(Mandatory = $true)][string]$LiteralPath)
    $stream = [IO.File]::Open($LiteralPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose(); $stream.Dispose() }
}

function Get-PfiNativeTextSha256 {
    param([Parameter(Mandatory = $true)][string]$Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash((New-Object Text.UTF8Encoding($false)).GetBytes($Text)))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-PfiNativePeInfo {
    # Machine type and link timestamp from the PE header; $null when the file is not a PE image.
    param([Parameter(Mandatory = $true)][string]$LiteralPath)
    $bytes = [IO.File]::ReadAllBytes($LiteralPath)
    if ($bytes.Length -lt 512 -or $bytes[0] -ne 0x4D -or $bytes[1] -ne 0x5A) { return $null }
    $pe = [BitConverter]::ToInt32($bytes, 0x3C)
    if ($pe -lt 0 -or ($pe + 12) -ge $bytes.Length -or $bytes[$pe] -ne 0x50 -or $bytes[$pe + 1] -ne 0x45) { return $null }
    $stamp = [BitConverter]::ToUInt32($bytes, $pe + 8)
    return [pscustomobject]@{
        Machine = ('0x{0:X4}' -f [BitConverter]::ToUInt16($bytes, $pe + 4))
        TimeDateStampUtc = ([DateTime]'1970-01-01Z').ToUniversalTime().AddSeconds($stamp).ToString('o')
        Size = $bytes.Length
    }
}

function Get-PfiNativeHarnessCacheRoot {
    param([Parameter(Mandatory = $true)][string]$RepoRoot)
    return (Join-Path $RepoRoot 'files\dev-work\verification-gate\cache\native-harness')
}

function ConvertTo-PfiCanonicalText {
    # Stable text for hashing: one "path=value" line per leaf, in the dictionaries' insertion order.
    param($Value, [string]$Prefix = '')
    $lines = New-Object Collections.Generic.List[string]
    if ($Value -is [Collections.IDictionary]) {
        foreach ($key in $Value.Keys) {
            $name = if ($Prefix) { $Prefix + '.' + $key } else { [string]$key }
            foreach ($line in (ConvertTo-PfiCanonicalText -Value $Value[$key] -Prefix $name)) { $lines.Add($line) }
        }
    }
    elseif ($Value -is [Array]) {
        for ($i = 0; $i -lt $Value.Count; $i++) {
            foreach ($line in (ConvertTo-PfiCanonicalText -Value $Value[$i] -Prefix ($Prefix + '[' + $i + ']'))) { $lines.Add($line) }
        }
    }
    else { $lines.Add($Prefix + '=' + [string]$Value) }
    return , $lines.ToArray()
}

function Get-PfiNativeHarnessFingerprint {
    param([Parameter(Mandatory = $true)][Collections.IDictionary]$Inputs)
    return (Get-PfiNativeTextSha256 -Text ((ConvertTo-PfiCanonicalText -Value $Inputs) -join "`n"))
}

function Get-PfiNativeHarnessBuildInputs {
    # Every input that can change the compiled harness: source, referenced broker (bytes and identity), compiler
    # (bytes and version), its default response file, the core library it compiles against, switches and target.
    param(
        [Parameter(Mandatory = $true)][ValidateSet('x64', 'x86')][string]$Platform,
        [Parameter(Mandatory = $true)][string]$BrokerAssembly,
        [Parameter(Mandatory = $true)][string]$HarnessSource,
        [string]$CompilerPath
    )
    $framework = if ($Platform -eq 'x64') { 'Framework64' } else { 'Framework' }
    $frameworkRelative = 'Microsoft.NET\' + $framework + '\v4.0.30319'
    if ([string]::IsNullOrWhiteSpace($CompilerPath)) { $CompilerPath = Join-Path $env:SystemRoot ($frameworkRelative + '\csc.exe') }
    $frameworkDirectory = Join-Path $env:SystemRoot $frameworkRelative
    $problems = New-Object Collections.Generic.List[string]
    $status = 'READY'
    if (-not (Test-Path -LiteralPath $CompilerPath -PathType Leaf)) { $problems.Add("compiler not found: $CompilerPath"); $status = 'BLOCKED' }
    if (-not (Test-Path -LiteralPath $HarnessSource -PathType Leaf)) { $problems.Add("harness source not found: $HarnessSource"); $status = 'FAIL' }
    if (-not (Test-Path -LiteralPath $BrokerAssembly -PathType Leaf)) { $problems.Add("broker assembly not found: $BrokerAssembly"); $status = 'FAIL' }
    if ($problems.Count -gt 0) {
        return [pscustomobject]@{ Status = $status; Detail = ($problems -join '; '); Inputs = $null; Fingerprint = $null
            CompilerPath = $CompilerPath; ReferenceFileName = $null; OutputFileName = $null }
    }

    $expectedMachine = if ($Platform -eq 'x64') { '0x8664' } else { '0x014C' }
    $brokerPe = Get-PfiNativePeInfo -LiteralPath $BrokerAssembly
    try { $brokerName = [Reflection.AssemblyName]::GetAssemblyName($BrokerAssembly) } catch { $brokerName = $null }
    if ($null -eq $brokerPe -or $null -eq $brokerName -or $brokerPe.Machine -cne $expectedMachine) {
        return [pscustomobject]@{ Status = 'FAIL'; Detail = "broker assembly is not a managed $Platform image: $BrokerAssembly"
            Inputs = $null; Fingerprint = $null; CompilerPath = $CompilerPath; ReferenceFileName = $null; OutputFileName = $null }
    }
    # The harness loads the broker by assembly name from its own folder, so the reference copy is named after it.
    $referenceFileName = $brokerName.Name + '.exe'
    $outputFileName = 'SelectionBrokerHarness.' + $Platform + '.exe'
    $responseFile = Join-Path $frameworkDirectory 'csc.rsp'
    $coreLibrary = Join-Path $frameworkDirectory 'mscorlib.dll'
    $inputs = [ordered]@{
        schema = $script:PfiNativeCacheSchema
        platform = $Platform
        harnessSource = [ordered]@{ fileName = 'SelectionBrokerHarness.cs'; sha256 = (Get-PfiNativeFileSha256 $HarnessSource) }
        broker = [ordered]@{ referenceFileName = $referenceFileName; assemblyName = $brokerName.FullName; machine = $brokerPe.Machine
            sha256 = (Get-PfiNativeFileSha256 $BrokerAssembly) }
        compiler = [ordered]@{ relativePath = ($frameworkRelative + '\csc.exe'); fileVersion = [Diagnostics.FileVersionInfo]::GetVersionInfo($CompilerPath).FileVersion
            sha256 = (Get-PfiNativeFileSha256 $CompilerPath) }
        compilerResponseFile = [ordered]@{ relativePath = ($frameworkRelative + '\csc.rsp')
            sha256 = $(if (Test-Path -LiteralPath $responseFile -PathType Leaf) { Get-PfiNativeFileSha256 $responseFile } else { 'absent' }) }
        coreLibrary = [ordered]@{ relativePath = ($frameworkRelative + '\mscorlib.dll')
            sha256 = $(if (Test-Path -LiteralPath $coreLibrary -PathType Leaf) { Get-PfiNativeFileSha256 $coreLibrary } else { 'absent' }) }
        switches = @('/nologo', '/target:exe', ('/platform:' + $Platform), ('/reference:' + $referenceFileName), ('/out:' + $outputFileName), 'SelectionBrokerHarness.cs')
    }
    return [pscustomobject]@{ Status = 'READY'; Detail = ''; Inputs = $inputs; Fingerprint = (Get-PfiNativeHarnessFingerprint -Inputs $inputs)
        CompilerPath = $CompilerPath; ReferenceFileName = $referenceFileName; OutputFileName = $outputFileName }
}

function Test-PfiNativePathUnder {
    param([string]$Path, [string]$Root)
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $base = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    return $full.StartsWith($base, [StringComparison]::OrdinalIgnoreCase)
}

function Add-PfiNativeJsonLine {
    param([string]$LiteralPath, [Collections.IDictionary]$Record)
    $Record['timeUtc'] = [DateTime]::UtcNow.ToString('o')
    [IO.File]::AppendAllText($LiteralPath, (($Record | ConvertTo-Json -Compress -Depth 6) + "`r`n"), (New-Object Text.UTF8Encoding($false)))
}

function Read-PfiNativeJsonLines {
    param([string]$LiteralPath)
    $records = New-Object Collections.Generic.List[object]
    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) { return , $records.ToArray() }
    foreach ($line in [IO.File]::ReadAllLines($LiteralPath)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $records.Add(($line | ConvertFrom-Json)) } catch { }
    }
    return , $records.ToArray()
}

function Test-PfiNativeCachedBuild {
    # Returns '' when the entry can be reused, otherwise the reason it cannot.
    param([string]$Directory, [string]$Fingerprint, $Request)
    $recordPath = Join-Path $Directory 'build-record.json'
    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) { return 'no cached build for these inputs' }
    try { $record = [IO.File]::ReadAllText($recordPath) | ConvertFrom-Json } catch { return 'build record missing or unreadable' }
    try {
        if ([string]$record.schema -cne $script:PfiNativeCacheSchema) { return 'build record schema differs' }
        if ([string]$record.fingerprint -cne $Fingerprint) { return 'build record fingerprint differs' }
        $exe = Join-Path $Directory $Request.OutputFileName
        if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { return 'cached executable missing' }
        if ((Get-PfiNativeFileSha256 $exe) -cne [string]$record.artifact.sha256) { return 'cached executable SHA-256 differs from its build record' }
        $pe = Get-PfiNativePeInfo -LiteralPath $exe
        $expectedMachine = if ($Request.Inputs.platform -eq 'x64') { '0x8664' } else { '0x014C' }
        if ($null -eq $pe -or $pe.Machine -cne $expectedMachine) { return 'cached executable machine type differs' }
        $reference = Join-Path $Directory $Request.ReferenceFileName
        if (-not (Test-Path -LiteralPath $reference -PathType Leaf) -or (Get-PfiNativeFileSha256 $reference) -cne $Request.Inputs.broker.sha256) {
            return 'cached broker reference missing or changed'
        }
        $sourceCopy = Join-Path $Directory 'SelectionBrokerHarness.cs'
        if (-not (Test-Path -LiteralPath $sourceCopy -PathType Leaf) -or (Get-PfiNativeFileSha256 $sourceCopy) -cne $Request.Inputs.harnessSource.sha256) {
            return 'cached source copy missing or changed'
        }
    }
    catch { return ('build record invalid: ' + $_.Exception.Message) }
    return ''
}

function Get-PfiNativeHarnessBuild {
    # Reuse the cached harness for these exact inputs, or build it once. Never launches the harness.
    param(
        [Parameter(Mandatory = $true)][ValidateSet('x64', 'x86')][string]$Platform,
        [Parameter(Mandatory = $true)][string]$BrokerAssembly,
        [Parameter(Mandatory = $true)][string]$HarnessSource,
        [Parameter(Mandatory = $true)][string]$CacheRoot,
        [string]$CompilerPath
    )
    $result = [ordered]@{ Platform = $Platform; Status = 'FAIL'; Detail = ''; CacheHit = $false; Reason = ''; Compiled = $false
        Fingerprint = $null; Directory = $null; Executable = $null; Sha256 = $null; Size = $null; Machine = $null
        PeTimeDateStampUtc = $null; RecordPath = $null; CompilerExitCode = $null; CompilerOutput = '' }
    $request = Get-PfiNativeHarnessBuildInputs -Platform $Platform -BrokerAssembly $BrokerAssembly -HarnessSource $HarnessSource -CompilerPath $CompilerPath
    if ($request.Status -ne 'READY') { $result.Status = $request.Status; $result.Detail = $request.Detail; return [pscustomobject]$result }

    $platformRoot = Join-Path $CacheRoot $Platform
    [void](New-Item -ItemType Directory -Path $platformRoot -Force)
    $directory = Join-Path $platformRoot $request.Fingerprint.Substring(0, 16)
    $result.Fingerprint = $request.Fingerprint
    $result.Directory = $directory
    $result.RecordPath = Join-Path $directory 'build-record.json'
    $events = Join-Path $CacheRoot 'cache-events.jsonl'

    $reason = Test-PfiNativeCachedBuild -Directory $directory -Fingerprint $request.Fingerprint -Request $request
    if ($reason -eq '') {
        $record = [IO.File]::ReadAllText($result.RecordPath) | ConvertFrom-Json
        $result.Status = 'READY'; $result.CacheHit = $true; $result.Reason = 'inputs unchanged; verified cached build reused'
        $result.Executable = Join-Path $directory $request.OutputFileName
        $result.Sha256 = [string]$record.artifact.sha256; $result.Size = [int64]$record.artifact.size
        $result.Machine = [string]$record.artifact.machine; $result.PeTimeDateStampUtc = [string]$record.artifact.peTimeDateStampUtc
        Add-PfiNativeJsonLine $events ([ordered]@{ platform = $Platform; result = 'hit'; reason = $result.Reason; fingerprint = $request.Fingerprint; sha256 = $result.Sha256 })
        return [pscustomobject]$result
    }
    $result.Reason = $reason

    # Build in a private staging folder; publish it only after it has been verified.
    $staging = Join-Path $platformRoot ('.staging-' + [guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $staging)
    try {
        Copy-Item -LiteralPath $BrokerAssembly -Destination (Join-Path $staging $request.ReferenceFileName)
        Copy-Item -LiteralPath $HarnessSource -Destination (Join-Path $staging 'SelectionBrokerHarness.cs')
        $compile = Invoke-PfiNativeProcess -FilePath $request.CompilerPath -ArgumentList $request.Inputs.switches -WorkingDirectory $staging -TimeoutSeconds 300
        $result.CompilerExitCode = $compile.ExitCode
        $result.CompilerOutput = ($compile.StdOut + $compile.StdErr).Trim()
        $exe = Join-Path $staging $request.OutputFileName
        if (-not $compile.Started) { $result.Status = 'BLOCKED'; $result.Detail = "compiler could not start: $($compile.StartError)" }
        elseif ($compile.TimedOut) { $result.Status = 'BLOCKED'; $result.Detail = 'compiler timed out' }
        elseif ($compile.ExitCode -ne 0) { $result.Status = 'FAIL'; $result.Detail = "compiler exit $($compile.ExitCode): $($result.CompilerOutput)" }
        elseif (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { $result.Status = 'FAIL'; $result.Detail = 'compiler reported success but produced no executable' }
        else {
            $pe = Get-PfiNativePeInfo -LiteralPath $exe
            $expectedMachine = if ($Platform -eq 'x64') { '0x8664' } else { '0x014C' }
            if ($null -eq $pe -or $pe.Machine -cne $expectedMachine) { $result.Status = 'FAIL'; $result.Detail = 'compiled harness has the wrong machine type' }
            else {
                $sha = Get-PfiNativeFileSha256 $exe
                $record = [ordered]@{
                    schema = $script:PfiNativeCacheSchema
                    platform = $Platform
                    fingerprint = $request.Fingerprint
                    inputs = $request.Inputs
                    artifact = [ordered]@{ fileName = $request.OutputFileName; sha256 = $sha; size = $pe.Size; machine = $pe.Machine; peTimeDateStampUtc = $pe.TimeDateStampUtc }
                    compilerExitCode = $compile.ExitCode
                    builtAtUtc = [DateTime]::UtcNow.ToString('o')
                    note = 'Built once for these inputs and reused while they are unchanged. Not a security approval: only an executed run establishes a result.'
                }
                [IO.File]::WriteAllText((Join-Path $staging 'build-record.json'), ($record | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
                if (Test-Path -LiteralPath $directory) {
                    if (-not (Test-PfiNativePathUnder -Path $directory -Root $CacheRoot)) { throw "Refusing to replace a path outside the cache: $directory" }
                    Remove-Item -LiteralPath $directory -Recurse -Force
                }
                Move-Item -LiteralPath $staging -Destination $directory
                $result.Status = 'READY'; $result.Compiled = $true
                $result.Executable = Join-Path $directory $request.OutputFileName
                $result.Sha256 = $sha; $result.Size = $pe.Size; $result.Machine = $pe.Machine; $result.PeTimeDateStampUtc = $pe.TimeDateStampUtc
            }
        }
    }
    finally {
        if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
    }
    Add-PfiNativeJsonLine $events ([ordered]@{ platform = $Platform; result = 'miss'; reason = $reason; status = $result.Status
        fingerprint = $request.Fingerprint; sha256 = $result.Sha256; compiled = $result.Compiled })
    return [pscustomobject]$result
}

function ConvertTo-PfiCommandLineArgument {
    # Quote one argument for CommandLineToArgvW / the MSVC runtime.
    param([AllowEmptyString()][string]$Value)
    if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') { return $Value }
    $builder = New-Object Text.StringBuilder
    [void]$builder.Append('"')
    $backslashes = 0
    foreach ($ch in $Value.ToCharArray()) {
        if ($ch -eq [char]'\') { $backslashes++; continue }
        if ($ch -eq [char]'"') { [void]$builder.Append([char]'\', $backslashes * 2 + 1).Append([char]'"') }
        else { [void]$builder.Append([char]'\', $backslashes).Append($ch) }
        $backslashes = 0
    }
    [void]$builder.Append([char]'\', $backslashes * 2).Append([char]'"')
    return $builder.ToString()
}

function Invoke-PfiNativeProcess {
    # Start a process directly (no shell), capture stdout/stderr without turning stderr into PowerShell errors, and
    # report whether it started, why not, its exit code and whether it timed out. A missing file is never launched.
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [string]$WorkingDirectory,
        [int]$TimeoutSeconds = 300,
        [hashtable]$Environment,
        [string]$StdOutPath,
        [string]$StdErrPath
    )
    $result = [ordered]@{ FilePath = $FilePath; Started = $false; StartErrorCode = $null; StartError = $null; ExitCode = $null
        TimedOut = $false; StdOut = ''; StdErr = ''; DurationSeconds = 0; ProcessId = $null }
    $utf8 = New-Object Text.UTF8Encoding($false)
    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
        $result.StartErrorCode = 2
        $result.StartError = 'The executable does not exist; nothing was launched.'
    }
    else {
        $info = New-Object Diagnostics.ProcessStartInfo
        $info.FileName = $FilePath
        $info.Arguments = (@($ArgumentList | ForEach-Object { ConvertTo-PfiCommandLineArgument $_ }) -join ' ')
        $info.UseShellExecute = $false
        $info.CreateNoWindow = $true
        $info.RedirectStandardOutput = $true
        $info.RedirectStandardError = $true
        if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) { $info.WorkingDirectory = $WorkingDirectory }
        if ($null -ne $Environment) {
            foreach ($key in $Environment.Keys) {
                if ($null -eq $Environment[$key]) { if ($info.EnvironmentVariables.ContainsKey($key)) { $info.EnvironmentVariables.Remove($key) } }
                else { $info.EnvironmentVariables[$key] = [string]$Environment[$key] }
            }
        }
        $process = New-Object Diagnostics.Process
        $process.StartInfo = $info
        $clock = [Diagnostics.Stopwatch]::StartNew()
        $started = $false
        try { $started = $process.Start() }
        catch {
            $exception = $_.Exception
            while ($null -ne $exception -and -not ($exception -is [ComponentModel.Win32Exception])) { $exception = $exception.InnerException }
            if ($null -ne $exception) { $result.StartErrorCode = $exception.NativeErrorCode; $result.StartError = $exception.Message }
            else { $result.StartErrorCode = -1; $result.StartError = $_.Exception.Message }
        }
        if ($started) {
            $result.Started = $true
            $result.ProcessId = $process.Id
            $outTask = $process.StandardOutput.ReadToEndAsync()
            $errTask = $process.StandardError.ReadToEndAsync()
            if ($process.WaitForExit([Math]::Max(1, $TimeoutSeconds) * 1000)) {
                $process.WaitForExit()
                $result.ExitCode = $process.ExitCode
            }
            else {
                $result.TimedOut = $true
                try { $process.Kill() } catch { }
                [void]$process.WaitForExit(10000)
            }
            if ($outTask.Wait(10000)) { $result.StdOut = $outTask.Result }
            if ($errTask.Wait(10000)) { $result.StdErr = $errTask.Result }
        }
        $result.DurationSeconds = [Math]::Round($clock.Elapsed.TotalSeconds, 3)
        $process.Dispose()
    }
    if ($StdOutPath) { [IO.File]::WriteAllText($StdOutPath, [string]$result.StdOut, $utf8) }
    if ($StdErrPath) { [IO.File]::WriteAllText($StdErrPath, [string]$result.StdErr, $utf8) }
    return [pscustomobject]$result
}

function Format-PfiNativeExitCode {
    param($ExitCode)
    if ($null -eq $ExitCode) { return 'none' }
    return ('{0} (0x{1:X8})' -f $ExitCode, [int]$ExitCode)
}

function Get-PfiNativeOutcome {
    # Classify one launch of a compiled test program. PASS needs exit 0 AND the pass line (with a positive count when
    # the pattern captures one); everything else is a non-pass with a reason.
    param([Parameter(Mandatory = $true)]$Launch, [Parameter(Mandatory = $true)][string]$PassPattern)
    $outcome = [ordered]@{ Status = 'FAIL'; Detail = ''; Assertions = $null; ExitCode = $Launch.ExitCode }
    $stdout = [string]$Launch.StdOut
    $stderr = [string]$Launch.StdErr
    if (-not $Launch.Started) {
        $code = $Launch.StartErrorCode
        if ($code -in $script:PfiNativeSecurityStartErrors) {
            $outcome.Status = 'BLOCKED_BY_ENDPOINT_SECURITY'
            $outcome.Detail = "launch refused by the OS (Win32 $code`: $($Launch.StartError)); endpoint security or policy"
        }
        elseif ($code -in @(2, 3)) { $outcome.Status = 'BLOCKED'; $outcome.Detail = "executable missing (Win32 $code); nothing was launched" }
        else { $outcome.Status = 'BLOCKED'; $outcome.Detail = "could not start (Win32 $code`: $($Launch.StartError))" }
        return [pscustomobject]$outcome
    }
    if ($Launch.TimedOut) { $outcome.Status = 'BLOCKED'; $outcome.Detail = 'timed out; the process was stopped'; return [pscustomobject]$outcome }
    if ($null -eq $Launch.ExitCode) { $outcome.Detail = 'exit code unavailable'; return [pscustomobject]$outcome }
    $exit = [int]$Launch.ExitCode
    if ($exit -eq 0) {
        $match = [regex]::Match($stdout, $PassPattern)
        if (-not $match.Success) { $outcome.Detail = 'exit 0 without a pass line: no evidence that the tests ran'; return [pscustomobject]$outcome }
        if ($match.Groups['count'].Success) {
            $outcome.Assertions = [int]$match.Groups['count'].Value
            if ($outcome.Assertions -le 0) { $outcome.Detail = 'pass line reports zero assertions'; return [pscustomobject]$outcome }
        }
        $outcome.Status = 'PASS'
        $outcome.Detail = $(if ($null -ne $outcome.Assertions) { "$($outcome.Assertions) assertions passed" } else { 'pass line present' })
        return [pscustomobject]$outcome
    }
    if ($exit -eq $script:PfiClrUnhandledException) {
        $exceptionMatch = [regex]::Match($stderr, 'Unhandled Exception:\s*(?<type>[\w.`]+):?\s*(?<message>[^\r\n]*)')
        if ($exceptionMatch.Success -and $exceptionMatch.Groups['type'].Value -ceq 'System.InvalidOperationException') {
            # The harness's Assert throws InvalidOperationException: a test verdict, not a crash.
            $outcome.Detail = 'assertion failed: ' + $exceptionMatch.Groups['message'].Value.Trim()
            return [pscustomobject]$outcome
        }
        $outcome.Status = 'CRASH'
        $outcome.Detail = $(if ($exceptionMatch.Success) { 'unhandled ' + $exceptionMatch.Groups['type'].Value + ': ' + $exceptionMatch.Groups['message'].Value.Trim() }
            else { 'unhandled CLR exception (exception type not reported)' }) + ' exit ' + (Format-PfiNativeExitCode $exit)
        return [pscustomobject]$outcome
    }
    if ($exit -lt 0) {
        $outcome.Status = 'CRASH'
        $outcome.Detail = 'abnormal termination, NTSTATUS exit ' + (Format-PfiNativeExitCode $exit)
        return [pscustomobject]$outcome
    }
    $outcome.Detail = 'nonzero exit ' + (Format-PfiNativeExitCode $exit)
    return [pscustomobject]$outcome
}

function Format-PfiNativeLine {
    # One machine-readable line: PFI-NATIVE-<KIND> key=value ... detail=<free text>. Spaces and % in values are escaped.
    param([Parameter(Mandatory = $true)][ValidateSet('RESULT', 'BUILD')][string]$Kind, [Collections.IDictionary]$Fields, [string]$Detail = '')
    $parts = @('PFI-NATIVE-' + $Kind)
    foreach ($key in $Fields.Keys) {
        $value = [string]$Fields[$key]
        if ($value -eq '') { $value = '-' }
        $parts += ($key + '=' + $value.Replace('%', '%25').Replace(' ', '%20'))
    }
    return (($parts -join ' ') + ' detail=' + ($Detail -replace '[\r\n]+', ' '))
}

function ConvertFrom-PfiNativeLine {
    param([Parameter(Mandatory = $true)][ValidateSet('RESULT', 'BUILD')][string]$Kind, [AllowEmptyString()][string]$Text)
    $records = New-Object Collections.Generic.List[object]
    foreach ($match in [regex]::Matches([string]$Text, ('(?m)^\s*PFI-NATIVE-' + $Kind + ' (?<fields>.*?) detail=(?<detail>[^\r\n]*)\r?$'))) {
        $record = @{ detail = $match.Groups['detail'].Value }
        foreach ($token in ($match.Groups['fields'].Value -split ' ')) {
            $index = $token.IndexOf('=')
            if ($index -gt 0) { $record[$token.Substring(0, $index)] = $token.Substring($index + 1).Replace('%20', ' ').Replace('%25', '%') }
        }
        $records.Add($record)
    }
    return , $records.ToArray()
}

function Get-PfiNativeRunnerDenial {
    # A runner that died before reporting (older runners threw on the first denied launch) is still a block, not FAIL.
    param($Runner)
    return ((([string]$Runner.StdOut + ' ' + [string]$Runner.StdErr) -replace '\s+', ' ') -match 'failed to run: ?Access is denied')
}

function New-PfiNativeVerdict {
    param([string]$Status, [string]$Detail)
    return [pscustomobject]@{ Status = $Status; Exit = $script:PfiNativeExitCodes[$Status]; Detail = $Detail }
}

function Resolve-PfiNativeRunnerStart {
    # Verdict when the runner process itself did not complete; $null when it did.
    param($Runner)
    if (-not $Runner.Started) {
        if ($Runner.StartErrorCode -in $script:PfiNativeSecurityStartErrors) { return (New-PfiNativeVerdict 'BLOCKED_BY_ENDPOINT_SECURITY' "runner launch refused (Win32 $($Runner.StartErrorCode))") }
        return (New-PfiNativeVerdict 'BLOCKED' "runner could not start (Win32 $($Runner.StartErrorCode): $($Runner.StartError))")
    }
    if ($Runner.TimedOut) { return (New-PfiNativeVerdict 'BLOCKED' 'runner timed out and was stopped') }
    if ($null -eq $Runner.ExitCode) { return (New-PfiNativeVerdict 'FAIL' 'runner exit code unavailable') }
    return $null
}

function Resolve-PfiNativeCheckResult {
    # Gate verdict for an executed native check. PASS only when the runner exited 0 AND every expected platform (or the
    # expected number of results) reported PASS. Precedence: FAIL > CRASH > BLOCKED_BY_ENDPOINT_SECURITY > BLOCKED.
    param([Parameter(Mandatory = $true)]$Runner, [object[]]$Results = @(), [string[]]$ExpectedPlatforms = @(), [int]$ExpectedCount = 0)
    $start = Resolve-PfiNativeRunnerStart -Runner $Runner
    if ($null -ne $start) { return $start }
    $statuses = @($Results | ForEach-Object { [string]$_.status })
    $summary = (@($Results | ForEach-Object { "$($_.platform)=$($_.status)" }) -join ', ')
    if ($statuses -contains 'FAIL') { return (New-PfiNativeVerdict 'FAIL' "test failure: $summary") }
    if ($statuses -contains 'CRASH') { return (New-PfiNativeVerdict 'CRASH' "test process crashed: $summary") }
    if ($statuses -contains 'BLOCKED_BY_ENDPOINT_SECURITY') { return (New-PfiNativeVerdict 'BLOCKED_BY_ENDPOINT_SECURITY' "launch blocked: $summary") }
    if ($statuses -contains 'BLOCKED') { return (New-PfiNativeVerdict 'BLOCKED' "prerequisite unavailable: $summary") }
    $missing = @($ExpectedPlatforms | Where-Object { $p = $_; @($Results | Where-Object { $_.platform -eq $p -and $_.status -eq 'PASS' }).Count -ne 1 })
    $complete = $missing.Count -eq 0 -and $Results.Count -ge [Math]::Max(1, [Math]::Max($ExpectedCount, $ExpectedPlatforms.Count)) -and
        @($statuses | Where-Object { $_ -ne 'PASS' }).Count -eq 0
    if ($complete -and [int]$Runner.ExitCode -eq 0) { return (New-PfiNativeVerdict 'PASS' "all results PASS: $summary") }
    if (Get-PfiNativeRunnerDenial -Runner $Runner) { return (New-PfiNativeVerdict 'BLOCKED_BY_ENDPOINT_SECURITY' "runner reported a denied launch (runner exit $($Runner.ExitCode))") }
    if ($complete) { return (New-PfiNativeVerdict 'FAIL' "results PASS but runner exit $($Runner.ExitCode): inconsistent") }
    return (New-PfiNativeVerdict 'FAIL' ("no conclusive result (runner exit $($Runner.ExitCode); missing: " + ($missing -join ', ') + "; reported: $summary)"))
}

function Resolve-PfiNativeBuildOnlyResult {
    # Default gate run: the harness is built or reused but not launched, so the best possible result is the withheld
    # BLOCKED_BY_ENDPOINT_SECURITY. A harness that does not build is a FAIL.
    param([Parameter(Mandatory = $true)]$Runner, [object[]]$Builds = @(), [string[]]$ExpectedPlatforms = @('x64', 'x86'))
    $start = Resolve-PfiNativeRunnerStart -Runner $Runner
    if ($null -ne $start) { return $start }
    $summary = (@($Builds | ForEach-Object { "$($_.platform) $($_.status) cache=$($_.cache) sha256=$($_.sha256)" }) -join '; ')
    if (@($Builds | Where-Object { $_.status -eq 'FAIL' }).Count -gt 0) { return (New-PfiNativeVerdict 'FAIL' "harness build failed: $summary") }
    if ([int]$Runner.ExitCode -notin @(0, 2)) { return (New-PfiNativeVerdict 'FAIL' "runner exit $($Runner.ExitCode) before the builds completed: $summary") }
    if (@($Builds | Where-Object { $_.status -eq 'BLOCKED' }).Count -gt 0) { return (New-PfiNativeVerdict 'BLOCKED' "harness build prerequisite missing: $summary") }
    $missing = @($ExpectedPlatforms | Where-Object { $p = $_; @($Builds | Where-Object { $_.platform -eq $p -and $_.status -eq 'READY' }).Count -ne 1 })
    if ($missing.Count -gt 0 -or [int]$Runner.ExitCode -ne 0) { return (New-PfiNativeVerdict 'FAIL' ("missing build evidence for: " + ($missing -join ', '))) }
    return (New-PfiNativeVerdict 'BLOCKED_BY_ENDPOINT_SECURITY' "withheld, not launched (no PFI_GATE_NATIVE_HARNESS=allow); builds ready: $summary")
}

function Add-PfiNativeLaunchRecord {
    param([Parameter(Mandatory = $true)][string]$CacheRoot, [Parameter(Mandatory = $true)][Collections.IDictionary]$Record)
    [void](New-Item -ItemType Directory -Path $CacheRoot -Force)
    Add-PfiNativeJsonLine (Join-Path $CacheRoot 'launch-history.jsonl') $Record
}

function Get-PfiNativeLaunchPermission {
    # A binary whose most recent launch was refused by endpoint security is not launched again until the user states
    # that the security owner reclassified that exact file: PFI_GATE_NATIVE_RECLASSIFIED=<sha256>[,<sha256>...].
    param([Parameter(Mandatory = $true)][string]$CacheRoot, [Parameter(Mandatory = $true)][string]$Sha256)
    $all = Read-PfiNativeJsonLines (Join-Path $CacheRoot 'launch-history.jsonl')
    $history = @($all | Where-Object { [string]$_.sha256 -ceq $Sha256 })
    if ($history.Count -eq 0 -or [string]$history[-1].status -cne 'BLOCKED_BY_ENDPOINT_SECURITY') {
        return [pscustomobject]@{ Permitted = $true; Reason = 'no unresolved block recorded for this binary' }
    }
    $acknowledged = @(([string]$env:PFI_GATE_NATIVE_RECLASSIFIED -split '[,;\s]+') | Where-Object { $_ -ceq $Sha256 })
    if ($acknowledged.Count -gt 0) { return [pscustomobject]@{ Permitted = $true; Reason = 'reclassification of this exact binary acknowledged' } }
    return [pscustomobject]@{ Permitted = $false
        Reason = ("previously blocked by endpoint security at $($history[-1].timeUtc); not re-attempted. After the security owner " +
            "reclassifies this exact file, set PFI_GATE_NATIVE_RECLASSIFIED=$Sha256 for one run.") }
}
