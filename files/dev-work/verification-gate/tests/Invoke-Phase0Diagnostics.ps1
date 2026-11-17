# Phase 0 diagnostics for the chooser, Reset, Repair and ordinary Uninstall.
#
# Two kinds of result, kept separate:
#   [PASS]/[FAIL]  regression assertions about behaviour that must hold now. They decide the exit code.
#   [FINDING]      characterization of a reported or newly found defect. Findings never change the exit
#                  code; they are evidence for the plan. Each one names its classification.
#
# Safety: every folder fixture, install root and log lives under the gate run's temp/artifacts folders
# (inside the repository). Registry writes use only GUID-named roots that the product's own guard
# recognizes as test roots, and are removed in finally. The production install, production HKCU keys,
# user folders and Explorer windows are only read, never changed. No compiled executable is launched.
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
[void](New-Item -ItemType Directory -Force -Path $OutputRoot, $FixtureRoot)
$windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$runtimeSource = Join-Path $repoRoot 'scripts\Windows'
foreach ($module in @('Core', 'Selection', 'Integration', 'Actions', 'Maintenance')) {
    . (Join-Path $runtimeSource ("PortableFolderIcons.$module.ps1"))
}
Add-Type -AssemblyName System.Drawing

$script:Passed = 0; $script:Failed = 0
$script:Findings = New-Object Collections.Generic.List[object]
$script:Log = New-Object Collections.Generic.List[string]
function Write-Line([string]$text) { $script:Log.Add($text); Write-Host $text }
function Assert-Gate([bool]$condition, [string]$name, [string]$detail = '') {
    if ($condition) { $script:Passed++; Write-Line "  [PASS] $name" }
    else { $script:Failed++; Write-Line "  [FAIL] $name$(if ($detail) { " :: $detail" })" }
}
function Add-Finding([string]$area, [string]$classification, [string]$text) {
    $script:Findings.Add([pscustomobject][ordered]@{ Area = $area; Classification = $classification; Finding = $text })
    Write-Line "  [FINDING] $area [$classification] $text"
}
function Invoke-Child([string[]]$arguments, [int]$timeoutSeconds, [string]$name) {
    # Starts Windows PowerShell only (signed inbox binary); never a compiled project executable.
    $out = Join-Path $FixtureRoot "$name.out.txt"; $err = Join-Path $FixtureRoot "$name.err.txt"
    $quoted = ($arguments | ForEach-Object { if ($_ -match '[\s"]') { '"' + $_.Replace('"', '\"') + '"' } else { $_ } }) -join ' '
    $process = Start-Process -FilePath $windowsPowerShell -ArgumentList $quoted -NoNewWindow -PassThru `
        -RedirectStandardOutput $out -RedirectStandardError $err
    $null = $process.Handle
    if (-not $process.WaitForExit($timeoutSeconds * 1000)) {
        & taskkill.exe /T /F /PID $process.Id 2>&1 | Out-Null
        return [pscustomobject]@{ ExitCode = $null; TimedOut = $true; StdOut = ''; StdErr = '' }
    }
    return [pscustomobject]@{ ExitCode = $process.ExitCode; TimedOut = $false
        StdOut = [IO.File]::ReadAllText($out); StdErr = [IO.File]::ReadAllText($err) }
}
function Resolve-ShellIcons([string[]]$paths, [string]$label) {
    $pathsFile = Join-Path $FixtureRoot "shell-$label.paths.txt"
    $outFile = Join-Path $OutputRoot "shell-$label.json"
    [IO.File]::WriteAllLines($pathsFile, $paths, (New-Object Text.UTF8Encoding($false)))
    $child = Invoke-Child @('-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File',
        (Join-Path $PSScriptRoot 'Resolve-PfiShellIcon.ps1'), '-PathsFile', $pathsFile, '-OutFile', $outFile) 60 "shell-$label"
    if ($child.ExitCode -ne 0) { throw "Shell icon resolver failed ($label): $($child.StdErr)" }
    $map = @{}
    # Assign first: Windows PowerShell 5.1 emits a JSON array as ONE pipeline object.
    $rows = [IO.File]::ReadAllText($outFile) | ConvertFrom-Json
    foreach ($row in $rows) { $map[[string]$row.Path] = $row }
    return $map
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
function Get-IniText([string]$folder) {
    # Decode the way Windows does: BOM when present, otherwise the ANSI code page. (The product itself
    # uses File.ReadAllText, which assumes UTF-8 without a BOM; this probe must not share that assumption.)
    $ini = Join-Path $folder 'desktop.ini'
    if (-not (Test-Path -LiteralPath $ini -PathType Leaf)) { return $null }
    $bytes = [IO.File]::ReadAllBytes($ini)
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) { return [Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2) }
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { return [Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3) }
    return [Text.Encoding]::Default.GetString($bytes)
}
function Get-FolderState([string]$folder, [string]$installRoot) {
    $ini = Join-Path $folder 'desktop.ini'
    $exists = Test-Path -LiteralPath $ini -PathType Leaf
    $text = Get-IniText $folder
    $lines = @(); if ($null -ne $text) { $lines = @([regex]::Split($text, '\r\n|\n|\r') | Where-Object { $_.Trim() }) }
    $iconLines = @($lines | Where-Object { $_ -match '^\s*(IconResource|IconFile|IconIndex)\s*=' })
    $otherLines = @($lines | Where-Object { $_ -notmatch '^\s*(IconResource|IconFile|IconIndex)\s*=' })
    $prefix = Get-PfiFolderResourcePrefix $folder
    $applied = Join-Path $installRoot 'icons\applied'
    $generated = 0
    if (Test-Path -LiteralPath $applied) { $generated = @(Get-ChildItem -LiteralPath $applied -Filter "$prefix-*.ico" -File).Count }
    $encoding = 'none'
    if ($exists) {
        $bytes = [IO.File]::ReadAllBytes($ini)
        if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) { $encoding = 'UTF-16LE BOM' }
        elseif ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB) { $encoding = 'UTF-8 BOM' }
        else { $encoding = 'no BOM' }
    }
    return [pscustomobject][ordered]@{
        IniExists = $exists; IniEncoding = $encoding
        IniAttributes = $(if ($exists) { [string][IO.File]::GetAttributes($ini) } else { '' })
        FolderAttributes = [string][IO.File]::GetAttributes($folder)
        IconLines = ($iconLines -join ' | '); OtherLines = ($otherLines -join ' | '); Generated = $generated
    }
}

$sections = [ordered]@{}
try {
    # ---------------------------------------------------------------- shared fixture install
    Write-Line '== Fixture install (repository installer, -SkipRegistry, fixture root only)'
    # Short names keep generated IconResource paths below MAX_PATH inside the run folder.
    $baseInstall = Join-Path $FixtureRoot 'ib'
    $install = Invoke-Child @('-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File',
        (Join-Path $runtimeSource 'Install-PortableFolderIcons.ps1'), '-RepositoryRoot', $repoRoot,
        '-InstallRoot', $baseInstall, '-SkipRegistry') 240 'fixture-install'
    if ($install.ExitCode -ne 0) { Write-Line "BLOCKED: fixture install failed: $($install.StdErr)"; exit 2 }
    $baseManifest = Read-PfiManifest (Join-Path $baseInstall 'manifest.json')
    $accepted = @($baseManifest.entries | Where-Object validationState -eq 'Accepted')
    Write-Line ("  fixture install accepted {0} icon(s) from files\ICO-Files" -f $accepted.Count)
    $blue = @($accepted | Where-Object menuLabel -eq 'Blue')[0]; $red = @($accepted | Where-Object menuLabel -eq 'Red')[0]

    # ---------------------------------------------------------------- D1 chooser / overflow
    Write-Line '== D1 chooser: discovery, validation, manifest, registry plan, ordering, dispatch identity'
    $d1 = @()
    foreach ($count in @(3, 21, 45, 120)) {
        $source = Join-Path $FixtureRoot "d1-source-$count"; [void](New-Item -ItemType Directory -Force -Path $source)
        $words = @('alpha', 'Bravo', 'charlie', 'Delta', 'echo', 'Foxtrot', 'golf', 'Hotel', 'india', 'Juliet')
        for ($i = 1; $i -le $count; $i++) {
            $stem = '{0} {1:D3}' -f $words[$i % $words.Count], $i
            if ($i % 10 -eq 0) { $stem += ' ' + ('long name segment ' * 6).Trim() }
            $fileName = $(if ($i % 2 -eq 0) { 'Folder_' } else { '' }) + $stem.Replace(' ', '_') + '.ico'
            New-SyntheticIco (Join-Path $source $fileName) $i
        }
        $cache = Join-Path $FixtureRoot "d1-cache-$count"; [void](New-Item -ItemType Directory -Force -Path $cache)
        $inventory = @(Get-PfiIconInventory -SourceDirectory $source -CacheDirectory $cache)
        $manifest = New-PfiManifest -Inventory $inventory
        $fakeHash = ('a' * 64)
        $plan = @(Get-PfiRegistryPlan -Manifest ([pscustomobject]$manifest | ConvertTo-Json -Depth 5 | ConvertFrom-Json) `
            -InstallRoot (Join-Path $FixtureRoot 'd1-install') -SelectionBrokerHash $fakeHash)
        # Phase 0B (ADR 015): Apply verbs live in the chooser store and in overflow stores (IconChoices.MoreNN), in that
        # menu order; each top-level static tree must stay within the observed 16-entry budget.
        $choiceVerbs = @($plan | Where-Object { $_.Name -eq 'MUIVerb' -and $_.Path -match '\\PortableFolderIcons\.ContextMenu\.IconChoices(\.More\d{2})?\\shell\\[^\\]+$' } |
            Sort-Object @{ Expression = { $(if ($_.Path -match 'IconChoices\.More(\d{2})\\') { [int]$Matches[1] } else { 0 }) } }, @{ Expression = { Split-Path -Leaf $_.Path } })
        $keyNames = @($choiceVerbs | ForEach-Object { Split-Path -Leaf $_.Path })
        $labels = @($choiceVerbs | ForEach-Object { [string]$_.Value })
        $ordinalSorted = @($keyNames | Sort-Object -CaseSensitive)
        $labelOrderOk = $true
        for ($k = 1; $k -lt $labels.Count; $k++) { if ([string]::Compare($labels[$k - 1], $labels[$k], [StringComparison]::CurrentCultureIgnoreCase) -gt 0) { $labelOrderOk = $false } }
        $utilities = @($plan | Where-Object { $_.Name -eq 'MUIVerb' -and $_.Path -like '*ContextMenu\shell\*' -and $_.Path -notlike '*IconChoices*' } | ForEach-Object { Split-Path -Leaf $_.Path } | Sort-Object)
        $treeSizes = @(@($choiceVerbs | Where-Object { $_.Path -notmatch 'IconChoices\.More\d{2}\\' }).Count + $utilities.Count) +
            @($choiceVerbs | Where-Object { $_.Path -match 'IconChoices\.More\d{2}\\' } | Group-Object { ($_.Path -split '\\shell\\')[0] } | ForEach-Object { $_.Count })
        $dispatchOk = $true
        foreach ($verb in $choiceVerbs) {
            $hashValue = @($plan | Where-Object { $_.Path -eq $verb.Path -and $_.Name -eq 'PfiIconHash' })[0].Value
            $iconValue = @($plan | Where-Object { $_.Path -eq $verb.Path -and $_.Name -eq 'Icon' })[0].Value
            $entry = @($inventory | Where-Object { $_.MenuLabel -ceq [string]$verb.Value })
            if ($entry.Count -ne 1 -or $entry[0].Hash -ne $hashValue -or -not $iconValue.EndsWith($entry[0].CachedFile + ',0')) { $dispatchOk = $false }
        }
        Assert-Gate (@($inventory | Where-Object Status -eq 'Accepted').Count -eq $count) "D1 $count synthetic icons are discovered and validated"
        Assert-Gate ($choiceVerbs.Count -eq $count) "D1 $count icons produce $count Apply verbs across the chooser and overflow entries (none dropped)"
        Assert-Gate ((@($keyNames) -join '|') -ceq (@($ordinalSorted) -join '|')) "D1 $count verb key order equals intended label order"
        Assert-Gate $labelOrderOk "D1 $count icon labels are alphabetical across chooser and overflow (case-insensitive)"
        Assert-Gate ((@($utilities) -join ',') -ceq 'Utility_0100_Reset,Utility_0200_Repair,Utility_0300_Uninstall,Utility_0900_Choose_Icons') "D1 $count Reset, Repair and Uninstall sort first in the short parent, then the chooser"
        Assert-Gate (@($treeSizes | Where-Object { $_ -gt 16 }).Count -eq 0) "D1 $count every top-level static tree stays within the observed 16-entry budget ($($treeSizes -join ', '))"
        Assert-Gate $dispatchOk "D1 $count every Apply verb dispatches the hash and cached icon of its own label"
        $d1 += [pscustomobject]@{ Icons = $count; ChooserVerbs = $choiceVerbs.Count; LongestLabel = (@($labels | Measure-Object -Property Length -Maximum).Maximum) }
    }
    # Label collisions are reported, not silently dropped from the menu.
    $collision = Join-Path $FixtureRoot 'd1-collision'; [void](New-Item -ItemType Directory -Force -Path $collision)
    New-SyntheticIco (Join-Path $collision 'Folder_Blue.ico') 201; New-SyntheticIco (Join-Path $collision 'blue.ico') 202
    $collisionInventory = @(Get-PfiIconInventory -SourceDirectory $collision -CacheDirectory (Join-Path $FixtureRoot 'd1-collision-cache'))
    Assert-Gate (@($collisionInventory | Where-Object Status -eq 'Rejected').Count -eq 2) 'D1 case-insensitive label collisions are rejected with a reason'
    $sections['D1-plan'] = $d1

    # Installed menu vs installed manifest (read-only registry and file reads).
    $installRoot = Join-Path $env:LOCALAPPDATA 'Portable-Folder-Icons'
    $installedManifest = Read-PfiManifest (Join-Path $installRoot 'manifest.json')
    $installedAccepted = @($installedManifest.entries | Where-Object validationState -eq 'Accepted')
    # Read-only. Counts Apply verbs in the chooser store and any Phase 0B overflow stores, so it holds for an
    # installation registered before or after Phase 0B.
    $installedOverflow = @(Get-PfiOwnedOverflowRegistryPaths -RegistryRoot $script:PfiProductionRegistryRoot -IconChoicesRoot $script:PfiProductionIconChoicesRoot)
    $installedStores = @($script:PfiProductionIconChoicesRoot) + @($installedOverflow | Where-Object { $_ -notlike ($script:PfiProductionRegistryRoot + '.More.*') })
    $installedVerbs = @($installedStores | ForEach-Object { Get-ChildItem -LiteralPath (Join-Path $_ 'shell') -ErrorAction SilentlyContinue })
    $stale = @()
    foreach ($verb in $installedVerbs) {
        $hashValue = [string]$verb.GetValue('PfiIconHash'); $iconValue = [string]$verb.GetValue('Icon'); $label = [string]$verb.GetValue('MUIVerb')
        $entry = @($installedAccepted | Where-Object { $_.hash -eq $hashValue -and $_.menuLabel -ceq $label })
        $iconFile = $iconValue -replace ',0$', ''
        $command = Get-Item -LiteralPath (Join-Path $verb.PSPath 'command') -ErrorAction SilentlyContinue
        $delegate = ''; if ($command) { $delegate = [string]$command.GetValue('DelegateExecute') }
        if ($entry.Count -ne 1 -or -not (Test-Path -LiteralPath $iconFile) -or (Get-PfiSha256 $iconFile) -ne $hashValue -or $delegate -ne $script:PfiSelectionBrokerClsid) { $stale += $verb.PSChildName }
    }
    Assert-Gate ($installedVerbs.Count -eq $installedAccepted.Count) ("D1 installed menu has one Apply verb per accepted manifest icon ({0} verbs, {1} accepted)" -f $installedVerbs.Count, $installedAccepted.Count)
    Assert-Gate ($stale.Count -eq 0) 'D1 installed menu has no stale, duplicate, unhashed or unregistered entries' ($stale -join ', ')
    Add-Type -AssemblyName System.Windows.Forms
    $work = [Windows.Forms.SystemInformation]::WorkingArea; $menuHeight = [Windows.Forms.SystemInformation]::MenuHeight
    $itemHeight = [Math]::Max($menuHeight, [Windows.Forms.SystemInformation]::SmallIconSize.Height + 8)
    $estimate = [Math]::Floor($work.Height / $itemHeight)
    Add-Finding 'D1' 'WINDOWS SHELL/CACHE BEHAVIOR' ("Classic Win32 popup menus that exceed the screen are scrolled only by their arrow buttons or keyboard, not the mouse wheel. Estimated capacity on this display: about {0} rows (work area {1}px / ~{2}px per row; estimate, not a measurement). Since Phase 0B no generated cascade holds more than 16 entries." -f $estimate, $work.Height, $itemHeight)
    $installedOldLayout = Test-Path -LiteralPath (Join-Path $script:PfiProductionSubcommandsRoot 'shell\Choice_0100_Icons')
    $installedParents = @($installedOverflow | Where-Object { $_ -like ($script:PfiProductionRegistryRoot + '.More.*') })
    if ($installedOldLayout) {
        Add-Finding 'D1/D5' 'INSTALLATION/REGISTRATION DEFECT' ("The installed menu predates Phase 0B: one chooser cascade with {0} icons and the utilities sorted after it, which the Shell truncates at 16 entries (M01 FAIL). Rerunning Setup_and_Run-Portable-Folder-Icons.bat registers the budgeted layout; manual M01 confirms it." -f $installedVerbs.Count)
    }
    else {
        Add-Finding 'D1/D5' 'UNVERIFIED (manual M01)' ("The installed menu uses the Phase 0B layout: {0} Apply verb(s), {1} overflow entr(y/ies). Gate check c-0009 proves the Shell-built menu for this layout; Explorer rendering needs manual M01." -f $installedVerbs.Count, $installedParents.Count)
    }
    $sections['D1-installed'] = [pscustomobject]@{ InstalledVerbs = $installedVerbs.Count; ManifestAccepted = $installedAccepted.Count; EstimatedRows = $estimate; WorkAreaHeight = $work.Height; MenuHeight = $menuHeight }

    # ---------------------------------------------------------------- D2 Reset to Default
    Write-Line '== D2 Reset: persisted state, unrelated metadata, attributes, fresh-process Shell resolution'
    $d2Root = Join-Path $FixtureRoot 'd2';[void](New-Item -ItemType Directory -Force -Path $d2Root)
    $unicode = New-Object Text.UnicodeEncoding($false, $true)
    $cases = [ordered]@{
        'plain' = @{ Ini = $null; FolderReadOnly = $false; Note = 'no desktop.ini' }
        'viewstate-only' = @{ Ini = "[ViewState]`r`nMode=`r`nVid=`r`nFolderType=Generic`r`n"; FolderReadOnly = $false; Note = 'unrelated section only' }
        'infotip-readonly' = @{ Ini = "[.ShellClassInfo]`r`nInfoTip=Keep this tip`r`n[ViewState]`r`nFolderType=Pictures`r`n"; FolderReadOnly = $true; Note = 'shell metadata to preserve' }
        'thirdparty-iconfile' = @{ Ini = "[.ShellClassInfo]`r`nIconFile=%SystemRoot%\system32\shell32.dll`r`nIconIndex=4`r`n"; FolderReadOnly = $true; Note = 'pre-existing third-party icon' }
        'readonly-no-ini' = @{ Ini = $null; FolderReadOnly = $true; Note = 'pre-existing ReadOnly, no desktop.ini' }
        'ansi-nonascii' = @{ Ini = 'ANSI'; FolderReadOnly = $true; Note = 'ANSI desktop.ini with a non-ASCII value' }
        'legacy-v010' = @{ Ini = 'LEGACY'; FolderReadOnly = $true; Note = 'v0.1.0-style IconResource to the shared cache' }
    }
    $control = Join-Path $d2Root 'control-never-customized'; [void](New-Item -ItemType Directory -Force -Path $control)
    $folders = [ordered]@{}
    foreach ($name in $cases.Keys) {
        $folder = Join-Path $d2Root $name; [void](New-Item -ItemType Directory -Force -Path $folder)
        $case = $cases[$name]; $ini = Join-Path $folder 'desktop.ini'
        if ($case.Ini -eq 'ANSI') {
            [IO.File]::WriteAllBytes($ini, [Text.Encoding]::GetEncoding(1252).GetBytes("[.ShellClassInfo]`r`nInfoTip=Caf" + [char]0x00E9 + " notes`r`n"))
        } elseif ($case.Ini -eq 'LEGACY') {
            [IO.File]::WriteAllText($ini, "[.ShellClassInfo]`r`nIconResource=$(Join-Path $baseInstall ('icons\' + $blue.cachedFilename)),0`r`n", $unicode)
        } elseif ($null -ne $case.Ini) {
            [IO.File]::WriteAllText($ini, $case.Ini, $unicode)
        }
        if (Test-Path -LiteralPath $ini) { [IO.File]::SetAttributes($ini, [IO.FileAttributes]'Hidden, System, Archive') }
        if ($case.FolderReadOnly) { [IO.File]::SetAttributes($folder, ([IO.File]::GetAttributes($folder) -bor [IO.FileAttributes]::ReadOnly)) }
        $folders[$name] = $folder
    }
    $allPaths = @($control) + @($folders.Values)
    $s0 = @{}; foreach ($name in $folders.Keys) { $s0[$name] = Get-FolderState $folders[$name] $baseInstall }
    $shell0 = Resolve-ShellIcons $allPaths 's0-before'
    foreach ($name in $folders.Keys) {
        if ($name -ne 'legacy-v010') { [void](Invoke-PfiApply -TargetPath @($folders[$name]) -IconHash $blue.hash -InstallRoot $baseInstall -SkipRefresh) }
    }
    [void](Invoke-PfiApply -TargetPath @($folders['plain']) -IconHash $red.hash -InstallRoot $baseInstall -SkipRefresh)
    $s1 = @{}; foreach ($name in $folders.Keys) { $s1[$name] = Get-FolderState $folders[$name] $baseInstall }
    $shell1 = Resolve-ShellIcons $allPaths 's1-applied'
    # Reset through the same batch entry point the broker dispatcher uses, with a duplicate occurrence.
    $resetTargets = @($folders.Values) + @($folders['plain'])
    $batch = Invoke-PfiBatchAction -Action Reset -TargetPath $resetTargets -InstallRoot $baseInstall -SkipRefresh
    $s2 = @{}; foreach ($name in $folders.Keys) { $s2[$name] = Get-FolderState $folders[$name] $baseInstall }
    $shell2 = Resolve-ShellIcons $allPaths 's2-reset'
    $batchAgain = Invoke-PfiBatchAction -Action Reset -TargetPath @($folders.Values) -InstallRoot $baseInstall -SkipRefresh
    $s3 = @{}; foreach ($name in $folders.Keys) { $s3[$name] = Get-FolderState $folders[$name] $baseInstall }

    Assert-Gate ($batch.SelectedCount -eq $resetTargets.Count -and $batch.SuccessCount -eq $resetTargets.Count) 'D2 batch Reset processes every occurrence, including a duplicate, and reports success'
    Assert-Gate ($batchAgain.SuccessCount -eq $folders.Count) 'D2 repeat Reset succeeds (idempotent)'
    $controlLocation = [string]$shell2[$control].IconLocation
    $d2Rows = @()
    foreach ($name in $folders.Keys) {
        $folder = $folders[$name]
        $appliedLocation = [string]$shell1[$folder].IconLocation
        if ($name -ne 'legacy-v010') {
            Assert-Gate ($appliedLocation -like '*\icons\applied\*') "D2 $name fresh-process Shell resolution sees the applied icon (probe is meaningful)" $appliedLocation
        }
        Assert-Gate ($s2[$name].IconLines -eq '') "D2 $name Reset removes IconResource/IconFile/IconIndex" $s2[$name].IconLines
        Assert-Gate ($s2[$name].Generated -eq 0) "D2 $name Reset reclaims this folder's generated resources"
        if (-not $s0[$name].IniExists) { Assert-Gate (-not $s2[$name].IniExists) "D2 $name Reset deletes the desktop.ini it created" }
        if ($name -notin @('ansi-nonascii', 'thirdparty-iconfile', 'legacy-v010')) {
            Assert-Gate ($s2[$name].OtherLines -ceq $s0[$name].OtherLines) "D2 $name Reset preserves unrelated desktop.ini content" ("before <{0}> after <{1}>" -f $s0[$name].OtherLines, $s2[$name].OtherLines)
            Assert-Gate ([string]$shell2[$folder].IconLocation -eq [string]$shell0[$folder].IconLocation) "D2 $name fresh-process Shell resolution after Reset equals the pre-Apply resolution" ("before <{0}> after <{1}>" -f $shell0[$folder].IconLocation, $shell2[$folder].IconLocation)
        }
        Assert-Gate (($s3[$name] | ConvertTo-Json -Compress) -eq ($s2[$name] | ConvertTo-Json -Compress)) "D2 $name second Reset changes nothing"
        $d2Rows += [pscustomobject][ordered]@{ Case = $name; Note = $cases[$name].Note
            Before = $s0[$name]; Applied = $s1[$name]; Reset = $s2[$name]
            ShellBefore = [string]$shell0[$folder].IconLocation; ShellApplied = $appliedLocation; ShellReset = [string]$shell2[$folder].IconLocation }
        if ($s2[$name].FolderAttributes -ne $s0[$name].FolderAttributes) {
            Add-Finding 'D2' 'SOURCE DEFECT (attribute ownership)' ("{0}: folder attributes before Apply <{1}>, after Reset <{2}>. Reset does not restore the folder's original ReadOnly state; it clears ReadOnly only when it deletes desktop.ini and leaves it set otherwise." -f $name, $s0[$name].FolderAttributes, $s2[$name].FolderAttributes)
        }
        if ($s0[$name].IniExists -and $s2[$name].IniExists -and $s2[$name].IniEncoding -ne $s0[$name].IniEncoding) {
            Add-Finding 'D2' 'SOURCE DEFECT (preservation)' ("{0}: desktop.ini encoding changed from {1} to {2}." -f $name, $s0[$name].IniEncoding, $s2[$name].IniEncoding)
        }
    }
    if ($s2['ansi-nonascii'].OtherLines -ne $s0['ansi-nonascii'].OtherLines) {
        Add-Finding 'D2' 'SOURCE DEFECT (preservation)' ("ansi-nonascii: unrelated InfoTip was altered by Apply/Reset: before <{0}> after <{1}>. desktop.ini is read with File.ReadAllText (UTF-8 default) and rewritten as UTF-16LE, so ANSI non-ASCII text is corrupted." -f $s0['ansi-nonascii'].OtherLines, $s2['ansi-nonascii'].OtherLines)
    }
    Add-Finding 'D2' 'UNVERIFIED' ("Persisted state and fresh-process Shell resolution after Reset match the never-customized control <{0}> for the standard cases. Rendering in a fresh Explorer view and in an already-open warm view are NOT established by this automation and stay manual." -f $controlLocation)
    Add-Finding 'D2' 'SOURCE DEFECT (design)' 'Reset removes ANY IconResource/IconFile/IconIndex in [.ShellClassInfo], including third-party or Windows Customize-tab icons, not only icons this tool applied (no ownership record exists yet).'
    $sections['D2'] = $d2Rows

    # ---------------------------------------------------------------- D3 Repair
    Write-Line '== D3 Repair: installed-resource validation boundary, error reporting, concurrency (isolated)'
    $scenarios = [ordered]@{
        'healthy' = { param($r) }
        'missing-actions-module' = { param($r) Remove-Item -LiteralPath (Join-Path $r 'runtime\PortableFolderIcons.Actions.ps1') -Force }
        'missing-cached-icon' = { param($r) Remove-Item -LiteralPath (Join-Path $r ('icons\' + $red.cachedFilename)) -Force }
        'corrupt-cached-icon' = { param($r) [IO.File]::AppendAllText((Join-Path $r ('icons\' + $red.cachedFilename)), 'x') }
        'corrupt-manifest' = { param($r) [IO.File]::WriteAllText((Join-Path $r 'manifest.json'), '{') }
        'missing-settings' = { param($r) Remove-Item -LiteralPath (Join-Path $r 'settings.json') -Force }
        'missing-broker' = { param($r) Remove-Item -LiteralPath (Join-Path $r 'runtime\SelectionHandler\PortableFolderIcons.SelectionBroker.exe') -Force }
        # Damages the broker's build manifest, not the executable: no project binary is written or launched.
        'corrupt-broker-manifest' = { param($r) [IO.File]::WriteAllText((Join-Path $r 'runtime\SelectionHandler\SelectionBroker.build.json'), '{') }
    }
    $d3 = @()
    foreach ($name in $scenarios.Keys) {
        $copy = Join-Path $FixtureRoot "d3-$name"
        Copy-Item -LiteralPath $baseInstall -Destination $copy -Recurse
        & $scenarios[$name] $copy
        $outcome = 'Error'; $message = ''; $damaged = 0
        try {
            $repair = Invoke-PfiRepair -InstallRoot $copy -SkipRegistry
            $outcome = $repair.Outcome; $damaged = @($repair.DamagedIcons).Count
            $message = Format-PfiRepairResult -Result $repair
        }
        catch { $message = $_.Exception.Message }
        $guided = $message.Contains('Setup_and_Run-Portable-Folder-Icons.bat')
        $d3 += [pscustomobject][ordered]@{ Scenario = $name; Outcome = $outcome; Damaged = $damaged; Message = $message; NamesRecovery = $guided }
        if ($name -eq 'healthy') { Assert-Gate ($outcome -eq 'Repaired') 'D3 Repair validates a healthy repository-independent install' $message }
        elseif ($name -like '*-cached-icon') {
            # Phase 0A (D3-B): one damaged cached icon no longer aborts Repair; it is diagnosed and NOT claimed repaired.
            Assert-Gate ($outcome -eq 'PartiallyRepaired' -and $damaged -eq 1 -and $message.Contains('not repaired') -and
                -not $message.Contains('Repair completed.')) "D3 Repair reports partial recovery, not success, when $name" $message
        }
        else { Assert-Gate ($outcome -eq 'Error') "D3 Repair does not report success when $name" $message }
        # Phase 0A (D3-D): every Repair outcome other than full success names the setup launcher.
        if ($name -ne 'healthy') { Assert-Gate $guided "D3 Repair tells the user to run Setup_and_Run when $name" $message }
    }
    # Phase 0A (D3-A): the dispatcher loads its modules inside a guarded boundary, so a missing module is visible.
    # The verification seam records the dialog instead of showing it (it is ignored for the production root).
    $dispatchCopy = Join-Path $FixtureRoot 'd3-dispatcher-missing-core'
    Copy-Item -LiteralPath $baseInstall -Destination $dispatchCopy -Recurse
    Remove-Item -LiteralPath (Join-Path $dispatchCopy 'runtime\PortableFolderIcons.Core.ps1') -Force
    $dialogDir = Join-Path $FixtureRoot 'd3-dispatcher-dialogs'
    [void](New-Item -ItemType Directory -Force -Path $dialogDir)
    $savedDialogDir = $env:PFI_TEST_DIALOG_DIR
    try {
        $env:PFI_TEST_DIALOG_DIR = $dialogDir
        $child = Invoke-Child @('-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File',
            (Join-Path $dispatchCopy 'runtime\Invoke-PortableFolderIcons.ps1'), '-Action', 'Repair') 60 'd3-dispatcher-missing-core'
    }
    finally { $env:PFI_TEST_DIALOG_DIR = $savedDialogDir }
    $dialogs = @(Get-ChildItem -LiteralPath $dialogDir -Filter 'dialogs-*.jsonl' -File | ForEach-Object { [IO.File]::ReadAllLines($_.FullName) } |
        Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json })
    Assert-Gate ((-not $child.TimedOut) -and $child.ExitCode -eq 1) 'D3 dispatcher exits 1 when a runtime module is missing' ("exit {0}" -f $child.ExitCode)
    Assert-Gate ($dialogs.Count -eq 1 -and $dialogs[0].image -eq 'Error' -and ([string]$dialogs[0].message).Contains('PortableFolderIcons.Core.ps1 is missing') -and
        ([string]$dialogs[0].message).Contains('Setup_and_Run-Portable-Folder-Icons.bat')) 'D3 a missing runtime module shows one Error dialog naming the file and the setup launcher' ("{0} dialog(s)" -f $dialogs.Count)
    Add-Finding 'D3' 'UNVERIFIED (registry-shape boundary)' 'If the installed dispatcher script itself is missing, the static Repair/Uninstall command (powershell.exe -WindowStyle Hidden -File <dispatcher>) has no product code to show a dialog. Fixing that needs a different verb shape; recorded for a later phase, not changed in Phase 0A.'
    # Concurrency: several processes re-registering at once, against isolated test registry roots, each holding the
    # per-user maintenance lock exactly as a Repair request does (Phase 0A, D3-C).
    $guid = [guid]::NewGuid().ToString('N')
    $regBase = "HKCU:\Software\PortableFolderIcons\Tests\Phase0-$guid"
    $regShell = "$regBase\DirectoryShell"; $regParent = "$regShell\PortableFolderIcons"
    $reference = "PortableFolderIcons.Tests.Phase0$guid"; $regSub = "HKCU:\Software\Classes\$reference"; $regChoices = "$regSub.IconChoices"
    $regClsid = 'HKCU:\Software\Classes\CLSID\{' + [guid]::NewGuid().ToString().ToUpperInvariant() + '}'
    $raceScript = Join-Path $FixtureRoot 'd3-race.ps1'
    $raceText = @"
`$ErrorActionPreference = 'Stop'
. '$((Join-Path $runtimeSource 'PortableFolderIcons.Core.ps1').Replace("'", "''"))'
. '$((Join-Path $runtimeSource 'PortableFolderIcons.Integration.ps1').Replace("'", "''"))'
. '$((Join-Path $runtimeSource 'PortableFolderIcons.Maintenance.ps1').Replace("'", "''"))'
`$manifest = Read-PfiManifest '$((Join-Path $baseInstall 'manifest.json').Replace("'", "''"))'
`$errors = @()
for (`$i = 0; `$i -lt 2; `$i++) {
    `$lock = `$null
    try {
        `$lock = Enter-PfiMaintenanceLock -InstallRoot '$($baseInstall.Replace("'", "''"))' -TimeoutSeconds 120
        [void](Register-PfiContextMenu -Manifest `$manifest -InstallRoot '$($baseInstall.Replace("'", "''"))' -RegistryRoot '$regParent' -SubcommandsRoot '$regSub' -SubcommandsReference '$reference' -IconChoicesRoot '$regChoices' -IconChoicesReference '$reference.IconChoices' -SelectionBrokerClsidRoot '$regClsid' -DirectoryShellRoot '$regShell')
    }
    catch { `$errors += `$_.Exception.Message }
    finally { if (`$null -ne `$lock) { Exit-PfiMaintenanceLock `$lock } }
}
`$errors | ForEach-Object { Write-Output ('RACE-ERROR: ' + `$_) }
"@
    [IO.File]::WriteAllText($raceScript, $raceText, (New-Object Text.UTF8Encoding($true)))
    $raceErrors = @(); $raceProcesses = @(); $finalVerbs = 0; $finalOwned = $false
    try {
        [void](New-Item -Path $regShell -Force)  # registration's legacy-entry sweep expects the shell root
        for ($p = 0; $p -lt 4; $p++) {
            $raceProcesses += Start-Process -FilePath $windowsPowerShell -ArgumentList ('-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $raceScript + '"') `
                -NoNewWindow -PassThru -RedirectStandardOutput (Join-Path $FixtureRoot "d3-race-$p.out.txt") -RedirectStandardError (Join-Path $FixtureRoot "d3-race-$p.err.txt")
        }
        foreach ($proc in $raceProcesses) { $null = $proc.Handle; if (-not $proc.WaitForExit(180000)) { & taskkill.exe /T /F /PID $proc.Id 2>&1 | Out-Null } }
        for ($p = 0; $p -lt 4; $p++) {
            $raceErrors += @(Get-Content -LiteralPath (Join-Path $FixtureRoot "d3-race-$p.out.txt") | Where-Object { $_ -like 'RACE-ERROR:*' })
            $raceErrors += @(Get-Content -LiteralPath (Join-Path $FixtureRoot "d3-race-$p.err.txt") | Where-Object { $_.Trim() } | Select-Object -First 2)
        }
        # Phase 0B: Apply verbs beyond the chooser allotment live in overflow stores ('<chooser store>.MoreNN').
        $finalStores = @($regChoices) + @(Get-PfiOwnedOverflowRegistryPaths -RegistryRoot $regParent -IconChoicesRoot $regChoices |
            Where-Object { $_ -notlike "$regParent.More.*" })
        $finalVerbs = @($finalStores | ForEach-Object { Get-ChildItem -LiteralPath (Join-Path $_ 'shell') -ErrorAction SilentlyContinue }).Count
        $finalOwned = Test-Path -LiteralPath (Join-Path $regClsid 'LocalServer32')
    }
    finally {
        # Every Classes key of this run starts with its GUID-unique reference (submenu, chooser and overflow stores).
        $runClassKeys = @((Get-Item -LiteralPath 'HKCU:\Software\Classes').GetSubKeyNames() |
            Where-Object { $_.StartsWith($reference, [StringComparison]::OrdinalIgnoreCase) } | ForEach-Object { "HKCU:\Software\Classes\$_" })
        foreach ($key in @($regClsid) + $runClassKeys + @($regBase)) { if (Test-Path -LiteralPath $key) { Remove-Item -LiteralPath $key -Recurse -Force } }
    }
    $leftClassKeys = @((Get-Item -LiteralPath 'HKCU:\Software\Classes').GetSubKeyNames() | Where-Object { $_.StartsWith($reference, [StringComparison]::OrdinalIgnoreCase) })
    Assert-Gate (-not (Test-Path -LiteralPath $regBase) -and -not (Test-Path -LiteralPath $regClsid) -and $leftClassKeys.Count -eq 0) 'D3 isolated race registry roots, including overflow stores, are removed' ($leftClassKeys -join ', ')
    $distinct = @($raceErrors | ForEach-Object { ($_ -replace '^RACE-ERROR: ', '') } | Sort-Object -Unique)
    Assert-Gate ($raceErrors.Count -eq 0) 'D3 4 concurrent processes x 2 lock-serialized re-registrations produce no error' (($distinct | Select-Object -First 3) -join ' || ')
    Assert-Gate ($finalVerbs -eq $accepted.Count -and $finalOwned) 'D3 after lock-serialized concurrent re-registration the menu is complete' ("chooser verbs {0}/{1}, COM LocalServer32 present={2}" -f $finalVerbs, $accepted.Count, $finalOwned)
    Add-Finding 'D3' 'UNVERIFIED (manual M03)' 'Whether Explorer starts one Repair process per selected folder (static verb, MultiSelectModel=Player), how many dialogs a real multi-folder Repair shows, and any console flash are manual checks (M03). Setup_and_Run registration is not coordinated with the maintenance lock (outside Phase 0A).'
    $sections['D3'] = [pscustomobject]@{ Scenarios = $d3; RaceErrors = $raceErrors.Count; RaceDistinct = $distinct; FinalVerbs = $finalVerbs; FinalComOwned = $finalOwned }

    # ---------------------------------------------------------------- D4 ordinary Uninstall
    Write-Line '== D4 ordinary Uninstall: what it removes and preserves (fixture root only)'
    # The product only allows uninstall cleanup of the exact LocalAppData root or the suite's test-root name.
    # Its BOM-less source is read by Windows PowerShell 5.1 as Windows-1252, so the literal is spelled the same way.
    $testLeaf = 'stable install ' + [char]0x00C3 + [char]0x00BC + 'nicode'
    $uninstallRoot = Join-Path (Join-Path $FixtureRoot ('PfiTests-' + [guid]::NewGuid().ToString('N'))) $testLeaf
    [void](New-Item -ItemType Directory -Force -Path (Split-Path -Parent $uninstallRoot))
    Copy-Item -LiteralPath $baseInstall -Destination $uninstallRoot -Recurse
    $customized = Join-Path $FixtureRoot 'd4-customized'; [void](New-Item -ItemType Directory -Force -Path $customized)
    $applied = Invoke-PfiApply -TargetPath @($customized) -IconHash $blue.hash -InstallRoot $uninstallRoot -SkipRefresh
    $uninstall = Invoke-PfiUninstall -InstallRoot $uninstallRoot -Confirmed -SkipRegistry
    foreach ($removed in @('runtime', 'state', 'manifest.json', 'settings.json')) {
        Assert-Gate (-not (Test-Path -LiteralPath (Join-Path $uninstallRoot $removed))) "D4 ordinary Uninstall removes $removed"
    }
    Assert-Gate ($uninstall.CachePreserved -and (Test-Path -LiteralPath (Join-Path $uninstallRoot ('icons\' + $blue.cachedFilename)))) 'D4 ordinary Uninstall preserves the hashed icon cache'
    Assert-Gate (Test-Path -LiteralPath $applied.IconResource) 'D4 ordinary Uninstall preserves the applied resource a customized folder still references'
    Assert-Gate ((Get-IniText $customized) -like "*$($applied.IconResource)*") 'D4 ordinary Uninstall leaves customized folders untouched'
    Add-Finding 'D4' 'SOURCE DEFECT (safety)' 'The installed Uninstall offers an optional cache purge (-PurgeCache) that deletes icons\ including icons\applied with only a warning dialog; this is the legacy warned purge, not a safe complete removal, and can break customized folders.'
    Add-Finding 'D4' 'UNVERIFIED' 'Uninstall, like Repair, is a static verb with MultiSelectModel=Player; with several folders selected Explorer may start several confirmation flows. Manual check.'
    $sections['D4'] = [pscustomobject]@{ Removed = 'runtime,state,manifest.json,settings.json'; CachePreserved = $uninstall.CachePreserved }
}
catch {
    $script:Failed++
    Write-Line "  [FAIL] diagnostics aborted: $($_.Exception.Message) at $($_.InvocationInfo.PositionMessage)"
}
finally {
    $report = [ordered]@{ Passed = $script:Passed; Failed = $script:Failed; Findings = $script:Findings; Sections = $sections }
    [IO.File]::WriteAllText((Join-Path $OutputRoot 'phase0-diagnostics.json'), ($report | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
    $md = @('# Phase 0 diagnostics', '', "Assertions: $($script:Passed) passed, $($script:Failed) failed. Findings: $($script:Findings.Count).", '',
        '| Area | Classification | Finding |', '|---|---|---|')
    foreach ($f in $script:Findings) { $md += "| $($f.Area) | $($f.Classification) | $($f.Finding.Replace('|', '\|')) |" }
    [IO.File]::WriteAllLines((Join-Path $OutputRoot 'phase0-diagnostics.md'), [string[]]$md, (New-Object Text.UTF8Encoding($false)))
    # Drop the bulky install copies (each holds every cached ICO). The D2 folders and all reports stay as evidence.
    foreach ($bulky in @(Get-ChildItem -LiteralPath $FixtureRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'd3-*' -or $_.Name -like 'PfiTests-*' -or $_.Name -like 'd1-cache-*' })) {
        Remove-Item -LiteralPath $bulky.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
}
Write-Host ('Diagnostics: {0} passed, {1} failed, {2} finding(s)' -f $script:Passed, $script:Failed, $script:Findings.Count)
if ($script:Failed -gt 0) { exit 1 }
exit 0
