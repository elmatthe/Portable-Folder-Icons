# Phase 0A maintenance reliability (gate check c-0010; coverage PFI-007, PFI-015, PFI-016, PFI-017).
#
# Runs the INSTALLED dispatcher (runtime\Invoke-PortableFolderIcons.ps1 -Action Repair|Uninstall), exactly as the
# Explorer verbs do, as real separate Windows PowerShell processes against disposable install copies. The dispatcher's
# verification seam records each dialog as JSON instead of showing it, and changes the menu only under GUID-named HKCU
# test keys that the product's own guard recognizes; the seam is ignored for the production install root.
#
# Covers: healthy and repeated Repair, missing and corrupt cached icons, missing and unloadable runtime modules,
# invalid settings/manifest/broker, failed registration, concurrent Repair (serialization AND result coalescing),
# concurrent Repair and ordinary Uninstall, timeout, abandoned lock, cancellation, normal and Developer Mode, and the
# unchanged broker/menu dispatch shape.
#
# Phase 0A.1 (PFI-017): the registered normal-mode Repair/Uninstall command runs wscript.exe with the installed
# windowless launcher. Those cases start that exact command (wscript.exe -> launcher -> hidden dispatcher) and watch
# the desktop with UI Automation for any console or Windows Terminal window while it runs.
#
# Safety: fixtures, install copies and logs live under the gate run's temp/artifacts folders inside the repository.
# Registry writes use only GUID-named test roots, removed in finally. The production install, production HKCU keys,
# user folders and Explorer are never touched. Only inbox powershell.exe and wscript.exe are started (the latter only
# on the installed launcher of a disposable install copy); no compiled executable.
#
# Exit: 0 all assertions passed, 1 an assertion failed, 2 a prerequisite was missing (BLOCKED).
[CmdletBinding()]
param(
    [string]$OutputRoot = $env:VERIFY_ARTIFACTS_DIR,
    [string]$FixtureRoot = $env:VERIFY_TEMP_DIR
)
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -ne 5) { Write-Host 'BLOCKED: Windows PowerShell 5.1 is required.'; exit 2 }
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\..'))
foreach ($required in @($OutputRoot, $FixtureRoot)) {
    if ([string]::IsNullOrWhiteSpace($required)) { Write-Host 'BLOCKED: run through the gate, or pass -OutputRoot and -FixtureRoot.'; exit 2 }
    $full = [IO.Path]::GetFullPath($required)
    if (-not $full.StartsWith((Join-Path $repoRoot 'files') + '\', [StringComparison]::OrdinalIgnoreCase)) {
        Write-Host "BLOCKED: outputs and fixtures must stay inside the repository files\ folder: $full"; exit 2
    }
}
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot); $FixtureRoot = [IO.Path]::GetFullPath($FixtureRoot)
[void](New-Item -ItemType Directory -Force -Path $OutputRoot, $FixtureRoot)
$windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$wscriptPath = Join-Path $env:SystemRoot 'System32\wscript.exe'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes   # framework assemblies only; nothing is compiled
$runtimeSource = Join-Path $repoRoot 'scripts\Windows'
foreach ($module in @('Core', 'Selection', 'Integration', 'Actions', 'Maintenance')) {
    . (Join-Path $runtimeSource ("PortableFolderIcons.$module.ps1"))
}
$launcher = 'Setup_and_Run-Portable-Folder-Icons.bat'

$script:Passed = 0; $script:Failed = 0
$script:Log = New-Object Collections.Generic.List[string]
$script:Evidence = [ordered]@{}
$script:RegistryRunRoots = New-Object Collections.Generic.List[object]
function Write-Line([string]$text) { $script:Log.Add($text); Write-Host $text }
function Assert-Gate([bool]$condition, [string]$name, [string]$detail = '') {
    if ($condition) { $script:Passed++; Write-Line "  [PASS] $name" }
    else { $script:Failed++; Write-Line "  [FAIL] $name$(if ($detail) { " :: $detail" })" }
}
function New-SyntheticIco([string]$path, [int]$seed) {
    # Tiny license-safe 16x16 32-bit ICO whose colour encodes $seed, so every file hashes differently.
    $stream = New-Object IO.MemoryStream; $w = New-Object IO.BinaryWriter($stream)
    $w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]1)
    $w.Write([byte]16); $w.Write([byte]16); $w.Write([byte]0); $w.Write([byte]0)
    $w.Write([uint16]1); $w.Write([uint16]32); $w.Write([uint32]1128); $w.Write([uint32]22)
    $w.Write([uint32]40); $w.Write([int32]16); $w.Write([int32]32); $w.Write([uint16]1); $w.Write([uint16]32)
    $w.Write([uint32]0); $w.Write([uint32]1088); $w.Write([int32]0); $w.Write([int32]0); $w.Write([uint32]0); $w.Write([uint32]0)
    for ($i = 0; $i -lt 256; $i++) { $w.Write([byte]($seed % 256)); $w.Write([byte](($seed * 37) % 256)); $w.Write([byte](($seed * 91 + $i) % 256)); $w.Write([byte]255) }
    for ($i = 0; $i -lt 64; $i++) { $w.Write([byte]0) }
    $w.Flush(); [IO.File]::WriteAllBytes($path, $stream.ToArray()); $w.Dispose()
}
function New-TestRegistryRoots {
    $g = [guid]::NewGuid().ToString('N')
    $base = "HKCU:\Software\PortableFolderIcons\Tests\P0A-$g"
    $reference = "PortableFolderIcons.Tests.P0A$g"
    $roots = [ordered]@{
        RegistryRoot = "$base\DirectoryShell\PortableFolderIcons"
        SubcommandsRoot = "HKCU:\Software\Classes\$reference"
        SubcommandsReference = $reference
        IconChoicesRoot = "HKCU:\Software\Classes\$reference.IconChoices"
        IconChoicesReference = "$reference.IconChoices"
        SelectionBrokerClsidRoot = 'HKCU:\Software\Classes\CLSID\{' + [guid]::NewGuid().ToString().ToUpperInvariant() + '}'
        DirectoryShellRoot = "$base\DirectoryShell"
    }
    [void](New-Item -Path $roots.DirectoryShellRoot -Force)  # registration's legacy-entry sweep expects the shell root
    $script:RegistryRunRoots.Add([pscustomobject]@{ Base = $base; Reference = $reference; Clsid = $roots.SelectionBrokerClsidRoot })
    $hash = @{}; foreach ($key in $roots.Keys) { $hash[$key] = $roots[$key] }
    return $hash
}
function Remove-TestRegistryRoots {
    foreach ($run in $script:RegistryRunRoots) {
        $classKeys = @((Get-Item -LiteralPath 'HKCU:\Software\Classes').GetSubKeyNames() |
            Where-Object { $_.StartsWith($run.Reference, [StringComparison]::OrdinalIgnoreCase) } | ForEach-Object { "HKCU:\Software\Classes\$_" })
        foreach ($key in @($run.Clsid) + $classKeys + @($run.Base)) {
            if (Test-Path -LiteralPath $key) { Remove-Item -LiteralPath $key -Recurse -Force }
        }
    }
}
function Get-OwnedTestKeys([hashtable]$roots) {
    $keys = @($roots.RegistryRoot, $roots.SubcommandsRoot, $roots.IconChoicesRoot, $roots.SelectionBrokerClsidRoot) +
        @(Get-PfiOwnedOverflowRegistryPaths -RegistryRoot $roots.RegistryRoot -IconChoicesRoot $roots.IconChoicesRoot)
    return @($keys | Where-Object { Test-Path -LiteralPath $_ })
}
function Get-RegistrySnapshot([hashtable]$roots) {
    $lines = New-Object Collections.Generic.List[string]
    foreach ($top in @(Get-OwnedTestKeys $roots)) {
        foreach ($key in @(@(Get-Item -LiteralPath $top) + @(Get-ChildItem -LiteralPath $top -Recurse))) {
            foreach ($name in @($key.GetValueNames())) { $lines.Add(('{0}|{1}|{2}' -f $key.PSPath, $name, $key.GetValue($name))) }
        }
    }
    return (@($lines | Sort-Object) -join "`n")
}
function Test-RegistryMatchesPlan([hashtable]$roots, [string]$install, $manifest, [bool]$developerMode) {
    # Every value Register-PfiContextMenu plans for this manifest is present with that exact value, and nothing else.
    $brokerRoot = Join-Path $install 'runtime\SelectionHandler'
    $broker = Test-PfiSelectionBrokerArtifact (Join-Path $brokerRoot 'PortableFolderIcons.SelectionBroker.exe') `
        (Read-PfiSelectionBrokerBuildManifest (Join-Path $brokerRoot 'SelectionBroker.build.json'))
    $plan = @(Get-PfiRegistryPlan -Manifest $manifest -InstallRoot $install -RegistryRoot $roots.RegistryRoot `
        -SubcommandsRoot $roots.SubcommandsRoot -SubcommandsReference $roots.SubcommandsReference `
        -IconChoicesRoot $roots.IconChoicesRoot -IconChoicesReference $roots.IconChoicesReference `
        -SelectionBrokerClsidRoot $roots.SelectionBrokerClsidRoot -SelectionBrokerHash $broker.Sha256 -DeveloperMode $developerMode)
    $mismatches = @()
    foreach ($item in $plan) {
        if (-not (Test-Path -LiteralPath $item.Path)) { $mismatches += "missing key $($item.Path)"; continue }
        $actual = (Get-Item -LiteralPath $item.Path).GetValue([string]$item.Name)
        if ([string]$actual -cne [string]$item.Value) { $mismatches += "$($item.Path)|$($item.Name): <$actual> vs <$($item.Value)>" }
    }
    $valueCount = 0
    foreach ($top in @(Get-OwnedTestKeys $roots)) {
        foreach ($key in @(@(Get-Item -LiteralPath $top) + @(Get-ChildItem -LiteralPath $top -Recurse))) { $valueCount += @($key.GetValueNames()).Count }
    }
    if ($valueCount -ne $plan.Count) { $mismatches += "registry holds $valueCount value(s), plan has $($plan.Count)" }
    return [pscustomobject]@{ Ok = ($mismatches.Count -eq 0); Detail = (($mismatches | Select-Object -First 4) -join ' || '); Plan = $plan }
}
function Get-AppliedLabels([hashtable]$roots) {
    $stores = @($roots.IconChoicesRoot) + @(Get-PfiOwnedOverflowRegistryPaths -RegistryRoot $roots.RegistryRoot -IconChoicesRoot $roots.IconChoicesRoot |
        Where-Object { $_ -notlike "$($roots.RegistryRoot).More.*" })
    return @($stores | ForEach-Object { Get-ChildItem -LiteralPath (Join-Path $_ 'shell') -ErrorAction SilentlyContinue } |
        ForEach-Object { [string]$_.GetValue('MUIVerb') } | Sort-Object)
}
function New-InstallCopy([string]$name, [switch]$DeveloperMode) {
    $copy = Join-Path $FixtureRoot $name
    Copy-Item -LiteralPath $script:BaseInstall -Destination $copy -Recurse
    if ($DeveloperMode) { Write-PfiInstalledSettings (New-PfiInstalledSettings -DeveloperMode $true) (Join-Path $copy 'settings.json') }
    return $copy
}
function Get-CachedIconPath([string]$install, [string]$label) {
    $entry = @((Read-PfiManifest (Join-Path $install 'manifest.json')).entries | Where-Object { $_.menuLabel -ceq $label })[0]
    return (Join-Path (Join-Path $install 'icons') $entry.cachedFilename)
}
function Start-Dispatcher {
    param([string]$Install, [string]$Action, $Roots, [string]$Name, [string]$Answers = '', [int]$LockTimeout = -1, [string]$DialogDir = '',
        [switch]$ViaLauncher, [string]$LauncherArguments = '')
    if (-not $DialogDir) { $DialogDir = Join-Path $FixtureRoot "dlg-$Name" }
    [void](New-Item -ItemType Directory -Force -Path $DialogDir)
    $saved = @{}
    foreach ($var in @('PFI_TEST_DIALOG_DIR', 'PFI_TEST_DIALOG_ANSWERS', 'PFI_TEST_REGISTRY_ROOTS', 'PFI_TEST_LOCK_TIMEOUT_SECONDS')) {
        $saved[$var] = [Environment]::GetEnvironmentVariable($var, 'Process')
    }
    try {
        [Environment]::SetEnvironmentVariable('PFI_TEST_DIALOG_DIR', $DialogDir, 'Process')
        [Environment]::SetEnvironmentVariable('PFI_TEST_DIALOG_ANSWERS', $(if ($Answers) { $Answers } else { $null }), 'Process')
        [Environment]::SetEnvironmentVariable('PFI_TEST_REGISTRY_ROOTS', $(if ($null -ne $Roots) { $Roots | ConvertTo-Json -Compress } else { $null }), 'Process')
        [Environment]::SetEnvironmentVariable('PFI_TEST_LOCK_TIMEOUT_SECONDS', $(if ($LockTimeout -ge 0) { [string]$LockTimeout } else { $null }), 'Process')
        if ($ViaLauncher) {
            # Exactly what the registered normal-mode verb runs (Phase 0A.1): Explorer starts wscript.exe, a GUI host with
            # no console, on the installed launcher, which starts the dispatcher with window style 0 and waits for it.
            if (-not $LauncherArguments) { $LauncherArguments = "-Action $Action" }
            $out = $null; $err = $null
            $process = Start-Process -FilePath $wscriptPath -PassThru `
                -ArgumentList ('"{0}" {1}' -f (Join-Path $Install 'runtime\Invoke-PortableFolderIcons.Hidden.vbs'), $LauncherArguments)
        }
        else {
            $dispatcher = Join-Path $Install 'runtime\Invoke-PortableFolderIcons.ps1'
            $out = Join-Path $FixtureRoot "$Name.out.txt"; $err = Join-Path $FixtureRoot "$Name.err.txt"
            $process = Start-Process -FilePath $windowsPowerShell -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError $err `
                -ArgumentList ('-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -Action {1}' -f $dispatcher, $Action)
        }
        $null = $process.Handle
    }
    finally {
        foreach ($var in $saved.Keys) { [Environment]::SetEnvironmentVariable($var, $saved[$var], 'Process') }
    }
    return [pscustomobject]@{ Process = $process; DialogDir = $DialogDir; Out = $out; Err = $err; Name = $Name; ViaLauncher = [bool]$ViaLauncher }
}
function Read-LauncherDialogs([string]$dir) {
    # The launcher's own dialogs, recorded by its verification seam: one UTF-16 file each, the image, a line feed, the message.
    return @(Get-ChildItem -LiteralPath $dir -Filter 'launcher-dialog-*.txt' -File -ErrorAction SilentlyContinue | ForEach-Object {
        $text = [IO.File]::ReadAllText($_.FullName)
        $split = $text.IndexOf("`n")
        if ($split -lt 0) { [pscustomobject]@{ image = ''; message = $text } }
        else { [pscustomobject]@{ image = $text.Substring(0, $split).Trim(); message = $text.Substring($split + 1) } }
    })
}
function Get-ConsoleWindowSnapshot {
    # Visible top-level console and Windows Terminal windows (UI Automation lists visible top-level windows only; a
    # minimized one is still listed) and the running Windows Terminal processes. Read-only.
    $entries = @{}
    $children = [System.Windows.Automation.AutomationElement]::RootElement.FindAll(
        [System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition)
    foreach ($element in $children) {
        try {
            $current = $element.Current
            if ($current.ClassName -in @('CASCADIA_HOSTING_WINDOW_CLASS', 'ConsoleWindowClass')) {
                $entries['w' + $current.NativeWindowHandle] = '{0} "{1}" (pid {2})' -f $current.ClassName, $current.Name, $current.ProcessId
            }
        }
        catch { }   # a window can close while it is being read
    }
    foreach ($terminal in @(Get-Process -Name WindowsTerminal -ErrorAction SilentlyContinue)) {
        $entries['p' + $terminal.Id] = 'WindowsTerminal.exe (pid {0})' -f $terminal.Id
    }
    return [pscustomobject]@{ TopLevelCount = $children.Count; Entries = $entries }
}
function Watch-ConsoleWindows([object[]]$started, $baseline, [int]$graceMilliseconds = 0, [int]$timeoutSeconds = 180) {
    # Polls until every started process has exited (plus a grace period for processes they start) and returns each
    # console or terminal window, or Windows Terminal process, that was not present in the baseline.
    $appeared = @{}
    $deadline = [DateTime]::UtcNow.AddSeconds($timeoutSeconds)
    $graceEnd = $null
    while ([DateTime]::UtcNow -lt $deadline) {
        $now = Get-ConsoleWindowSnapshot
        foreach ($key in @($now.Entries.Keys)) { if (-not $baseline.Entries.ContainsKey($key)) { $appeared[$key] = $now.Entries[$key] } }
        if (@($started | Where-Object { -not $_.Process.HasExited }).Count -eq 0) {
            if ($null -eq $graceEnd) { $graceEnd = [DateTime]::UtcNow.AddMilliseconds($graceMilliseconds) }
            if ([DateTime]::UtcNow -ge $graceEnd) { break }
        }
        Start-Sleep -Milliseconds 100   # test code only: polls a real condition with a deadline
    }
    return @($appeared.Values)
}
function Get-RegisteredCommand([hashtable]$roots, [string]$utility) {
    $verbKey = if ($utility -eq 'Repair') { 'Utility_0200_Repair' } else { 'Utility_0300_Uninstall' }
    return [string](Get-Item -LiteralPath (Join-Path $roots.SubcommandsRoot "shell\$verbKey\command")).GetValue('')
}
function Register-TestMenu([string]$install, [hashtable]$roots) {
    [void](Register-PfiContextMenu -Manifest $baseManifest -InstallRoot $install -RegistryRoot $roots.RegistryRoot -SubcommandsRoot $roots.SubcommandsRoot `
        -SubcommandsReference $roots.SubcommandsReference -IconChoicesRoot $roots.IconChoicesRoot -IconChoicesReference $roots.IconChoicesReference `
        -SelectionBrokerClsidRoot $roots.SelectionBrokerClsidRoot -DirectoryShellRoot $roots.DirectoryShellRoot)
}
function Read-Records([string]$dir, [string]$kind, [int]$processId = 0) {
    $filter = if ($processId -gt 0) { "$kind-$processId.jsonl" } else { "$kind-*.jsonl" }
    $records = @(Get-ChildItem -LiteralPath $dir -Filter $filter -File -ErrorAction SilentlyContinue | ForEach-Object {
        foreach ($line in [IO.File]::ReadAllLines($_.FullName)) { if ($line.Trim()) { $line | ConvertFrom-Json } }
    })
    return @($records | Sort-Object { [long]$_.utcTicks })
}
function Wait-Dispatcher($started, [int]$timeoutSeconds = 180) {
    if (-not $started.Process.WaitForExit($timeoutSeconds * 1000)) {
        & taskkill.exe /T /F /PID $started.Process.Id 2>&1 | Out-Null
        return [pscustomobject]@{ ExitCode = $null; TimedOut = $true; Dialogs = @(); Trace = @(); LauncherDialogs = @(); StdErr = '' }
    }
    # Through the launcher the dispatcher is a grandchild process, so read every record in the run's own dialog folder.
    $recordProcess = if ($started.ViaLauncher) { 0 } else { $started.Process.Id }
    return [pscustomobject]@{
        ExitCode = $started.Process.ExitCode; TimedOut = $false
        Dialogs = @(Read-Records $started.DialogDir 'dialogs' $recordProcess)
        Trace = @(Read-Records $started.DialogDir 'trace' $recordProcess)
        LauncherDialogs = @(Read-LauncherDialogs $started.DialogDir)
        StdErr = $(if ($started.ViaLauncher) { '' } else { ([IO.File]::ReadAllText($started.Err)).Trim() })
    }
}
function Invoke-Dispatcher {
    param([string]$Install, [string]$Action, $Roots, [string]$Name, [string]$Answers = '', [int]$LockTimeout = -1,
        [switch]$ViaLauncher, [string]$LauncherArguments = '')
    return (Wait-Dispatcher (Start-Dispatcher -Install $Install -Action $Action -Roots $Roots -Name $Name -Answers $Answers -LockTimeout $LockTimeout `
        -ViaLauncher:$ViaLauncher -LauncherArguments $LauncherArguments))
}
function Wait-TraceCount([string]$dir, [string]$event, [int]$count, [int]$timeoutSeconds = 120) {
    $deadline = [DateTime]::UtcNow.AddSeconds($timeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        if (@(Read-Records $dir 'trace' | Where-Object { $_.event -eq $event }).Count -ge $count) { return $true }
        Start-Sleep -Milliseconds 200   # test code only: polls a real condition with a deadline
    }
    return $false
}
function Test-LockIntervalsDisjoint([object[]]$trace) {
    $intervals = @()
    foreach ($group in @($trace | Group-Object processId)) {
        $acquired = @($group.Group | Where-Object event -eq 'lock-acquired' | ForEach-Object { [long]$_.utcTicks })
        $released = @($group.Group | Where-Object event -eq 'lock-releasing' | ForEach-Object { [long]$_.utcTicks })
        for ($i = 0; $i -lt $acquired.Count; $i++) {
            if ($i -ge $released.Count) { return $false }
            $intervals += [pscustomobject]@{ Start = $acquired[$i]; End = $released[$i] }
        }
    }
    $sorted = @($intervals | Sort-Object Start)
    for ($i = 1; $i -lt $sorted.Count; $i++) { if ($sorted[$i].Start -lt $sorted[$i - 1].End) { return $false } }
    return ($sorted.Count -gt 0)
}
function Get-FileHashes([string]$dir) {
    $map = @{}
    foreach ($file in @(Get-ChildItem -LiteralPath $dir -File -Filter '*.ico')) { $map[$file.Name] = Get-PfiSha256 $file.FullName }
    return $map
}
function Test-SameHashes($before, $after, [string[]]$except) {
    foreach ($name in $before.Keys) {
        if ($except -contains $name) { continue }
        if (-not $after.ContainsKey($name) -or $after[$name] -ne $before[$name]) { return $false }
    }
    return $true
}
function Test-Message($result, [string[]]$contains, [string[]]$absent = @()) {
    $text = (@($result.Dialogs | ForEach-Object { [string]$_.message }) -join "`n---`n")
    foreach ($needle in $contains) { if (-not $text.Contains($needle)) { return $false } }
    foreach ($needle in $absent) { if ($text.Contains($needle)) { return $false } }
    return $true
}

$lockHolder = $null
try {
    # ------------------------------------------------------------------------------------------------ fixture
    Write-Line '== Fixture: repository copy with 14 synthetic ICOs, installed with -SkipRegistry (fixture root only)'
    $fixtureRepo = Join-Path $FixtureRoot 'repo'
    [void](New-Item -ItemType Directory -Force -Path (Join-Path $fixtureRepo 'scripts\Windows'), (Join-Path $fixtureRepo 'files\ICO-Files'))
    Copy-Item -Path (Join-Path $runtimeSource '*.ps1') -Destination (Join-Path $fixtureRepo 'scripts\Windows')
    Copy-Item -Path (Join-Path $runtimeSource '*.vbs') -Destination (Join-Path $fixtureRepo 'scripts\Windows')
    Copy-Item -LiteralPath (Join-Path $runtimeSource 'SelectionHandler') -Destination (Join-Path $fixtureRepo 'scripts\Windows\SelectionHandler') -Recurse
    [IO.File]::WriteAllText((Join-Path $fixtureRepo 'config.toml'), "[settings]`r`ndeveloper_mode = false`r`n")
    $labels = @('Alpha', 'Bravo', 'Charlie', 'Delta', 'Echo', 'Foxtrot', 'Golf', 'Hotel', 'India', 'Juliet', 'Kilo', 'Lima', 'Mike', 'November')
    for ($i = 0; $i -lt $labels.Count; $i++) { New-SyntheticIco (Join-Path $fixtureRepo ("files\ICO-Files\Folder_{0}.ico" -f $labels[$i])) ($i + 3) }
    $script:BaseInstall = Join-Path $FixtureRoot 'ib'
    & $windowsPowerShell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $runtimeSource 'Install-PortableFolderIcons.ps1') `
        -RepositoryRoot $fixtureRepo -InstallRoot $script:BaseInstall -SkipRegistry *> (Join-Path $FixtureRoot 'fixture-install.txt')
    if ($LASTEXITCODE -ne 0) { Write-Line "BLOCKED: fixture install failed (exit $LASTEXITCODE)"; exit 2 }
    $baseManifest = Read-PfiManifest (Join-Path $script:BaseInstall 'manifest.json')
    $accepted = @($baseManifest.entries | Where-Object validationState -eq 'Accepted')
    Assert-Gate ($accepted.Count -eq 14) 'fixture install accepted the 14 synthetic icons' "$($accepted.Count)"
    $total = $accepted.Count

    # ------------------------------------------------------------------------------------------------ healthy
    Write-Line '== Healthy and repeated Repair; menu and broker dispatch shape unchanged'
    $h1 = New-InstallCopy 'h1'; $r1 = New-TestRegistryRoots
    $res = Invoke-Dispatcher -Install $h1 -Action Repair -Roots $r1 -Name 'h1-a'
    Assert-Gate ($res.ExitCode -eq 0) 'healthy Repair exits 0' "exit $($res.ExitCode) timedOut $($res.TimedOut) stderr <$($res.StdErr)>"
    Assert-Gate ($res.Dialogs.Count -eq 1 -and $res.Dialogs[0].image -eq 'Information') 'healthy Repair shows exactly one Information dialog' "$($res.Dialogs.Count)"
    Assert-Gate (Test-Message $res @('Repair completed.', '- Runtime files and selection broker: valid', "- Cached icons verified: $total of $total",
        "- Explorer menu: recreated with $total icon(s)", '- Developer Mode: off', $launcher) @('partially', 'NOT repaired')) 'healthy Repair reports what it validated and recreated'
    Assert-Gate (-not $res.StdErr) 'healthy Repair writes nothing to stderr' $res.StdErr
    $match = Test-RegistryMatchesPlan $r1 $h1 $baseManifest $false
    Assert-Gate $match.Ok 'healthy Repair registers exactly the full Phase 0B plan (every icon, utilities, overflow, COM)' $match.Detail
    $resetCommand = (Get-Item -LiteralPath (Join-Path $r1.SubcommandsRoot "shell\$script:PfiResetVerbName\command")).GetValue('DelegateExecute')
    $applyVerbs = @(Get-ChildItem -LiteralPath (Join-Path $r1.IconChoicesRoot 'shell'))
    $applyDelegates = @($applyVerbs | ForEach-Object { (Get-Item -LiteralPath (Join-Path $_.PSPath 'command')).GetValue('DelegateExecute') } | Sort-Object -Unique)
    Assert-Gate ($resetCommand -ceq $script:PfiSelectionBrokerClsid -and $applyDelegates.Count -eq 1 -and $applyDelegates[0] -ceq $script:PfiSelectionBrokerClsid) `
        'Reset and Apply still dispatch through the unchanged selection broker CLSID'
    foreach ($utility in @('Repair', 'Uninstall')) {
        $command = Get-RegisteredCommand $r1 $utility
        Assert-Gate ($command -ceq ('"{0}" "{1}" -Action {2}' -f $wscriptPath, (Join-Path $h1 'runtime\Invoke-PortableFolderIcons.Hidden.vbs'), $utility)) `
            "normal mode registers $utility as the installed windowless launcher command (Phase 0A.1)" $command
    }
    $snapshot1 = Get-RegistrySnapshot $r1
    $res2 = Invoke-Dispatcher -Install $h1 -Action Repair -Roots $r1 -Name 'h1-b'
    Assert-Gate ($res2.ExitCode -eq 0 -and $res2.Dialogs.Count -eq 1 -and (Test-Message $res2 @('Repair completed.'))) 'repeated Repair succeeds and reports again (a later request is not coalesced)'
    Assert-Gate (@($res2.Trace | Where-Object event -eq 'repair-start').Count -eq 1) 'repeated Repair really ran (not coalesced into the earlier one)'
    Assert-Gate ((Get-RegistrySnapshot $r1) -ceq $snapshot1) 'repeated Repair leaves an identical registration (idempotent)'
    $script:Evidence['healthy'] = $res.Dialogs[0].message

    $h2 = New-InstallCopy 'h2' -DeveloperMode; $r2 = New-TestRegistryRoots
    $resDev = Invoke-Dispatcher -Install $h2 -Action Repair -Roots $r2 -Name 'h2'
    Assert-Gate ($resDev.ExitCode -eq 0 -and (Test-Message $resDev @('Repair completed.', '- Developer Mode: on'))) 'Developer Mode Repair reports Developer Mode on'
    $matchDev = Test-RegistryMatchesPlan $r2 $h2 $baseManifest $true
    Assert-Gate $matchDev.Ok 'Developer Mode Repair registers exactly the planned menu' $matchDev.Detail
    foreach ($utility in @('Repair', 'Uninstall')) {
        $command = Get-RegisteredCommand $r2 $utility
        Assert-Gate ($command -ceq ('"{0}" -NoLogo -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{1}" -Action {2}' -f
            $windowsPowerShell, (Join-Path $h2 'runtime\Invoke-PortableFolderIcons.ps1'), $utility)) "Developer Mode keeps its unchanged direct PowerShell $utility command" $command
    }

    # ------------------------------------------------------------------------------------------------ damaged icons
    Write-Line '== Missing and corrupt cached icons: diagnose all, keep healthy ones, recover the menu, never claim repair'
    $m1 = New-InstallCopy 'm1'; $rm = New-TestRegistryRoots
    $missingPath = Get-CachedIconPath $m1 'Delta'
    $hashesBefore = Get-FileHashes (Join-Path $m1 'icons'); $manifestBytes = [IO.File]::ReadAllBytes((Join-Path $m1 'manifest.json'))
    Remove-Item -LiteralPath $missingPath -Force
    $resM = Invoke-Dispatcher -Install $m1 -Action Repair -Roots $rm -Name 'm1'
    Assert-Gate ($resM.ExitCode -eq 3) 'missing cached icon: Repair exits 3 (partial)' "exit $($resM.ExitCode) stderr <$($resM.StdErr)>"
    Assert-Gate ($resM.Dialogs.Count -eq 1 -and $resM.Dialogs[0].image -eq 'Warning') 'missing cached icon: one Warning dialog'
    Assert-Gate (Test-Message $resM @('Repair partially completed.', ('- Cached icons verified: {0} of {1}' -f ($total - 1), $total),
        '- Delta: missing; not repaired and left out of the menu', ('- Explorer menu: recreated with {0} icon(s)' -f ($total - 1)), $launcher) @('Repair completed.')) `
        'missing cached icon: message names it as missing and NOT repaired, reports partial recovery and the setup launcher'
    $labelsM = @(Get-AppliedLabels $rm)
    Assert-Gate ($labelsM.Count -eq ($total - 1) -and $labelsM -notcontains 'Delta') 'missing cached icon: menu recreated for the 13 verified icons only' ($labelsM -join ',')
    $filtered = [pscustomobject]@{ schemaVersion = 1; productVersion = '0.1.1'; installedAt = $baseManifest.installedAt
        entries = @($baseManifest.entries | Where-Object { $_.menuLabel -cne 'Delta' }) }
    $matchM = Test-RegistryMatchesPlan $rm $m1 $filtered $false
    Assert-Gate $matchM.Ok 'missing cached icon: registration equals the plan for the healthy icons (utilities, overflow, COM intact)' $matchM.Detail
    Assert-Gate (-not (Test-Path -LiteralPath $missingPath)) 'missing cached icon: Repair does not fabricate or import a replacement'
    Assert-Gate (Test-SameHashes $hashesBefore (Get-FileHashes (Join-Path $m1 'icons')) @(Split-Path -Leaf $missingPath)) 'missing cached icon: every healthy cached icon is unchanged'
    Assert-Gate ([Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $m1 'manifest.json'))) -ceq [Convert]::ToBase64String($manifestBytes)) 'missing cached icon: the installed manifest is not rewritten'
    $script:Evidence['partial-missing'] = $resM.Dialogs[0].message

    $c1 = New-InstallCopy 'c1'; $rc = New-TestRegistryRoots
    $corruptPath = Get-CachedIconPath $c1 'Golf'
    [IO.File]::AppendAllText($corruptPath, 'x'); $corruptBytes = [IO.File]::ReadAllBytes($corruptPath)
    $resC = Invoke-Dispatcher -Install $c1 -Action Repair -Roots $rc -Name 'c1'
    Assert-Gate ($resC.ExitCode -eq 3 -and $resC.Dialogs.Count -eq 1 -and $resC.Dialogs[0].image -eq 'Warning') 'corrupt cached icon: Repair exits 3 with one Warning dialog' "exit $($resC.ExitCode)"
    Assert-Gate (Test-Message $resC @('- Golf: damaged (its content no longer matches its recorded SHA-256); not repaired and left out of the menu', $launcher) @('Repair completed.')) `
        'corrupt cached icon: message names it as damaged and NOT repaired, with the setup launcher'
    Assert-Gate (@(Get-AppliedLabels $rc) -notcontains 'Golf' -and @(Get-AppliedLabels $rc).Count -eq ($total - 1)) 'corrupt cached icon: left out of the menu; the other icons registered'
    Assert-Gate ([Convert]::ToBase64String([IO.File]::ReadAllBytes($corruptPath)) -ceq [Convert]::ToBase64String($corruptBytes)) 'corrupt cached icon: Repair leaves its bytes untouched (no claimed repair)'

    $c2 = New-InstallCopy 'c2'; $rc2 = New-TestRegistryRoots
    Remove-Item -LiteralPath (Get-CachedIconPath $c2 'Alpha') -Force
    [IO.File]::WriteAllText((Get-CachedIconPath $c2 'Bravo'), 'not an icon')
    $resC2 = Invoke-Dispatcher -Install $c2 -Action Repair -Roots $rc2 -Name 'c2'
    Assert-Gate ($resC2.ExitCode -eq 3 -and (Test-Message $resC2 @('- Alpha: missing;', '- Bravo: damaged', ('- Cached icons verified: {0} of {1}' -f ($total - 2), $total),
        ('recreated with {0} icon(s)' -f ($total - 2))))) 'several damaged icons: every one is diagnosed in one result, the rest recovered'

    # ------------------------------------------------------------------------------------------------ startup failures
    Write-Line '== Missing or unloadable runtime modules: one visible dialog naming the file, in both modes; nothing changed'
    $startupCases = @(
        @{ Name = 'x1'; Dev = $false; Action = 'Repair'; File = 'PortableFolderIcons.Maintenance.ps1'; Damage = 'delete'; Expect = 'PortableFolderIcons.Maintenance.ps1 is missing' },
        @{ Name = 'x2'; Dev = $true; Action = 'Repair'; File = 'PortableFolderIcons.Core.ps1'; Damage = 'delete'; Expect = 'PortableFolderIcons.Core.ps1 is missing' },
        @{ Name = 'x3'; Dev = $false; Action = 'Repair'; File = 'PortableFolderIcons.Actions.ps1'; Damage = 'syntax'; Expect = 'PortableFolderIcons.Actions.ps1 could not be loaded' },
        @{ Name = 'x4'; Dev = $false; Action = 'Repair'; File = 'PortableFolderIcons.Selection.ps1'; Damage = 'throw'; Expect = 'PortableFolderIcons.Selection.ps1 could not be loaded (simulated runtime load failure)' },
        @{ Name = 'x5'; Dev = $false; Action = 'Uninstall'; File = 'PortableFolderIcons.Integration.ps1'; Damage = 'delete'; Expect = 'PortableFolderIcons.Integration.ps1 is missing' }
    )
    foreach ($case in $startupCases) {
        $copy = New-InstallCopy $case.Name -DeveloperMode:$case.Dev; $roots = New-TestRegistryRoots
        [void](Register-PfiContextMenu -Manifest $baseManifest -InstallRoot $copy -RegistryRoot $roots.RegistryRoot -SubcommandsRoot $roots.SubcommandsRoot `
            -SubcommandsReference $roots.SubcommandsReference -IconChoicesRoot $roots.IconChoicesRoot -IconChoicesReference $roots.IconChoicesReference `
            -SelectionBrokerClsidRoot $roots.SelectionBrokerClsidRoot -DirectoryShellRoot $roots.DirectoryShellRoot)
        $before = Get-RegistrySnapshot $roots
        $target = Join-Path $copy ('runtime\' + $case.File)
        switch ($case.Damage) {
            'delete' { Remove-Item -LiteralPath $target -Force }
            'syntax' { [IO.File]::WriteAllText($target, "function Broken-PfiModule {`r`n") }
            'throw' { [IO.File]::WriteAllText($target, "throw 'simulated runtime load failure'`r`n") }
        }
        $resX = Invoke-Dispatcher -Install $copy -Action $case.Action -Roots $roots -Name $case.Name -Answers 'Yes,No'
        $mode = if ($case.Dev) { 'Developer Mode' } else { 'normal mode' }
        Assert-Gate ($resX.ExitCode -eq 1 -and $resX.Dialogs.Count -eq 1 -and $resX.Dialogs[0].image -eq 'Error') "$($case.Name) $($case.Action), $($case.File) $($case.Damage) ($mode): exits 1 with exactly one Error dialog" "exit $($resX.ExitCode) dialogs $($resX.Dialogs.Count)"
        Assert-Gate (Test-Message $resX @($case.Expect, "$($case.Action) did not run. Nothing was changed.", $launcher) @('completed')) "$($case.Name): the dialog names the file, says nothing changed and names the setup launcher"
        Assert-Gate ((Get-RegistrySnapshot $roots) -ceq $before) "$($case.Name): the existing registration is untouched"
        if ($case.Name -eq 'x1') { $script:Evidence['startup-missing'] = $resX.Dialogs[0].message }
    }

    # ------------------------------------------------------------------------------------------------ invalid state
    Write-Line '== Invalid settings, manifest and broker; failed registration: visible, guided, nothing claimed'
    $invalidCases = @(
        @{ Name = 'v1'; Damage = { param($c) [IO.File]::WriteAllText((Join-Path $c 'settings.json'), '{') }; Expect = 'Installed settings are malformed' },
        @{ Name = 'v2'; Damage = { param($c) [IO.File]::WriteAllText((Join-Path $c 'manifest.json'), '{') }; Expect = 'Manifest is missing or corrupt' },
        @{ Name = 'v3'; Damage = { param($c) Remove-Item -LiteralPath (Join-Path $c 'runtime\SelectionHandler\PortableFolderIcons.SelectionBroker.exe') -Force }; Expect = 'The required selection broker executable is missing.' }
    )
    foreach ($case in $invalidCases) {
        $copy = New-InstallCopy $case.Name; $roots = New-TestRegistryRoots
        [void](Register-PfiContextMenu -Manifest $baseManifest -InstallRoot $copy -RegistryRoot $roots.RegistryRoot -SubcommandsRoot $roots.SubcommandsRoot `
            -SubcommandsReference $roots.SubcommandsReference -IconChoicesRoot $roots.IconChoicesRoot -IconChoicesReference $roots.IconChoicesReference `
            -SelectionBrokerClsidRoot $roots.SelectionBrokerClsidRoot -DirectoryShellRoot $roots.DirectoryShellRoot)
        $before = Get-RegistrySnapshot $roots
        & $case.Damage $copy
        $resV = Invoke-Dispatcher -Install $copy -Action Repair -Roots $roots -Name $case.Name
        Assert-Gate ($resV.ExitCode -eq 1 -and $resV.Dialogs.Count -eq 1 -and $resV.Dialogs[0].image -eq 'Error') "$($case.Name): Repair exits 1 with one Error dialog" "exit $($resV.ExitCode) stderr <$($resV.StdErr)>"
        Assert-Gate (Test-Message $resV @('Repair could not complete.', $case.Expect, 'Nothing was changed.', $launcher) @('Repair completed.')) "$($case.Name): names the problem ($($case.Expect)) and the setup launcher"
        Assert-Gate ((Get-RegistrySnapshot $roots) -ceq $before) "$($case.Name): the existing registration is untouched"
    }
    $f1 = New-InstallCopy 'f1'; $rf = New-TestRegistryRoots
    [void](New-Item -Path (Join-Path $rf.SelectionBrokerClsidRoot 'LocalServer32') -Force)
    Set-Item -LiteralPath (Join-Path $rf.SelectionBrokerClsidRoot 'LocalServer32') -Value '"C:\Foreign\Other.exe"'
    $resF = Invoke-Dispatcher -Install $f1 -Action Repair -Roots $rf -Name 'f1'
    Assert-Gate ($resF.ExitCode -eq 1 -and $resF.Dialogs.Count -eq 1 -and $resF.Dialogs[0].image -eq 'Error') 'failed registration: Repair exits 1 with one Error dialog' "exit $($resF.ExitCode)"
    Assert-Gate (Test-Message $resF @('could not recreate the Explorer menu', 'not exactly owned by Portable Folder Icons', 'may be missing or incomplete', $launcher) @('Repair completed.')) `
        'failed registration: says the menu could not be recreated and names the setup launcher'
    Assert-Gate ((Get-Item -LiteralPath (Join-Path $rf.SelectionBrokerClsidRoot 'LocalServer32')).GetValue('') -ceq '"C:\Foreign\Other.exe"') 'failed registration: the foreign COM registration is untouched'
    Remove-Item -LiteralPath $rf.SelectionBrokerClsidRoot -Recurse -Force
    $resF2 = Invoke-Dispatcher -Install $f1 -Action Repair -Roots $rf -Name 'f1-retry' -LockTimeout 5
    Assert-Gate ($resF2.ExitCode -eq 0 -and (Test-Message $resF2 @('Repair completed.'))) 'the lock is released after a failed Repair: an immediate retry acquires it and succeeds' "exit $($resF2.ExitCode)"

    # ------------------------------------------------------------------------------------------------ concurrency
    Write-Line '== Concurrent Repair: serialization by the maintenance lock AND coalescing into one result'
    $k1 = New-InstallCopy 'k1'; $rk = New-TestRegistryRoots
    $batchDir = Join-Path $FixtureRoot 'dlg-k1'
    $lockHolder = Enter-PfiMaintenanceLock -InstallRoot $k1 -TimeoutSeconds 5   # every request starts before any Repair
    $batch = @(for ($p = 1; $p -le 4; $p++) { Start-Dispatcher -Install $k1 -Action Repair -Roots $rk -Name "k1-$p" -DialogDir $batchDir })
    $allWaiting = Wait-TraceCount $batchDir 'lock-waiting' 4
    Exit-PfiMaintenanceLock $lockHolder; $lockHolder = $null
    $batchResults = @($batch | ForEach-Object { Wait-Dispatcher $_ })
    $batchTrace = @(Read-Records $batchDir 'trace'); $batchDialogs = @(Read-Records $batchDir 'dialogs')
    Assert-Gate $allWaiting 'four Repair processes all waited on the per-user maintenance lock'
    Assert-Gate (@($batchResults | Where-Object { $_.ExitCode -ne 0 }).Count -eq 0) 'all four concurrent Repair requests exit 0' (($batchResults | ForEach-Object { $_.ExitCode }) -join ',')
    Assert-Gate (@($batchTrace | Where-Object event -eq 'repair-start').Count -eq 1 -and @($batchTrace | Where-Object event -eq 'coalesced').Count -eq 3) `
        'one Repair ran; the three overlapping requests coalesced into its result'
    Assert-Gate ($batchDialogs.Count -eq 1 -and $batchDialogs[0].image -eq 'Information' -and ([string]$batchDialogs[0].message).StartsWith('Repair completed.')) `
        'four overlapping Repair requests show exactly one result dialog and no error' "$($batchDialogs.Count) dialog(s)"
    Assert-Gate (Test-LockIntervalsDisjoint $batchTrace) 'maintenance lock intervals of the four processes never overlap (serialized)'
    Assert-Gate (@($batchResults | Where-Object { $_.StdErr }).Count -eq 0) 'no concurrent Repair process wrote to stderr (no registry race errors)'
    $matchK = Test-RegistryMatchesPlan $rk $k1 $baseManifest $false
    Assert-Gate $matchK.Ok 'after concurrent Repair the registration is complete and exactly as planned' $matchK.Detail
    $script:Evidence['concurrent-repair'] = [ordered]@{ Exits = @($batchResults | ForEach-Object { $_.ExitCode }); Dialogs = $batchDialogs.Count
        RepairsRun = @($batchTrace | Where-Object event -eq 'repair-start').Count; Coalesced = @($batchTrace | Where-Object event -eq 'coalesced').Count }

    Write-Line '== Concurrent Repair and ordinary Uninstall: no mixed state in either order'
    $u1 = New-InstallCopy 'u1'; $ru = New-TestRegistryRoots
    [void](Register-PfiContextMenu -Manifest $baseManifest -InstallRoot $u1 -RegistryRoot $ru.RegistryRoot -SubcommandsRoot $ru.SubcommandsRoot `
        -SubcommandsReference $ru.SubcommandsReference -IconChoicesRoot $ru.IconChoicesRoot -IconChoicesReference $ru.IconChoicesReference `
        -SelectionBrokerClsidRoot $ru.SelectionBrokerClsidRoot -DirectoryShellRoot $ru.DirectoryShellRoot)
    $mixDir = Join-Path $FixtureRoot 'dlg-u1'
    $lockHolder = Enter-PfiMaintenanceLock -InstallRoot $u1 -TimeoutSeconds 5
    $un = Start-Dispatcher -Install $u1 -Action Uninstall -Roots $ru -Name 'u1-uninstall' -Answers 'Yes,No' -DialogDir $mixDir
    $re = Start-Dispatcher -Install $u1 -Action Repair -Roots $ru -Name 'u1-repair' -DialogDir $mixDir
    $bothWaiting = Wait-TraceCount $mixDir 'lock-waiting' 2
    Exit-PfiMaintenanceLock $lockHolder; $lockHolder = $null
    $unRes = Wait-Dispatcher $un; $reRes = Wait-Dispatcher $re
    $mixTrace = @(Read-Records $mixDir 'trace')
    $repairFirst = $false
    $unAcquired = @($unRes.Trace | Where-Object event -eq 'lock-acquired')
    $reAcquired = @($reRes.Trace | Where-Object event -eq 'lock-acquired')
    if ($unAcquired.Count -gt 0 -and $reAcquired.Count -gt 0) { $repairFirst = [long]$reAcquired[0].utcTicks -lt [long]$unAcquired[0].utcTicks }
    Assert-Gate $bothWaiting 'Uninstall (after its unchanged prompts) and Repair both waited on the same lock'
    Assert-Gate ($unRes.ExitCode -eq 0 -and (Test-Message $unRes @('Remove the Folder Icons context menu and installed runtime?', 'Optional cache purge:', 'Uninstall completed. Cached icons were preserved at:'))) `
        'Uninstall kept its two prompts and completed' "exit $($unRes.ExitCode)"
    if ($repairFirst) {
        Assert-Gate ($reRes.ExitCode -eq 0 -and (Test-Message $reRes @('Repair completed.'))) 'order Repair-then-Uninstall: Repair completed before the Uninstall started'
    }
    else {
        Assert-Gate ($reRes.ExitCode -eq 1 -and (Test-Message $reRes @('being uninstalled, or another request has already uninstalled it', 'Repair did not change anything.', $launcher))) `
            'order Uninstall-then-Repair: Repair refuses and changes nothing' "exit $($reRes.ExitCode)"
    }
    Assert-Gate (@(Get-OwnedTestKeys $ru).Count -eq 0) 'final state is uninstalled: no registration was recreated after the Uninstall (no mixed state)'
    Assert-Gate (Test-Path -LiteralPath (Join-Path $u1 $script:PfiUninstallCleanupMarker) -PathType Leaf) 'the scheduled runtime cleanup marker is present'
    Assert-Gate (Test-LockIntervalsDisjoint $mixTrace) 'Repair and Uninstall lock intervals never overlap'
    Assert-Gate (-not $unRes.StdErr -and -not $reRes.StdErr) 'neither process wrote to stderr'
    $script:Evidence['repair-uninstall-order'] = $(if ($repairFirst) { 'Repair then Uninstall' } else { 'Uninstall then Repair' })

    $reAfter = Invoke-Dispatcher -Install $u1 -Action Repair -Roots $ru -Name 'u1-repair-after'
    Assert-Gate ($reAfter.ExitCode -eq 1 -and $reAfter.Dialogs.Count -eq 1 -and (Test-Message $reAfter @('being uninstalled, or another request has already uninstalled it', 'Repair did not change anything.', $launcher))) `
        'Repair after an ordinary Uninstall refuses with one guided dialog'
    Assert-Gate (@(Get-OwnedTestKeys $ru).Count -eq 0) 'Repair after Uninstall recreated nothing'
    $unAgain = Invoke-Dispatcher -Install $u1 -Action Uninstall -Roots $ru -Name 'u1-uninstall-again' -Answers 'Yes,No'
    Assert-Gate ($unAgain.ExitCode -eq 0 -and @($unAgain.Dialogs | Where-Object image -eq 'Error').Count -eq 0 -and
        (Test-Message $unAgain @('has already been uninstalled by another request. This request changed nothing, including the cached icons.'))) `
        'a second confirmed Uninstall reports the earlier removal instead of a misleading error'

    # ------------------------------------------------------------------------------------------------ cancel, timeout, abandoned
    Write-Line '== Cancellation, timeout and abandoned lock'
    $n1 = New-InstallCopy 'n1'; $rn = New-TestRegistryRoots
    [void](Register-PfiContextMenu -Manifest $baseManifest -InstallRoot $n1 -RegistryRoot $rn.RegistryRoot -SubcommandsRoot $rn.SubcommandsRoot `
        -SubcommandsReference $rn.SubcommandsReference -IconChoicesRoot $rn.IconChoicesRoot -IconChoicesReference $rn.IconChoicesReference `
        -SelectionBrokerClsidRoot $rn.SelectionBrokerClsidRoot -DirectoryShellRoot $rn.DirectoryShellRoot)
    $beforeN = Get-RegistrySnapshot $rn
    $resN = Invoke-Dispatcher -Install $n1 -Action Uninstall -Roots $rn -Name 'n1' -Answers 'No'
    Assert-Gate ($resN.ExitCode -eq 2 -and $resN.Dialogs.Count -eq 1 -and @($resN.Trace | Where-Object event -like 'lock-*').Count -eq 0) 'declined Uninstall exits 2 after one prompt and never takes the lock'
    Assert-Gate ((Get-RegistrySnapshot $rn) -ceq $beforeN -and (Test-Path -LiteralPath (Join-Path $n1 'runtime\Invoke-PortableFolderIcons.ps1'))) 'declined Uninstall changes nothing'

    $lockHolder = Enter-PfiMaintenanceLock -InstallRoot $n1 -TimeoutSeconds 5
    $resT = Invoke-Dispatcher -Install $n1 -Action Repair -Roots $rn -Name 't1-repair' -LockTimeout 2
    $resTu = Invoke-Dispatcher -Install $n1 -Action Uninstall -Roots $rn -Name 't1-uninstall' -LockTimeout 2 -Answers 'Yes,No'
    Exit-PfiMaintenanceLock $lockHolder; $lockHolder = $null
    Assert-Gate ($resT.ExitCode -eq 1 -and $resT.Dialogs.Count -eq 1 -and $resT.Dialogs[0].image -eq 'Error' -and
        (Test-Message $resT @('Another Portable Folder Icons Repair or Uninstall is still running.', 'waited 2 seconds', 'Repair did not run.', $launcher))) 'Repair that cannot get the lock times out with one guided dialog'
    Assert-Gate ($resTu.ExitCode -eq 1 -and (Test-Message $resTu @('Uninstall could not complete.', 'still running', 'Nothing was changed.', $launcher))) 'Uninstall that cannot get the lock times out, saying nothing was changed'
    Assert-Gate ((Get-RegistrySnapshot $rn) -ceq $beforeN -and -not (Test-Path -LiteralPath (Join-Path $n1 $script:PfiUninstallCleanupMarker))) 'timed-out requests changed nothing'
    $script:Evidence['timeout'] = $resT.Dialogs[0].message

    # A holder that ends without releasing: a script takes the lock, signals, then exits when told to (no release).
    # The named kernel mutex is destroyed when its last handle closes, so with nobody waiting nothing is left behind;
    # a request that is already waiting receives it as abandoned and must take it over.
    $abandonScript = Join-Path $FixtureRoot 'abandon-lock.ps1'
    [IO.File]::WriteAllText($abandonScript, (@(
        'param([string]$InstallRoot, [string]$Signal)'
        "`$ErrorActionPreference = 'Stop'"
        (". '{0}'" -f (Join-Path $runtimeSource 'PortableFolderIcons.Maintenance.ps1').Replace("'", "''"))
        '$lock = Enter-PfiMaintenanceLock -InstallRoot $InstallRoot -TimeoutSeconds 5'
        '[IO.File]::WriteAllText($Signal + ''.held'', ''held'')'
        '$deadline = [DateTime]::UtcNow.AddSeconds(120)'
        'while (-not (Test-Path -LiteralPath ($Signal + ''.go'')) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100 }'
        'exit 0'
    ) -join "`r`n"), (New-Object Text.UTF8Encoding($true)))
    function Start-AbandoningHolder([string]$install, [string]$signal) {
        $holder = Start-Process -FilePath $windowsPowerShell -NoNewWindow -PassThru `
            -ArgumentList ('-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -InstallRoot "{1}" -Signal "{2}"' -f $abandonScript, $install, $signal)
        $null = $holder.Handle
        $deadline = [DateTime]::UtcNow.AddSeconds(60)
        while (-not (Test-Path -LiteralPath "$signal.held") -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100 }
        return $holder
    }

    $a0 = New-InstallCopy 'a0'; $ra0 = New-TestRegistryRoots
    $holder0 = Start-AbandoningHolder $a0 (Join-Path $FixtureRoot 'a0-signal')
    [IO.File]::WriteAllText((Join-Path $FixtureRoot 'a0-signal.go'), 'go')
    $holderExited = $holder0.WaitForExit(60000)
    Assert-Gate ($holderExited -and $holder0.ExitCode -eq 0) 'abandoned lock, nobody waiting: the holder ended without releasing the lock'
    $resA0 = Invoke-Dispatcher -Install $a0 -Action Repair -Roots $ra0 -Name 'a0' -LockTimeout 5
    Assert-Gate ($resA0.ExitCode -eq 0 -and (Test-Message $resA0 @('Repair completed.'))) 'abandoned lock, nobody waiting: a later Repair is never blocked by it' "exit $($resA0.ExitCode)"

    $a1 = New-InstallCopy 'a1'; $ra = New-TestRegistryRoots
    $holder1 = Start-AbandoningHolder $a1 (Join-Path $FixtureRoot 'a1-signal')
    $waiting = Start-Dispatcher -Install $a1 -Action Repair -Roots $ra -Name 'a1' -LockTimeout 60
    $isWaiting = Wait-TraceCount $waiting.DialogDir 'lock-waiting' 1
    [IO.File]::WriteAllText((Join-Path $FixtureRoot 'a1-signal.go'), 'go')
    [void]$holder1.WaitForExit(60000)
    $resA = Wait-Dispatcher $waiting
    Assert-Gate $isWaiting 'abandoned lock, request waiting: the Repair was waiting when the holder ended'
    Assert-Gate ($resA.ExitCode -eq 0 -and (Test-Message $resA @('Repair completed.', 'A previous Repair or Uninstall ended before it finished.'))) 'abandoned lock, request waiting: Repair takes it over, completes and says the earlier operation was interrupted' "exit $($resA.ExitCode)"
    Assert-Gate (@($resA.Trace | Where-Object { $_.event -eq 'lock-acquired' -and $_.detail -eq 'abandoned' }).Count -eq 1) 'abandoned lock, request waiting: ownership was recovered as abandoned'
    $matchA = Test-RegistryMatchesPlan $ra $a1 $baseManifest $false
    Assert-Gate $matchA.Ok 'abandoned lock: Repair rebuilt the complete registration' $matchA.Detail

    # ------------------------------------------------------------------------------------------------ windowless launcher
    Write-Line '== Phase 0A.1 windowless launcher: the registered normal-mode command opens no console or terminal window'
    $consoleStartup = Get-Item -LiteralPath 'HKCU:\Console\%%Startup' -ErrorAction SilentlyContinue
    $delegation = if ($null -eq $consoleStartup) { 'no HKCU\Console\%%Startup key' }
        elseif ([string]::IsNullOrEmpty([string]$consoleStartup.GetValue('DelegationTerminal'))) { 'no delegation values (Let Windows decide)' }
        else { 'DelegationConsole {0}, DelegationTerminal {1}' -f $consoleStartup.GetValue('DelegationConsole'), $consoleStartup.GetValue('DelegationTerminal') }
    $script:Evidence['default-terminal-setting'] = $delegation
    Write-Line "  default terminal setting: $delegation"

    $w1 = New-InstallCopy 'w1'; $rw1 = New-TestRegistryRoots
    $baseline = Get-ConsoleWindowSnapshot
    Assert-Gate ($baseline.TopLevelCount -gt 0) 'the window observer sees the interactive desktop (UI Automation lists top-level windows)' "$($baseline.TopLevelCount)"
    $startedW1 = Start-Dispatcher -Install $w1 -Action Repair -Roots $rw1 -Name 'w1' -ViaLauncher
    $windowsW1 = @(Watch-ConsoleWindows @($startedW1) $baseline)
    $resW1 = Wait-Dispatcher $startedW1
    Assert-Gate ($resW1.ExitCode -eq 0) 'launcher Repair: wscript.exe returns the dispatcher result 0' "exit $($resW1.ExitCode) timedOut $($resW1.TimedOut)"
    Assert-Gate ($resW1.Dialogs.Count -eq 1 -and $resW1.Dialogs[0].image -eq 'Information' -and
        (Test-Message $resW1 @('Repair completed.', "- Cached icons verified: $total of $total", "- Explorer menu: recreated with $total icon(s)", $launcher))) `
        'launcher Repair: exactly one Information result dialog with the unchanged text' "$($resW1.Dialogs.Count)"
    Assert-Gate ($resW1.LauncherDialogs.Count -eq 0) 'launcher Repair: the launcher adds no dialog of its own on success'
    Assert-Gate ($windowsW1.Count -eq 0) 'launcher Repair: no console or Windows Terminal window, and no Windows Terminal process, appeared' ($windowsW1 -join '; ')
    $matchW1 = Test-RegistryMatchesPlan $rw1 $w1 $baseManifest $false
    Assert-Gate $matchW1.Ok 'launcher Repair: the registration is complete and exactly as planned' $matchW1.Detail
    Assert-Gate ((Get-RegisteredCommand $rw1 'Repair') -ceq ('"{0}" "{1}" -Action Repair' -f $wscriptPath, (Join-Path $w1 'runtime\Invoke-PortableFolderIcons.Hidden.vbs'))) `
        'launcher Repair re-registers the windowless command it was started from'

    $w2 = New-InstallCopy 'w2'; $rw2 = New-TestRegistryRoots
    $w2Dir = Join-Path $FixtureRoot 'dlg-w2'
    $baseline = Get-ConsoleWindowSnapshot
    $lockHolder = Enter-PfiMaintenanceLock -InstallRoot $w2 -TimeoutSeconds 5   # every request starts before any Repair
    $w2Batch = @(for ($p = 1; $p -le 4; $p++) { Start-Dispatcher -Install $w2 -Action Repair -Roots $rw2 -Name "w2-$p" -DialogDir $w2Dir -ViaLauncher })
    $w2Waiting = Wait-TraceCount $w2Dir 'lock-waiting' 4
    Exit-PfiMaintenanceLock $lockHolder; $lockHolder = $null
    $windowsW2 = @(Watch-ConsoleWindows $w2Batch $baseline)
    $w2Results = @($w2Batch | ForEach-Object { Wait-Dispatcher $_ })
    $w2Trace = @(Read-Records $w2Dir 'trace'); $w2Dialogs = @(Read-Records $w2Dir 'dialogs')
    Assert-Gate $w2Waiting 'four overlapping launcher Repairs all waited on the maintenance lock'
    Assert-Gate (@($w2Results | Where-Object { $_.ExitCode -ne 0 }).Count -eq 0) 'four overlapping launcher Repairs all exit 0' (($w2Results | ForEach-Object { $_.ExitCode }) -join ',')
    Assert-Gate (@($w2Trace | Where-Object event -eq 'repair-start').Count -eq 1 -and @($w2Trace | Where-Object event -eq 'coalesced').Count -eq 3) `
        'four overlapping launcher Repairs: one ran, three coalesced into its result'
    Assert-Gate ($w2Dialogs.Count -eq 1 -and $w2Dialogs[0].image -eq 'Information' -and ([string]$w2Dialogs[0].message).StartsWith('Repair completed.') -and
        @(Read-LauncherDialogs $w2Dir).Count -eq 0) 'four overlapping launcher Repairs show exactly one result dialog and no error' "$($w2Dialogs.Count) dialog(s)"
    Assert-Gate (Test-LockIntervalsDisjoint $w2Trace) 'four overlapping launcher Repairs never overlap inside the lock'
    Assert-Gate ($windowsW2.Count -eq 0) 'four overlapping launcher Repairs opened no console or terminal window' ($windowsW2 -join '; ')
    $matchW2 = Test-RegistryMatchesPlan $rw2 $w2 $baseManifest $false
    Assert-Gate $matchW2.Ok 'after overlapping launcher Repairs the registration is complete and exactly as planned' $matchW2.Detail
    $script:Evidence['launcher-concurrent-repair'] = [ordered]@{ Exits = @($w2Results | ForEach-Object { $_.ExitCode }); Dialogs = $w2Dialogs.Count
        RepairsRun = @($w2Trace | Where-Object event -eq 'repair-start').Count; Coalesced = @($w2Trace | Where-Object event -eq 'coalesced').Count
        WindowsSeen = $windowsW2.Count }

    # Install root with spaces, non-ASCII characters, an ampersand, an apostrophe and parentheses (built from code points).
    $unicodeInstallName = 'w3 ' + [char]0x00DC + [char]0x6F22 + [char]0x03A9 + " & 'q' (x)"
    $w3 = New-InstallCopy $unicodeInstallName; $rw3 = New-TestRegistryRoots
    $resW3 = Invoke-Dispatcher -Install $w3 -Action Repair -Roots $rw3 -Name 'w3' -ViaLauncher
    Assert-Gate ($resW3.ExitCode -eq 0 -and $resW3.Dialogs.Count -eq 1 -and (Test-Message $resW3 @('Repair completed.')) -and $resW3.LauncherDialogs.Count -eq 0) `
        'launcher Repair from a Unicode install path with &, apostrophe and parentheses completes with one result' "exit $($resW3.ExitCode)"
    $matchW3 = Test-RegistryMatchesPlan $rw3 $w3 $baseManifest $false
    Assert-Gate ($matchW3.Ok -and (Get-RegisteredCommand $rw3 'Uninstall') -ceq ('"{0}" "{1}" -Action Uninstall' -f $wscriptPath, (Join-Path $w3 'runtime\Invoke-PortableFolderIcons.Hidden.vbs'))) `
        'Unicode install path: commands and icon paths registered exactly, quoted, without loss' $matchW3.Detail

    $w4 = New-InstallCopy 'w4'; $rw4 = New-TestRegistryRoots
    Register-TestMenu $w4 $rw4
    $beforeW4 = Get-RegistrySnapshot $rw4
    $baseline = Get-ConsoleWindowSnapshot
    $startedW4 = Start-Dispatcher -Install $w4 -Action Uninstall -Roots $rw4 -Name 'w4' -Answers 'No' -ViaLauncher
    $windowsW4 = @(Watch-ConsoleWindows @($startedW4) $baseline)
    $resW4 = Wait-Dispatcher $startedW4
    Assert-Gate ($resW4.ExitCode -eq 2 -and $resW4.Dialogs.Count -eq 1 -and $resW4.Dialogs[0].buttons -eq 'YesNo' -and
        (Test-Message $resW4 @('Remove the Folder Icons context menu and installed runtime?')) -and @($resW4.Trace | Where-Object event -like 'lock-*').Count -eq 0) `
        'launcher Uninstall, declined: exits 2 after its one unchanged prompt and never takes the lock' "exit $($resW4.ExitCode)"
    Assert-Gate ((Get-RegistrySnapshot $rw4) -ceq $beforeW4 -and (Test-Path -LiteralPath (Join-Path $w4 'runtime\Invoke-PortableFolderIcons.ps1')) -and
        -not (Test-Path -LiteralPath (Join-Path $w4 $script:PfiUninstallCleanupMarker))) 'launcher Uninstall, declined: nothing changed'
    Assert-Gate ($resW4.LauncherDialogs.Count -eq 0 -and $windowsW4.Count -eq 0) 'launcher Uninstall, declined: no launcher dialog and no console or terminal window' ($windowsW4 -join '; ')

    $w5 = New-InstallCopy 'w5'; $rw5 = New-TestRegistryRoots
    Register-TestMenu $w5 $rw5
    $baseline = Get-ConsoleWindowSnapshot
    $startedW5 = Start-Dispatcher -Install $w5 -Action Uninstall -Roots $rw5 -Name 'w5' -Answers 'Yes,No' -ViaLauncher
    $windowsW5 = @(Watch-ConsoleWindows @($startedW5) $baseline 3000)   # grace: the hidden cleanup helper it starts
    $resW5 = Wait-Dispatcher $startedW5
    Assert-Gate ($resW5.ExitCode -eq 0 -and (Test-Message $resW5 @('Remove the Folder Icons context menu and installed runtime?', 'Optional cache purge:',
        'Uninstall completed. Cached icons were preserved at:')) -and $resW5.LauncherDialogs.Count -eq 0) 'launcher Uninstall, confirmed: unchanged prompts and result' "exit $($resW5.ExitCode)"
    Assert-Gate (@(Get-OwnedTestKeys $rw5).Count -eq 0 -and (Test-Path -LiteralPath (Join-Path $w5 $script:PfiUninstallCleanupMarker) -PathType Leaf)) `
        'launcher Uninstall, confirmed: registration removed and the runtime cleanup scheduled, as before'
    Assert-Gate ($windowsW5.Count -eq 0) 'launcher Uninstall, confirmed: no console or terminal window from the Uninstall or its hidden cleanup helper' ($windowsW5 -join '; ')

    foreach ($action in @('Repair', 'Uninstall')) {
        $w6 = New-InstallCopy "w6-$action"; $rw6 = New-TestRegistryRoots
        Register-TestMenu $w6 $rw6
        $beforeW6 = Get-RegistrySnapshot $rw6
        Remove-Item -LiteralPath (Join-Path $w6 'runtime\Invoke-PortableFolderIcons.ps1') -Force
        $resW6 = Invoke-Dispatcher -Install $w6 -Action $action -Roots $rw6 -Name "w6-$action" -Answers 'Yes,No' -ViaLauncher
        $launcherText = @($resW6.LauncherDialogs | ForEach-Object { [string]$_.message }) -join "`n---`n"
        Assert-Gate ($resW6.ExitCode -eq 1 -and $resW6.LauncherDialogs.Count -eq 1 -and $resW6.LauncherDialogs[0].image -eq 'Error' -and $resW6.Dialogs.Count -eq 0) `
            "missing dispatcher, ${action}: the launcher exits 1 with exactly one Error dialog of its own" "exit $($resW6.ExitCode) launcher dialogs $($resW6.LauncherDialogs.Count)"
        Assert-Gate ($launcherText.Contains('installed runtime file Invoke-PortableFolderIcons.ps1 is missing') -and
            $launcherText.Contains("$action did not run. Nothing was changed.") -and $launcherText.Contains($launcher)) `
            "missing dispatcher, ${action}: the dialog names the file, says nothing changed and names the setup launcher" $launcherText
        Assert-Gate ((Get-RegistrySnapshot $rw6) -ceq $beforeW6) "missing dispatcher, ${action}: the registration is untouched"
        if ($action -eq 'Repair') { $script:Evidence['launcher-missing-dispatcher'] = $launcherText }
    }

    $w7 = New-InstallCopy 'w7'; $rw7 = New-TestRegistryRoots
    Remove-Item -LiteralPath (Join-Path $w7 'runtime\PortableFolderIcons.Maintenance.ps1') -Force
    $resW7 = Invoke-Dispatcher -Install $w7 -Action Repair -Roots $rw7 -Name 'w7' -ViaLauncher
    Assert-Gate ($resW7.ExitCode -eq 1 -and $resW7.Dialogs.Count -eq 1 -and $resW7.Dialogs[0].image -eq 'Error' -and $resW7.LauncherDialogs.Count -eq 0 -and
        (Test-Message $resW7 @('PortableFolderIcons.Maintenance.ps1 is missing', 'Repair did not run. Nothing was changed.', $launcher))) `
        "missing runtime module through the launcher: the dispatcher's one guarded Error dialog still appears and the launcher adds none" "exit $($resW7.ExitCode)"
    Assert-Gate (@(Get-OwnedTestKeys $rw7).Count -eq 0) 'missing runtime module through the launcher: nothing was registered'

    $w8 = New-InstallCopy 'w8'; $rw8 = New-TestRegistryRoots
    [IO.File]::WriteAllText((Join-Path $w8 'runtime\Invoke-PortableFolderIcons.ps1'), "exit 7`r`n")
    $resW8 = Invoke-Dispatcher -Install $w8 -Action Repair -Roots $rw8 -Name 'w8' -ViaLauncher
    $launcherText = @($resW8.LauncherDialogs | ForEach-Object { [string]$_.message }) -join "`n---`n"
    Assert-Gate ($resW8.ExitCode -eq 1 -and $resW8.LauncherDialogs.Count -eq 1 -and $resW8.LauncherDialogs[0].image -eq 'Error' -and
        $launcherText.Contains('Repair ended before Portable Folder Icons could report a result (Windows PowerShell exit code 7).') -and $launcherText.Contains($launcher)) `
        'unrecognised dispatcher exit through the launcher: one guided Error dialog and exit 1' "exit $($resW8.ExitCode) <$launcherText>"

    $w9 = New-InstallCopy 'w9'
    $badLines = @('-Action', '-Action Repair Extra', '-Action Bogus', '-Action Repair -TargetPath "C:\x"', '-Action Uninstall -IconHash x -TargetPath "C:\x"')
    for ($b = 0; $b -lt $badLines.Count; $b++) {
        $resW9 = Invoke-Dispatcher -Install $w9 -Action '' -Roots $null -Name "w9-$b" -ViaLauncher -LauncherArguments $badLines[$b]
        Assert-Gate ($resW9.ExitCode -eq 64 -and $resW9.Dialogs.Count -eq 0 -and $resW9.Trace.Count -eq 0 -and $resW9.LauncherDialogs.Count -eq 0) `
            "the launcher rejects '$($badLines[$b])' with exit 64 and starts nothing" "exit $($resW9.ExitCode)"
    }

    # Existing Apply/Reset/selection arguments still reach the dispatcher unchanged. Each case stops at validation
    # before anything is written or any Explorer notification is sent.
    $w10 = New-InstallCopy 'w10'
    $unicodeTarget = Join-Path $FixtureRoot ('w10 target ' + [char]0x00E9 + [char]0x4E2D + " & 'x' (1)")
    [void](New-Item -ItemType Directory -Path $unicodeTarget)
    $legacyCases = @(
        @{ Name = 'w10-apply'; Line = ('-Action Apply -IconHash {0} -TargetPath "{1}"' -f ('0' * 64), $unicodeTarget); Expect = 'The requested icon is not present in the active manifest.' },
        @{ Name = 'w10-reset'; Line = ('-Action Reset -TargetPath "{0} missing"' -f $unicodeTarget); Expect = 'The selected target is missing or is not a directory.' },
        @{ Name = 'w10-selection'; Line = ('-SelectionToken {0} -PayloadHash {1}' -f ('a' * 32), ('b' * 64)); Expect = 'The Explorer selection payload is missing or has already been consumed.' }
    )
    foreach ($case in $legacyCases) {
        $resW10 = Invoke-Dispatcher -Install $w10 -Action '' -Roots $null -Name $case.Name -ViaLauncher -LauncherArguments $case.Line
        Assert-Gate ($resW10.ExitCode -eq 1 -and $resW10.Dialogs.Count -eq 1 -and $resW10.Dialogs[0].image -eq 'Error' -and
            (Test-Message $resW10 @($case.Expect)) -and $resW10.LauncherDialogs.Count -eq 0) "$($case.Name): the launcher still forwards it unchanged (dispatcher reports: $($case.Expect))" "exit $($resW10.ExitCode)"
    }
    Assert-Gate (@(Get-ChildItem -LiteralPath $unicodeTarget -Force).Count -eq 0) 'Apply through the launcher reached the existing Unicode folder (icon check, not a missing-folder error) and wrote nothing'
}
catch {
    $script:Failed++
    Write-Line "  [FAIL] maintenance reliability aborted: $($_.Exception.Message) at $($_.InvocationInfo.PositionMessage)"
}
finally {
    if ($null -ne $lockHolder) { Exit-PfiMaintenanceLock $lockHolder }
    try { Remove-TestRegistryRoots } catch { $script:Failed++; Write-Line "  [FAIL] test registry cleanup: $($_.Exception.Message)" }
    $left = @($script:RegistryRunRoots | Where-Object { (Test-Path -LiteralPath $_.Base) -or (Test-Path -LiteralPath $_.Clsid) })
    if ($left.Count -eq 0) { $script:Passed++; Write-Line '  [PASS] every GUID-named test registry root was removed' }
    else { $script:Failed++; Write-Line "  [FAIL] $($left.Count) test registry root(s) remain" }
    $report = [ordered]@{ Passed = $script:Passed; Failed = $script:Failed; Evidence = $script:Evidence }
    [IO.File]::WriteAllText((Join-Path $OutputRoot 'maintenance-reliability.json'), ($report | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllLines((Join-Path $OutputRoot 'maintenance-reliability.log'), [string[]]$script:Log, (New-Object Text.UTF8Encoding($false)))
    # Drop the bulky install copies (each holds every cached ICO); dialogs, traces and reports stay as evidence.
    foreach ($bulky in @(Get-ChildItem -LiteralPath $FixtureRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike 'dlg-*' })) {
        Remove-Item -LiteralPath $bulky.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
}
Write-Host ('Maintenance reliability: {0} passed, {1} failed' -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
exit 0
