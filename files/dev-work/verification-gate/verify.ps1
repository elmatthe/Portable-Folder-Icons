# Verification gate runner for Generic projects on Windows.
# Contract: .ai/VERIFICATION.md. Needs only Windows PowerShell 5.1 or PowerShell 7: no Python or Node.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File files\dev-work\verification-gate\verify.ps1
#   ... verify.ps1 -Mode focused -Select <check-id>     selected checks
#   ... verify.ps1 -Mode changed                        broadens to all checks
#   ... verify.ps1 -PlatformScope windows               scoped checkpoint
#   ... verify.ps1 -Status                              is the last full run current?
#
# Double-dash spellings also work, so every runner shares one interface.
# Every run writes outputs\<run-id>\ and exits 0 PASS, 1 FAIL, 2 BLOCKED, 130 interrupted.
# Checks are listed in checks.tsv and required functionality in coverage.tsv.
#
# PROJECT ADAPTATION (Portable Folder Icons, 2026-11-16). Copied from the workspace template
# templates/verification/generic (snapshot 2026-11-04, SHA-256 645dff0d...); the template itself is unchanged.
# Every change is marked "PFI:" and explained in GATE.md, section "Portable Folder Icons adaptation":
#   1. The status index lives in outputs\verify-state.json (all generated output stays under outputs\).
#   2. scripts\verify.ps1 is accepted as the project's established verifier (config.toml [verification]).
#   3. Check exit codes: 0 PASS, 1 FAIL, 2 BLOCKED, 3 BLOCKED (BLOCKED_BY_ENDPOINT_SECURITY), 4 NOT RUN (opt-in).

$ErrorActionPreference = 'Stop'
$script:GateDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:ProjectRoot = [IO.Path]::GetFullPath((Join-Path $script:GateDir '..\..\..'))
$script:GateRel = 'files/dev-work/verification-gate'
$script:OutputsDir = Join-Path $script:GateDir 'outputs'
# PFI: keep the status index with the other generated output (template: files\runtime\verify-state.json).
$script:StatePath = Join-Path $script:OutputsDir 'verify-state.json'
$script:ChecksFile = Join-Path $script:GateDir 'checks.tsv'
$script:CoverageFile = Join-Path $script:GateDir 'coverage.tsv'
$script:Utf8 = New-Object Text.UTF8Encoding $false
$script:Help = @'
usage: verify.ps1 [--mode focused|changed|full] [--select ID]... [--platform-scope windows|macos|both] [--setup] [--status]

Run this project's verification gate. See .ai/VERIFICATION.md.
Exit codes: 0 PASS, 1 FAIL, 2 BLOCKED, 130 interrupted.
'@

function Stop-WithUsage([string]$message) {
    [Console]::Error.WriteLine("$($script:Help)`n`nverify.ps1: error: $message")
    exit 2
}

$script:Mode = 'full'
$script:Selected = @()
$script:ScopeArg = $null
$script:Action = 'run'
$index = 0
while ($index -lt $args.Count) {
    $argument = [string]$args[$index]
    switch -Regex ($argument) {
        '^(-h|--help|-help)$' { Write-Output $script:Help; exit 0 }
        '^(--mode|-mode)$' {
            $index++
            if ($index -ge $args.Count) { Stop-WithUsage '--mode needs a value' }
            $script:Mode = [string]$args[$index]
            if ($script:Mode -notin @('focused', 'changed', 'full')) { Stop-WithUsage "invalid mode: $($script:Mode)" }
            break
        }
        '^(--select|-select)$' {
            $index++
            if ($index -ge $args.Count) { Stop-WithUsage '--select needs a value' }
            $script:Selected += [string]$args[$index]
            break
        }
        '^(--platform-scope|-platformscope)$' {
            $index++
            if ($index -ge $args.Count) { Stop-WithUsage '--platform-scope needs a value' }
            $script:ScopeArg = [string]$args[$index]
            if ($script:ScopeArg -notin @('windows', 'macos', 'both')) { Stop-WithUsage "invalid scope: $($script:ScopeArg)" }
            break
        }
        '^(--setup|-setup)$' { $script:Action = 'setup'; break }
        '^(--status|-status)$' { $script:Action = 'status'; break }
        default { Stop-WithUsage "unknown argument: $argument" }
    }
    $index++
}
if ($script:Mode -eq 'focused' -and $script:Selected.Count -eq 0 -and $script:Action -eq 'run') { Stop-WithUsage '--mode focused needs at least one --select' }
if ($script:Selected.Count -gt 0 -and $script:Mode -ne 'focused') { Stop-WithUsage '--select applies only to --mode focused' }

function Get-UtcStamp { return [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ") }
function Write-AtomicFile([string]$path, [string]$text) {
    $tmp = "$path.$PID.$([Guid]::NewGuid().ToString('N').Substring(0, 6)).tmp"
    [IO.File]::WriteAllText($tmp, $text, $script:Utf8)
    for ($attempt = 0; ; $attempt++) {
        try {
            [IO.File]::Copy($tmp, $path, $true)
            [IO.File]::Delete($tmp)
            return
        } catch {
            if ($attempt -ge 9) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue; throw }
            Start-Sleep -Milliseconds (50 * ($attempt + 1))
        }
    }
}
function Invoke-Git([string[]]$arguments) {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return $null }
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = (Get-Command git).Source
    $psi.Arguments = (@('--no-optional-locks') + $arguments | ForEach-Object { ConvertTo-NativeArg $_ }) -join ' '
    $psi.WorkingDirectory = $script:ProjectRoot
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.StandardOutputEncoding = $script:Utf8
    $process = [Diagnostics.Process]::Start($psi)
    $errorTask = $process.StandardError.ReadToEndAsync()
    $output = $process.StandardOutput.ReadToEnd()
    $process.WaitForExit()
    $null = $errorTask.Result
    if ($process.ExitCode -ne 0) { return $null }
    return $output
}
function ConvertTo-NativeArg([string]$value) {
    # CommandLineToArgvW quoting, so arguments arrive exactly as listed in checks.tsv.
    if ($value -ne '' -and $value -notmatch '[\s"]') { return $value }
    $escaped = [regex]::Replace($value, '(\\*)"', '$1$1\"')
    $escaped = [regex]::Replace($escaped, '(\\+)$', '$1$1')
    return '"' + $escaped + '"'
}
function Test-DigestExcluded([string]$name) {
    return $name.StartsWith("$($script:GateRel)/outputs/") -or $name.StartsWith("$($script:GateRel)/cache/") -or
        $name.StartsWith('files/runtime/') -or $name -eq 'md-instructions/Handoff.md'
}
function Get-InputFiles {
    $listed = Invoke-Git @('-c', 'core.quotepath=off', 'ls-files', '-co', '--exclude-standard', '-z', '--', '.')
    if ($null -ne $listed) {
        $names = @($listed -split "`0" | Where-Object { $_ })
    } else {
        $skipDirs = '(^|/)(\.git|\.venv|venv|node_modules|__pycache__)/'
        $skipTop = '^files/(bin|runtime|temp|run-temp|test-logs|logs|output|backups|diagnostics)/'
        $rootLength = $script:ProjectRoot.TrimEnd('\').Length + 1
        $names = @(Get-ChildItem -LiteralPath $script:ProjectRoot -Recurse -File -Force | ForEach-Object { $_.FullName.Substring($rootLength).Replace('\', '/') } |
            Where-Object { $_ -notmatch $skipDirs -and $_ -notmatch $skipTop })
    }
    return @($names | Where-Object { -not (Test-DigestExcluded $_) } | Sort-Object -CaseSensitive)
}
function Get-Sha256Hex([byte[]]$bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() } finally { $sha.Dispose() }
}
function Get-InputDigest {
    $builder = New-Object Text.StringBuilder
    $names = @(Get-InputFiles)
    foreach ($name in $names) {
        $full = Join-Path $script:ProjectRoot ($name.Replace('/', '\'))
        $hash = 'missing'
        if (Test-Path -LiteralPath $full -PathType Leaf) { $hash = Get-Sha256Hex ([IO.File]::ReadAllBytes($full)) }
        [void]$builder.Append("$name`0$hash`n")
    }
    return @{ digest = (Get-Sha256Hex ($script:Utf8.GetBytes($builder.ToString()))); count = $names.Count }
}
function Read-State {
    if (-not (Test-Path -LiteralPath $script:StatePath)) { return @{} }
    try {
        $data = [IO.File]::ReadAllText($script:StatePath) | ConvertFrom-Json
        if ($data.schema -ne 2) { return @{} }
        return $data
    } catch { return @{} }
}
function Update-State([scriptblock]$change) {
    $runtime = Split-Path -Parent $script:StatePath
    if (-not (Test-Path -LiteralPath $runtime)) { [void](New-Item -ItemType Directory -Force -Path $runtime) }
    $lock = "$($script:StatePath).lockd"
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    while ($true) {
        try {
            [void][IO.Directory]::CreateDirectory($runtime)
            if (-not (Test-Path -LiteralPath $lock)) {
                $item = New-Item -ItemType Directory -Path $lock -ErrorAction Stop
                if ($item) { break }
            }
        } catch { }
        if (Test-Path -LiteralPath $lock) {
            $age = ([DateTime]::UtcNow - (Get-Item -LiteralPath $lock).LastWriteTimeUtc).TotalSeconds
            if ($age -gt 60) { Remove-Item -LiteralPath $lock -Force -ErrorAction SilentlyContinue; continue }
        }
        if ([DateTime]::UtcNow -gt $deadline) { throw 'could not lock the status index' }
        Start-Sleep -Milliseconds 50
    }
    try {
        $current = Read-State
        $sections = @{}
        foreach ($key in @('latest_any', 'latest_full', 'last_full_pass', 'in_progress')) {
            if ($current.$key) { $sections[$key] = $current.$key }
        }
        & $change $sections
        $lines = @('  "schema": 2')
        foreach ($key in @('latest_any', 'latest_full', 'last_full_pass', 'in_progress')) {
            if ($sections.ContainsKey($key) -and $sections[$key]) { $lines += "  `"$key`": $($sections[$key] | ConvertTo-Json -Compress -Depth 5)" }
        }
        Write-AtomicFile $script:StatePath ("{`n" + ($lines -join ",`n") + "`n}`n")
    } finally {
        Remove-Item -LiteralPath $lock -Force -Recurse -ErrorAction SilentlyContinue
    }
}
function Show-Status {
    $state = Read-State
    $latest = $state.latest_full
    if (-not $latest) { Write-Output 'No full verification result is recorded.'; exit 2 }
    Write-Output "Latest full run: $($latest.run_id): $($latest.disposition) ($($latest.lifecycle)), scope $($latest.platform_scope -join '+'), finished $($latest.finished_at)"
    $problems = @()
    if ($state.in_progress -and $state.in_progress.run_id -ne $latest.run_id) { $problems += "full run $($state.in_progress.run_id) started and has no terminal record (running or killed)" }
    if (-not (Test-Path -LiteralPath (Join-Path $script:OutputsDir "$($latest.run_id)\results.json"))) { $problems += 'its evidence is no longer on disk' }
    if ((Get-InputDigest).digest -ne $latest.input_digest) { $problems += 'verification inputs changed since that run' }
    if ($latest.disposition -ne 'PASS') { $problems += "the latest full result is $($latest.disposition)" }
    if ($state.last_full_pass -and $state.last_full_pass.run_id -ne $latest.run_id) { Write-Output "History only: last full PASS was $($state.last_full_pass.run_id)." }
    if ($problems.Count -gt 0) {
        Write-Output "NOT CURRENT: $($problems -join '; ')."
        if ($latest.disposition -eq 'FAIL') { exit 1 }
        exit 2
    }
    Write-Output 'CURRENT: the working tree matches that PASS.'
    exit 0
}

if ($script:Action -eq 'setup') { Write-Output "This gate has no tooling to install; checks.tsv runs the project's own tools."; exit 0 }
if ($script:Action -eq 'status') { Show-Status }

# --- run allocation ---------------------------------------------------------
function Test-Inside([string]$path, [string]$parent) {
    $item = Get-Item -LiteralPath $path -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { return $false }
    return $true
}
if ((Test-Path -LiteralPath $script:OutputsDir) -and -not (Test-Inside $script:OutputsDir $script:GateDir)) {
    [Console]::Error.WriteLine("ERROR: $($script:GateRel)/outputs is a link; refusing to write through it.")
    exit 2
}
$script:RunId = $null
try {
    [void][IO.Directory]::CreateDirectory($script:OutputsDir)
    for ($attempt = 0; $attempt -lt 64 -and -not $script:RunId; $attempt++) {
        $candidate = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 6)
        $target = Join-Path $script:OutputsDir $candidate
        if (-not (Test-Path -LiteralPath $target)) {
            try {
                [void](New-Item -ItemType Directory -Path $target -ErrorAction Stop)
                $script:RunId = $candidate
            } catch [IO.IOException] { }
        }
    }
} catch {
    [Console]::Error.WriteLine("ERROR: could not create a run folder under $($script:GateRel)/outputs: $_")
    exit 2
}
if (-not $script:RunId) { [Console]::Error.WriteLine("ERROR: could not create a run folder under $($script:GateRel)/outputs."); exit 2 }

$script:RunDir = Join-Path $script:OutputsDir $script:RunId
$script:StartedAt = Get-UtcStamp
$script:StartedClock = [Diagnostics.Stopwatch]::StartNew()
$script:Lifecycle = 'RUNNING'
$script:Checks = New-Object Collections.ArrayList
$script:Tests = New-Object Collections.ArrayList
$script:Outcomes = @{}
$script:Notes = New-Object Collections.ArrayList
$script:Anomalies = New-Object Collections.ArrayList
$script:Reasons = @()
$script:Disposition = 'BLOCKED'
$script:ExitCode = 2
$script:Statement = ''
$script:Coverage = @{ registered = 0; not_applicable = 0; optional = 0; outside_scope = 0; applicable = 0; exempt = 0; mapped = 0; satisfied = 0; unresolved = 0; mapping_status = 'NOT RUN'; execution_status = 'NOT RUN'; gaps = @(); requirements = @(); unmapped_tests = @(); code_coverage = @{ collected = $false } }
$script:Current = $null
$script:ActiveOs = 'windows'
$script:Finished = $false

function Read-Tsv([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return @() }
    return @([IO.File]::ReadAllLines($path) | ForEach-Object { $_.TrimEnd("`r") })
}
function Get-Directive([string]$name) {
    foreach ($line in (Read-Tsv $script:ChecksFile)) {
        if ($line.StartsWith("@$name`t")) { return $line.Substring($name.Length + 2).Trim() }
    }
    return ''
}
$script:ProjectName = Get-Directive 'project'
if (-not $script:ProjectName) { $script:ProjectName = Split-Path -Leaf $script:ProjectRoot }
$script:ProjectVersion = Get-Directive 'version'
$script:Declared = @((Get-Directive 'platforms') -split ',' | Where-Object { $_ })
if ($script:Declared.Count -eq 0) { $script:Declared = @('windows', 'macos') }
if ($script:ScopeArg) {
    if ($script:ScopeArg -eq 'both') { $script:Scope = @('windows', 'macos') } else { $script:Scope = @($script:ScopeArg) }
} else {
    $script:Scope = @((Get-Directive 'delivery_scope') -split ',' | Where-Object { $_ })
    if ($script:Scope.Count -eq 0) { $script:Scope = $script:Declared }
}

function Get-GitFacts {
    $facts = @{ git_root_relation = 'none'; target_path = '.'; branch = $null; head = $null; dirty = $null }
    $top = Invoke-Git @('rev-parse', '--show-toplevel')
    if (-not $top) { return $facts }
    $topPath = [IO.Path]::GetFullPath($top.Trim().Replace('/', '\')).TrimEnd('\')
    $root = $script:ProjectRoot.TrimEnd('\')
    if ($topPath -ieq $root) { $facts.git_root_relation = 'project' } else {
        $facts.git_root_relation = 'ancestor'
        $facts.target_path = $root.Substring($topPath.Length + 1).Replace('\', '/')
    }
    $branch = Invoke-Git @('branch', '--show-current')
    if ($branch) { $facts.branch = $branch.Trim() }
    $head = Invoke-Git @('rev-parse', '--verify', 'HEAD')
    if ($head) { $facts.head = $head.Trim() }
    $status = Invoke-Git @('status', '--porcelain=v1', '--untracked-files=all', '--', '.')
    if ($null -ne $status) { $facts.dirty = [bool]$status.Trim() }
    return $facts
}
$script:Source = Get-GitFacts
$startDigest = Get-InputDigest
$script:Source.input_digest_start = $startDigest.digest
$script:Source.files_digested = $startDigest.count
$script:Source.input_digest_end = $null
$script:Source.changed_during_run = $null

function Get-ResultsObject {
    $finished = $script:Lifecycle -ne 'RUNNING'
    $portable = @($script:Checks | Where-Object { $_.layer -eq 'portable' -and $_.status -in @('PASS', 'FAIL') } | ForEach-Object { $_.id })
    $native = @($script:Checks | Where-Object { $_.layer -eq 'native' -and $_.status -in @('PASS', 'FAIL') } | ForEach-Object { $_.id })
    $outstanding = @($script:Declared | Where-Object { $_ -ne $script:ActiveOs })
    $checks = @($script:Checks | ForEach-Object {
        $copy = @{}
        foreach ($key in $_.Keys) { if ($key -ne 'diagnostic') { $copy[$key] = $_[$key] } }
        $copy
    })
    $evidence = @($script:Checks | ForEach-Object { $_.evidence } | Where-Object { $_ } | Sort-Object -Unique)
    $review = 'not-required'
    if ($script:Mode -eq 'full' -and $script:Lifecycle -eq 'COMPLETED') { $review = 'pending' }
    return [ordered]@{
        schema_version = 1
        run = [ordered]@{ id = $script:RunId; path = "$($script:GateRel)/outputs/$($script:RunId)"; started_at = $script:StartedAt
            ended_at = $(if ($finished) { Get-UtcStamp } else { $null }); duration_seconds = [math]::Round($script:StartedClock.Elapsed.TotalSeconds, 3)
            mode = $script:Mode; selectors = @($script:Selected); lifecycle = $script:Lifecycle; runner = 'verify.ps1'; invocation = @(); cwd_is_project_root = ((Get-Location).Path -ieq $script:ProjectRoot.TrimEnd('\')) }
        disposition = $(if ($finished) { $script:Disposition } else { $null })
        exit_code = $(if ($finished) { $script:ExitCode } else { $null })
        acceptance = [ordered]@{ scope = $script:Mode; established = ($script:Mode -eq 'full' -and $script:Disposition -eq 'PASS' -and $script:Lifecycle -eq 'COMPLETED'); statement = $script:Statement }
        reasons = @($script:Reasons); notes = @($script:Notes)
        project = [ordered]@{ name = $script:ProjectName; version = $(if ($script:ProjectVersion) { $script:ProjectVersion } else { $null }); profile = 'generic'; adapters = @() }
        source = $script:Source
        platform = [ordered]@{ active = [ordered]@{ os = 'windows'; version = [Environment]::OSVersion.VersionString; architecture = $env:PROCESSOR_ARCHITECTURE; machine = $env:COMPUTERNAME }
            declared = @($script:Declared); requested_scope = @($script:Scope); portable_checks = $portable; native_checks = $native; outstanding = $outstanding
            not_run_note = @($outstanding | ForEach-Object { "$_ native acceptance NOT RUN" }) }
        checks = $checks; tests = @($script:Tests); coverage = $script:Coverage; evidence = $evidence; anomalies = @($script:Anomalies)
        review = [ordered]@{ state = $review; path = 'agent-review.md' }
    }
}
function Write-Results { Write-AtomicFile (Join-Path $script:RunDir 'results.json') ((Get-ResultsObject | ConvertTo-Json -Depth 8) + "`n") }
function Add-Check([string]$id, [string]$kind, [string]$status, [string]$reason, [bool]$required = $true, [string]$layer = 'portable', $rawExit = $null, [double]$duration = 0, [string]$evidence = '', [string]$diagnostic = '', [bool]$applicable = $true) {
    $evidenceList = @()
    if ($evidence) { $evidenceList = @($evidence) }
    [void]$script:Checks.Add(@{ id = $id; kind = $kind; layer = $layer; required = $required; applicable = $applicable; status = $status; reason = $reason; counts = @{}; raw_exit = $rawExit; duration_seconds = [math]::Round($duration, 3); evidence = $evidenceList; diagnostic = $diagnostic })
    Write-Results
}
function Stop-OwnedTree($process) {
    # taskkill starts from this child's PID, so unrelated processes are never touched.
    if ($process -and -not $process.HasExited) {
        & taskkill.exe /T /F /PID $process.Id 2>&1 | Out-Null
        [void]$process.WaitForExit(10000)
    }
}
function Invoke-Bounded([string]$exe, [string[]]$arguments, [int]$timeout, [string]$name) {
    $logs = Join-Path $script:RunDir 'logs'
    [void][IO.Directory]::CreateDirectory($logs)
    $temp = Join-Path $script:RunDir 'temp'
    $artifacts = Join-Path $script:RunDir 'artifacts'
    [void][IO.Directory]::CreateDirectory($temp)
    [void][IO.Directory]::CreateDirectory($artifacts)
    $log = Join-Path $logs "$name.log"
    $errorLog = Join-Path $temp "$name.stderr"
    $environment = @{ VERIFY_RUN_ID = $script:RunId; VERIFY_RUN_DIR = $script:RunDir; VERIFY_ARTIFACTS_DIR = $artifacts; VERIFY_TEMP_DIR = $temp; VERIFY_GATE_DIR = $script:GateDir
        VERIFY_FIXTURES_DIR = (Join-Path $script:GateDir 'fixtures'); VERIFY_PROJECT_ROOT = $script:ProjectRoot; VERIFY_PLATFORM = 'windows'; TMP = $temp; TEMP = $temp; TMPDIR = $temp }
    $saved = @{}
    foreach ($key in $environment.Keys) { $saved[$key] = [Environment]::GetEnvironmentVariable($key); [Environment]::SetEnvironmentVariable($key, $environment[$key]) }
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $timedOut = $false
    try {
        $commandLine = (@($arguments) | ForEach-Object { ConvertTo-NativeArg $_ }) -join ' '
        $options = @{ FilePath = $exe; WorkingDirectory = $script:ProjectRoot; RedirectStandardOutput = $log; RedirectStandardError = $errorLog; PassThru = $true; NoNewWindow = $true }
        if ($commandLine) { $options.ArgumentList = $commandLine }
        $process = Start-Process @options
        $null = $process.Handle  # Without touching Handle, ExitCode can stay empty after exit.
        $script:Current = $process
        while (-not $process.WaitForExit(200)) {
            if ($clock.Elapsed.TotalSeconds -ge $timeout) {
                $timedOut = $true
                Stop-OwnedTree $process
                break
            }
        }
        $raw = $null
        if ($process.HasExited) { $raw = $process.ExitCode }
        $script:Current = $null
    } catch {
        return @{ startError = "$_"; raw = $null; timedOut = $false; log = $log; duration = $clock.Elapsed.TotalSeconds }
    } finally {
        foreach ($key in $saved.Keys) { [Environment]::SetEnvironmentVariable($key, $saved[$key]) }
    }
    if ((Test-Path -LiteralPath $errorLog) -and (Get-Item -LiteralPath $errorLog).Length -gt 0) {
        [IO.File]::AppendAllText($log, [IO.File]::ReadAllText($errorLog))
    }
    Remove-Item -LiteralPath $errorLog -Force -ErrorAction SilentlyContinue
    return @{ raw = $raw; timedOut = $timedOut; log = $log; duration = $clock.Elapsed.TotalSeconds }
}
function Get-LogTail([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return '' }
    $lines = [IO.File]::ReadAllLines($path)
    if ($lines.Count -gt 60) { $lines = $lines[($lines.Count - 60)..($lines.Count - 1)] }
    return ($lines -join "`n")
}
function Test-PathBudget {
    $length = $script:RunDir.Length
    $remaining = 259 - $length
    if ($remaining -lt 80) {
        Add-Check 'path-budget' 'preflight' 'BLOCKED' "run directory uses $length of 259 characters; tools need about 80 more. Move the project to a shorter path."
    } else {
        Add-Check 'path-budget' 'preflight' 'PASS' "$remaining characters left below the run directory"
    }
}
function Test-PlatformScope {
    $undeclared = @($script:Scope | Where-Object { $_ -notin $script:Declared })
    if ($undeclared.Count -gt 0) { Add-Check 'platform-scope' 'preflight' 'FAIL' "requested scope includes undeclared platform(s): $($undeclared -join ', ')" }
    elseif ($script:ActiveOs -notin $script:Scope) { Add-Check 'platform-scope' 'preflight' 'BLOCKED' "requested $($script:Scope -join '+') but this machine runs windows; a native run there is required" }
    elseif ($script:Scope.Count -gt 1) {
        $other = @($script:Scope | Where-Object { $_ -ne $script:ActiveOs })
        Add-Check 'platform-scope' 'preflight' 'BLOCKED' "both-platform acceptance is incomplete: $($other -join ', ') NOT RUN on this windows machine"
    } else { Add-Check 'platform-scope' 'preflight' 'PASS' 'windows scope on windows' $true 'native' }
}
function Test-DataRow([string]$line) { return $line.Trim() -and -not $line.StartsWith('#') -and -not $line.StartsWith('@') }
function Test-ApplicationUnconfigured {
    return @(Read-Tsv $script:CoverageFile | Where-Object { Test-DataRow $_ }).Count -eq 0 -and @(Read-Tsv $script:ChecksFile | Where-Object { Test-DataRow $_ }).Count -eq 0
}
function Test-Structure {
    $problems = @()
    $scripts = Join-Path $script:ProjectRoot 'scripts'
    if (Test-Path -LiteralPath $scripts) {
        foreach ($item in Get-ChildItem -LiteralPath $scripts) {
            # PFI: scripts\verify.ps1 predates the gate and is the configured authoritative verifier; c-0001 runs it.
            if ($item.Name -ceq 'verify.ps1') { continue }
            if ($item.Name -match '^(verify\..*|project-status\..*|conftest\.py|test_.*)$') { $problems += "scripts/$($item.Name): developer-only tooling belongs in $($script:GateRel)/" }
        }
    }
    if (-not (Test-Path -LiteralPath $script:CoverageFile)) { $problems += "$($script:GateRel)/coverage.tsv is missing" }
    if (-not (Test-Path -LiteralPath $script:ChecksFile)) { $problems += "$($script:GateRel)/checks.tsv is missing" }
    if ($script:Source.git_root_relation -ne 'none') {
        $ignored = Invoke-Git @('check-ignore', '--no-index', "$($script:GateRel)/outputs/x", "$($script:GateRel)/cache/x")
        if (-not $ignored -or @($ignored.Trim() -split "`n").Count -lt 2) { $problems += 'gate outputs/ and cache/ must be ignored by Git' }
    }
    if ($problems.Count -gt 0) { Add-Check 'structure' 'static' 'FAIL' "$($problems.Count) structure problem(s)" $true 'portable' $null 0 '' ($problems -join "`n") }
    else { Add-Check 'structure' 'static' 'PASS' 'gate layout and ignore rules' }
}
function Test-Docs {
    $missing = @(@('md-instructions/Briefing.md', 'md-instructions/Handoff.md') | Where-Object { -not (Test-Path -LiteralPath (Join-Path $script:ProjectRoot $_)) })
    if ($missing.Count -gt 0) {
        Add-Check 'docs' 'static' 'FAIL' "$($missing.Count) required document(s) missing" $true 'portable' $null 0 '' ($missing -join "`n")
        return
    }
    $changelog = Join-Path $script:ProjectRoot 'md-instructions\Changelog.md'
    $markers = @('[project_name]', '[project name]', '[yyyy-mm-dd]', '[feature]', '[version]', '[what the project', '[what is actively', '[short summary', '[required change]')
    $templated = @()
    foreach ($file in @((Join-Path $script:ProjectRoot 'md-instructions\Briefing.md'), $changelog)) {
        if (-not (Test-Path -LiteralPath $file)) { continue }
        $text = [IO.File]::ReadAllText($file).ToLowerInvariant()
        foreach ($marker in $markers) {
            if ($text.Contains($marker)) { $templated += "$(Split-Path -Leaf $file): unresolved placeholder '$marker'"; break }
        }
    }
    if ($templated.Count -gt 0) {
        $status = 'FAIL'
        if (Test-ApplicationUnconfigured) { $status = 'BLOCKED' }
        Add-Check 'docs' 'static' $status 'template placeholders remain' $true 'portable' $null 0 '' ($templated -join "`n")
        return
    }
    if (-not (Test-Path -LiteralPath $changelog)) { Add-Check 'docs' 'static' 'PASS' 'core docs present, no changelog kept'; return }
    if (-not $script:ProjectVersion) { Add-Check 'docs' 'static' 'FAIL' 'could not determine the project version for the changelog check; set @version in checks.tsv'; return }
    $dash = [char]0x2014
    if ([IO.File]::ReadAllText($changelog) -match "(?m)^##\s+v$([regex]::Escape($script:ProjectVersion))(?:\s|$|$dash|-)") { Add-Check 'docs' 'static' 'PASS' 'permanent docs present, changelog current' }
    else { Add-Check 'docs' 'static' 'FAIL' 'current version missing from Changelog.md' $true 'portable' $null 0 '' "Expected a heading for v$($script:ProjectVersion)" }
}
function Invoke-Commands {
    if (-not (Test-Path -LiteralPath $script:ChecksFile)) { Add-Check 'checks-file' 'static' 'FAIL' 'checks.tsv is missing'; return }
    $configured = 0
    foreach ($row in (Read-Tsv $script:ChecksFile | Where-Object { Test-DataRow $_ })) {
        $fields = $row.Split("`t")
        if ($fields.Count -lt 6) { Add-Check 'checks-file' 'static' 'FAIL' "malformed checks.tsv row: $row"; continue }
        $id = $fields[0]; $required = $fields[1] -eq 'yes'; $layer = $fields[4]
        $limit = 900
        [void][int]::TryParse($fields[2], [ref]$limit)
        $configured++
        if ($script:Mode -eq 'focused' -and $id -notin $script:Selected) { continue }
        $platforms = @($fields[3] -split ',')
        if ($fields[3] -eq 'all') { $platforms = $script:Declared }
        if ('windows' -notin $platforms) {
            $inScope = $required -and @($platforms | Where-Object { $_ -in $script:Scope }).Count -gt 0
            Add-Check $id 'command' 'NOT RUN' "runs on $($platforms -join ', ')" $inScope $layer
            continue
        }
        $program = $fields[5]
        $exe = $null
        $relative = Join-Path $script:ProjectRoot $program
        if (Test-Path -LiteralPath $relative -PathType Leaf) { $exe = $relative }
        else { $found = Get-Command $program -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1; if ($found) { $exe = $found.Source } }
        if (-not $exe) {
            Add-Check $id 'command' 'BLOCKED' "$program was not found" $required $layer
            $script:Outcomes[$id] = 'blocked'
            continue
        }
        $arguments = @()
        if ($fields.Count -gt 6) { $arguments = @($fields[6..($fields.Count - 1)]) }
        $outcome = Invoke-Bounded $exe $arguments $limit $id
        if ($outcome.raw -eq -1073741510) {  # STATUS_CONTROL_C_EXIT
            $script:Interrupted = $true
            throw 'interrupted'
        }
        if ($outcome.startError) { $status = 'BLOCKED'; $reason = "could not start: $($outcome.startError)"; $result = 'blocked' }
        elseif ($outcome.timedOut) { $status = 'BLOCKED'; $reason = "timed out after ${limit}s"; $result = 'blocked' }
        elseif ($outcome.raw -eq 0) { $status = 'PASS'; $reason = 'exit 0'; $result = 'passed' }
        # PFI: checks report why they could not establish a result, so a security-policy block or a missing
        # opt-in is never confused with a product failure. None of these can make the run PASS.
        elseif ($outcome.raw -eq 2) { $status = 'BLOCKED'; $reason = 'exit 2: prerequisite unavailable'; $result = 'blocked' }
        elseif ($outcome.raw -eq 3) { $status = 'BLOCKED'; $reason = 'BLOCKED_BY_ENDPOINT_SECURITY (exit 3)'; $result = 'blocked' }
        elseif ($outcome.raw -eq 4) { $status = 'NOT RUN'; $reason = 'exit 4: explicit opt-in not given'; $result = 'not-run' }
        # PFI: a crashed test process is a failure, but not an assertion verdict; label it so the two stay distinct.
        elseif ($outcome.raw -eq 5) { $status = 'FAIL'; $reason = 'exit 5: test process crashed (not an assertion result)'; $result = 'failed' }
        else { $status = 'FAIL'; $reason = "exit $($outcome.raw)"; $result = 'failed' }
        $script:Outcomes[$id] = $result
        [void]$script:Tests.Add(@{ adapter = 'command'; id = $id; layer = $layer; attempts = 1; outcome = $result; duration_seconds = [math]::Round($outcome.duration, 3); reason = $reason })
        $diagnostic = ''
        if ($status -ne 'PASS') { $diagnostic = Get-LogTail $outcome.log }
        Add-Check $id 'command' $status $reason $required $layer $outcome.raw $outcome.duration "logs/$id.log" $diagnostic
    }
    if ($configured -eq 0) { Add-Check 'commands' 'tests' 'NOT RUN' 'no project commands are configured in checks.tsv' $false }
}
function Invoke-Coverage {
    if (-not (Test-Path -LiteralPath $script:CoverageFile)) { Add-Check 'coverage' 'coverage' 'BLOCKED' 'coverage.tsv cannot be read'; return }
    $configuredChecks = @{}
    foreach ($row in (Read-Tsv $script:ChecksFile | Where-Object { Test-DataRow $_ })) { $configuredChecks[$row.Split("`t")[0]] = $true }
    $c = $script:Coverage
    $gaps = New-Object Collections.ArrayList
    $rows = New-Object Collections.ArrayList
    $seen = @{}
    $hardFail = $false
    $softBlock = $false
    function Add-Row([string]$id, [string]$description, [string]$status, [bool]$mapped, [string]$detail) {
        [void]$rows.Add(@{ id = $id; description = $description; status = $status; mapped = $mapped; detail = $detail; tests = @() })
    }
    foreach ($line in (Read-Tsv $script:CoverageFile | Where-Object { Test-DataRow $_ })) {
        $f = $line.Split("`t")
        $id = $f[0]
        $description = ''; if ($f.Count -gt 3) { $description = $f[3] }
        $tests = ''; if ($f.Count -gt 4) { $tests = $f[4] }
        $exception = ''; if ($f.Count -gt 5) { $exception = $f[5] }
        $c.registered++
        if ($seen[$id]) { [void]$gaps.Add("duplicate requirement id: $id"); $hardFail = $true }
        $seen[$id] = $true
        if (-not $description) { [void]$gaps.Add("${id}: a description is required"); $hardFail = $true }
        $platforms = @($f[2] -split ',')
        if ($f[2] -eq 'all') { $platforms = $script:Declared }
        if ($exception.StartsWith('NA:')) {
            $reason = $exception.Substring(3)
            if (-not $reason) { [void]$gaps.Add("${id}: not-applicable needs a reason"); $hardFail = $true }
            else { $c.not_applicable++; Add-Row $id $description 'NOT APPLICABLE' $false $reason }
            continue
        }
        if ($f[1] -ne 'yes') { $c.optional++; Add-Row $id $description 'OPTIONAL' $false ''; continue }
        if (@($platforms | Where-Object { $_ -in $script:Scope }).Count -eq 0 -or 'windows' -notin $platforms) {
            $c.outside_scope++
            Add-Row $id $description 'OUTSIDE SCOPE' $false "required on $($platforms -join ', '); this run is windows"
            continue
        }
        if ($exception -and $exception -ne '-') {
            $parts = $exception.Split('|')
            $c.applicable++
            $usable = $parts.Count -ge 4 -and $parts[0] -and $parts[1] -and $parts[2] -and $parts[3]
            $expired = $parts.Count -ge 5 -and $parts[4] -and $parts[4] -ne '-' -and ([string]::CompareOrdinal($parts[4], [DateTime]::UtcNow.ToString('yyyy-MM-dd')) -lt 0)
            if (-not $usable) {
                $detail = 'exception is not usable: approval details are missing; agents may propose exceptions but only the user can approve them'
                [void]$gaps.Add("${id}: $detail"); $hardFail = $true; $c.unresolved++
                Add-Row $id $description 'UNMAPPED' $false $detail
            } elseif ($expired) {
                $detail = "exception is not usable: expired on $($parts[4])"
                [void]$gaps.Add("${id}: $detail"); $hardFail = $true; $c.unresolved++
                Add-Row $id $description 'UNMAPPED' $false $detail
            } else {
                $c.applicable--; $c.exempt++
                Add-Row $id $description 'EXEMPT' $true "$($parts[0]): $($parts[1])"
            }
            continue
        }
        $c.applicable++
        if (-not $tests -or $tests -eq '-') {
            [void]$gaps.Add("${id}: no test is mapped"); $hardFail = $true; $c.unresolved++
            Add-Row $id $description 'UNMAPPED' $false 'no test is mapped'
            continue
        }
        $state = 'SATISFIED'; $detail = ''
        foreach ($test in ($tests -split ',')) {
            if (-not $configuredChecks[$test]) { $state = 'DANGLING'; $detail = "mapped test(s) do not exist: $test"; break }
            $result = $script:Outcomes[$test]
            if ($result -eq 'failed') { $state = 'FAILED'; $detail = "$test (failed)"; break }
            if ($result -ne 'passed' -and $state -eq 'SATISFIED') { $state = 'NOT SATISFIED'; $detail = "not executed or not passed: $test" }
        }
        switch ($state) {
            'SATISFIED' { $c.mapped++; $c.satisfied++; Add-Row $id $description $state $true '' }
            'DANGLING' { [void]$gaps.Add("${id}: $detail"); $hardFail = $true; $c.unresolved++; Add-Row $id $description $state $false $detail }
            'FAILED' { [void]$gaps.Add("${id}: $detail"); $hardFail = $true; $c.mapped++; $c.unresolved++; Add-Row $id $description $state $true $detail }
            default { [void]$gaps.Add("${id}: $detail"); $softBlock = $true; $c.mapped++; $c.unresolved++; Add-Row $id $description $state $true $detail }
        }
    }
    $c.gaps = @($gaps)
    $c.requirements = @($rows)
    if ($c.applicable -eq 0) { $c.mapping_status = 'BLOCKED' } elseif ($c.mapped -eq $c.applicable) { $c.mapping_status = 'PASS' } else { $c.mapping_status = 'FAIL' }
    if ($script:Mode -ne 'full') { Add-Check 'coverage' 'coverage' 'NOT RUN' "$($script:Mode) mode: mapping reported, executed satisfaction not established" $false; return }
    if ($hardFail) {
        $c.execution_status = 'FAIL'
        Add-Check 'coverage' 'coverage' 'FAIL' "$($c.unresolved) of $($c.applicable) required item(s) unresolved" $true 'portable' $null 0 '' ($gaps -join "`n")
    } elseif ($c.applicable -eq 0) {
        $c.execution_status = 'BLOCKED'
        if ($c.registered -eq 0) { Add-Check 'coverage' 'coverage' 'BLOCKED' 'application verification not configured: no required functionality is registered in coverage.tsv' }
        else { Add-Check 'coverage' 'coverage' 'BLOCKED' 'no required functionality is applicable to this scope' }
    } elseif ($softBlock) {
        $c.execution_status = 'BLOCKED'
        Add-Check 'coverage' 'coverage' 'BLOCKED' "$($c.unresolved) of $($c.applicable) required item(s) could not be established" $true 'portable' $null 0 '' ($gaps -join "`n")
    } else {
        $c.execution_status = 'PASS'
        Add-Check 'coverage' 'coverage' 'PASS' "$($c.satisfied) of $($c.applicable) required item(s) satisfied; $($c.exempt) approved exception(s)"
    }
}
function Complete-Aggregate {
    $required = @($script:Checks | Where-Object { $_.required -and $_.applicable })
    $script:Reasons = @($required | Where-Object { $_.status -in @('FAIL', 'BLOCKED', 'NOT RUN') } | ForEach-Object { "$($_.id): $($_.reason)" })
    $script:Reasons += @($script:Notes | Where-Object { $_ -like 'unknown selector*' })
    $statuses = @($required | ForEach-Object { $_.status })
    $executed = @($script:Checks | Where-Object { $_.status -in @('PASS', 'FAIL') -and $_.kind -eq 'command' })
    $disposition = 'PASS'
    if ('FAIL' -in $statuses) { $disposition = 'FAIL' }
    elseif ('BLOCKED' -in $statuses -or ($script:Mode -eq 'full' -and 'NOT RUN' -in $statuses)) { $disposition = 'BLOCKED' }
    elseif ($script:Mode -ne 'full' -and $executed.Count -eq 0) { $disposition = 'BLOCKED'; $script:Reasons += 'nothing was selected, so nothing was verified' }
    elseif (@($script:Notes | Where-Object { $_ -like 'unknown selector*' }).Count -gt 0) { $disposition = 'BLOCKED' }
    if ($script:Source.changed_during_run -and $disposition -eq 'PASS') { $disposition = 'BLOCKED'; $script:Reasons += 'verification inputs changed during the run, so this evidence cannot certify them' }
    if ($script:Lifecycle -eq 'INTERRUPTED') {
        if ($disposition -eq 'PASS') { $disposition = 'BLOCKED' }
        $script:Reasons += 'the run was interrupted before it finished'
        $script:ExitCode = 130
    } else {
        $script:ExitCode = @{ PASS = 0; FAIL = 1; BLOCKED = 2 }[$disposition]
    }
    $script:Disposition = $disposition
    $names = @{ windows = 'Windows'; macos = 'macOS' }
    $dash = [char]0x2014
    if ($script:Mode -ne 'full') {
        $script:Statement = "$disposition $dash $($script:Mode) selection on Windows; full acceptance not established"
    } else {
        $label = (@($script:Scope) | ForEach-Object { $names[$_] }) -join '+'
        $tail = (@($script:Declared | Where-Object { $_ -notin $script:Scope -or $_ -ne 'windows' }) | ForEach-Object { "; $($names[$_]) native acceptance NOT RUN" }) -join ''
        $script:Statement = "$disposition $dash full $label checkpoint$tail"
    }
}
function Write-Reports {
    $summary = @("# Verification summary: $($script:ProjectName)", '', "**$($script:Statement)**", '',
        "- Run: ``$($script:RunId)`` ($($script:Lifecycle)), mode ``$($script:Mode)``, exit $($script:ExitCode)",
        '- Profile: generic',
        "- Source: branch $($script:Source.branch), HEAD $($script:Source.head), dirty $($script:Source.dirty), inputs ``$($script:Source.input_digest_start.Substring(0, 16))``",
        "- Machine: $env:COMPUTERNAME (windows); requested scope $($script:Scope -join '+')", '', '| Check | Required | Status | Detail |', '|---|---|---|---|')
    foreach ($check in $script:Checks) {
        $requiredLabel = 'no'
        if ($check.required) { $requiredLabel = 'yes' }
        $summary += "| $($check.id) | $requiredLabel | $($check.status) | $($check.reason.Replace('|', '\|').Replace("`n", ' ')) |"
    }
    if ($script:Notes.Count -gt 0 -or $script:Anomalies.Count -gt 0) { $summary += @('', '## Notes and anomalies', ''); foreach ($n in @($script:Notes) + @($script:Anomalies)) { $summary += "- $n" } }
    $summary += @('', 'Details: `failures.md`, `coverage-report.md`, `results.json`, `logs/`.')
    if ($script:Mode -eq 'full' -and $script:Lifecycle -eq 'COMPLETED') { $summary += @('', 'Agent review: pending. The supervising agent writes `agent-review.md` here after inspecting this evidence. A review is not approval.') }
    Write-AtomicFile (Join-Path $script:RunDir 'summary.md') (($summary -join "`n") + "`n")
    $c = $script:Coverage
    $coverage = @('# Functional coverage', '', "Mode ``$($script:Mode)``. Mapping and executed satisfaction are separate, and neither is code coverage.", '',
        "- Registered: $($c.registered); not applicable: $($c.not_applicable); optional: $($c.optional); outside this scope: $($c.outside_scope)",
        "- Applicable required: $($c.applicable); approved exceptions: $($c.exempt)",
        "- Mapped: $($c.mapped) ($($c.mapping_status)); executed and satisfied: $($c.satisfied) ($($c.execution_status)); unresolved: $($c.unresolved)",
        '- Code coverage: not collected')
    if (@($c.requirements).Count -gt 0) { $coverage += @('', '| Requirement | Status | Detail |', '|---|---|---|'); foreach ($r in $c.requirements) { $coverage += "| $($r.id) | $($r.status) | $($r.detail.Replace('|', '\|')) |" } }
    if (@($c.gaps).Count -gt 0) { $coverage += @('', '## Gaps', ''); foreach ($g in $c.gaps) { $coverage += "- $g" } }
    Write-AtomicFile (Join-Path $script:RunDir 'coverage-report.md') (($coverage -join "`n") + "`n")
    $bad = @($script:Checks | Where-Object { $_.status -in @('FAIL', 'BLOCKED') -and $_.required })
    if ($bad.Count -eq 0 -and $script:Lifecycle -eq 'COMPLETED') {
        $failures = "# Failures and blockers`n`nNone were observed in this run.`n"
    } else {
        $lines = @('# Failures and blockers', '')
        if ($script:Lifecycle -eq 'INTERRUPTED') { $lines += @('The run was interrupted. Results below are partial.', '') }
        foreach ($check in $bad) {
            $lines += @("## $($check.status): $($check.id)", '', $check.reason, '')
            if (@($check.evidence).Count -gt 0) { $lines += @("Evidence: ``$($check.evidence -join '`, `')``", '') }
            if ($check.diagnostic) { $lines += @('```text', $check.diagnostic.Replace('```', "'''"), '```', '') }
        }
        $failures = ($lines -join "`n") + "`n"
    }
    Write-AtomicFile (Join-Path $script:RunDir 'failures.md') $failures
    Write-Results
}
function Remove-EmptyDirs([string]$root) {
    foreach ($child in Get-ChildItem -LiteralPath $root -Directory -Force) {
        Remove-EmptyDirs $child.FullName
        if (@(Get-ChildItem -LiteralPath $child.FullName -Force).Count -eq 0) { Remove-Item -LiteralPath $child.FullName -Force -ErrorAction SilentlyContinue }
    }
}
function Complete-Run([string]$lifecycle) {
    if ($script:Finished) { return }
    $script:Finished = $true
    $script:Lifecycle = $lifecycle
    if ($script:Current) { Stop-OwnedTree $script:Current; $script:Current = $null }
    try {
        $script:Source.input_digest_end = (Get-InputDigest).digest
        $script:Source.changed_during_run = $script:Source.input_digest_end -ne $script:Source.input_digest_start
    } catch {
        [void]$script:Anomalies.Add("could not hash inputs at the end of the run: $_")
        $script:Source.changed_during_run = $true
    }
    Complete-Aggregate
    Remove-EmptyDirs $script:RunDir
    $published = $true
    try {
        Write-Reports
        $record = [ordered]@{ run_id = $script:RunId; mode = $script:Mode; disposition = $script:Disposition; lifecycle = $script:Lifecycle; finished_at = (Get-UtcStamp); input_digest = $script:Source.input_digest_end; git_head = $script:Source.head; dirty = $script:Source.dirty; platform_scope = @($script:Scope); tests = $script:Tests.Count }
        Update-State {
            param($sections)
            $sections['latest_any'] = $record
            if ($script:Mode -eq 'full') {
                $sections['latest_full'] = $record
                if ($script:Disposition -eq 'PASS') { $sections['last_full_pass'] = $record }
                if ($sections['in_progress'] -and $sections['in_progress'].run_id -eq $script:RunId) { $sections.Remove('in_progress') }
            }
        }
    } catch {
        $published = $false
        [Console]::Error.WriteLine("ERROR: results could not be published: $_")
    }
    if (-not $published) {
        # Never leave an older PASS standing when the new result cannot be recorded.
        Remove-Item -LiteralPath $script:StatePath -Force -ErrorAction SilentlyContinue
        if ($script:ExitCode -eq 0) { $script:ExitCode = 2 }
    }
    Write-Output "`nVERIFY $($script:Mode.ToUpperInvariant()): $($script:ProjectName) [$($script:RunId)]"
    foreach ($check in $script:Checks) {
        if ($check.status -eq 'NOT RUN' -and -not $check.required) { continue }
        Write-Output "  [$($check.status)] $($check.id): $($check.reason)"
    }
    Write-Output $script:Statement
    Write-Output "Evidence: $($script:GateRel)/outputs/$($script:RunId)/ (start with summary.md)"
    if ($script:Mode -eq 'full' -and $script:Lifecycle -eq 'COMPLETED') { Write-Output 'Agent review pending: write agent-review.md in that folder. See .ai/VERIFICATION.md.' }
}

$script:Done = $false
$script:Interrupted = $false
try {
    Write-Results
    Test-PathBudget
    if ($script:Mode -eq 'full') {
        try {
            Update-State { param($sections) $sections['in_progress'] = [ordered]@{ run_id = $script:RunId; started_at = $script:StartedAt } }
        } catch { [void]$script:Anomalies.Add("could not mark this run as in progress: $_") }
    }
    if ($script:Mode -eq 'changed') { [void]$script:Notes.Add('Generic projects have no change-to-check mapping, so the selection was broadened to every configured check. Full acceptance is still not established by this mode.') }
    if ($script:Mode -eq 'focused') {
        $known = @(Read-Tsv $script:ChecksFile | Where-Object { Test-DataRow $_ } | ForEach-Object { $_.Split("`t")[0] })
        foreach ($selector in $script:Selected) { if ($selector -notin $known) { [void]$script:Notes.Add("unknown selector: $selector") } }
    }
    Test-PlatformScope
    if ($script:Mode -ne 'focused') { Test-Structure; Test-Docs }
    Invoke-Commands
    Invoke-Coverage
    Complete-Run 'COMPLETED'
    $script:Done = $true
} catch {
    if ($script:Interrupted) {
        Complete-Run 'INTERRUPTED'
    } else {
        Add-Check 'runner' 'internal' 'BLOCKED' "unexpected runner error: $_" $true 'portable' $null 0 '' ($_ | Out-String)
        Complete-Run 'COMPLETED'
    }
    $script:Done = $true
} finally {
    # Ctrl+C unwinds through here without reaching the end of the try block.
    if (-not $script:Done) { Complete-Run 'INTERRUPTED'; [Environment]::Exit(130) }
}
exit $script:ExitCode
