# Gate check c-0009 (Phase 0B, ADR 015): what the Windows Shell's static-menu builder actually exposes for the
# product's context-menu registration, as the icon inventory expands and shrinks.
#
# Isolation: the product's own Register-PfiContextMenu writes the menu beneath GUID-named HKCU test keys
# (Software\PortableFolderIcons\Tests\Menu-* and Software\Classes\PortableFolderIcons.Tests.Menu*), which its guard
# accepts only as test roots, plus a test CLSID key. Before every menu build each DelegateExecute value is replaced by a
# random UNREGISTERED CLSID and each static command by a path that does not exist, and that is asserted, so no COM
# server, broker or command can start. The menu is built with SHCreateDefaultContextMenu from the test keys only (no
# third-party shell extension is loaded) and nothing is invoked. Every test key is deleted in finally. Production keys,
# the installed product and its manifest are never written or read. The fixture broker copy is only hashed and read as
# metadata, never executed.
#
# Proves what the Shell's static-verb builder produces on this machine. It does not prove pixels, scrolling, or how
# Explorer itself calls the builder (manual gate M01).
# Exit: 0 PASS, 1 FAIL (an assertion failed or the check crashed), 2 BLOCKED (prerequisite missing).
[CmdletBinding()]
param(
    [string]$OutputRoot = $env:VERIFY_ARTIFACTS_DIR,
    [string]$FixtureRoot = $env:VERIFY_TEMP_DIR
)
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -ne 5) { Write-Host 'BLOCKED: Windows PowerShell 5.1 is required.'; exit 2 }
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\..'))
foreach ($name in @('OutputRoot', 'FixtureRoot')) {
    $value = [string](Get-Variable -Name $name -ValueOnly)
    if ([string]::IsNullOrWhiteSpace($value)) { Write-Host 'BLOCKED: run through the gate, or pass -OutputRoot and -FixtureRoot.'; exit 2 }
    # Resolve against the PowerShell location: SHParseDisplayName needs an absolute path.
    $full = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($value)
    if (-not $full.StartsWith((Join-Path $repoRoot 'files') + '\', [StringComparison]::OrdinalIgnoreCase)) {
        Write-Host "BLOCKED: $name must stay inside the repository files\ folder: $full"; exit 2
    }
    Set-Variable -Name $name -Value $full
}
[void](New-Item -ItemType Directory -Force -Path $OutputRoot, $FixtureRoot)
foreach ($module in @('Core', 'Integration')) { . (Join-Path $repoRoot "scripts\Windows\PortableFolderIcons.$module.ps1") }

if (-not ('PfiGate.ShellMenu' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
namespace PfiGate {
    [ComImport, Guid("000214E4-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IContextMenu {
        [PreserveSig] int QueryContextMenu(IntPtr hmenu, uint indexMenu, uint idCmdFirst, uint idCmdLast, uint uFlags);
        [PreserveSig] int InvokeCommand(IntPtr pici);
        [PreserveSig] int GetCommandString(UIntPtr idCmd, uint uType, IntPtr pReserved, IntPtr pszName, uint cchMax);
    }
    [ComImport, Guid("000214F4-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IContextMenu2 {
        [PreserveSig] int QueryContextMenu(IntPtr hmenu, uint indexMenu, uint idCmdFirst, uint idCmdLast, uint uFlags);
        [PreserveSig] int InvokeCommand(IntPtr pici);
        [PreserveSig] int GetCommandString(UIntPtr idCmd, uint uType, IntPtr pReserved, IntPtr pszName, uint cchMax);
        [PreserveSig] int HandleMenuMsg(uint uMsg, IntPtr wParam, IntPtr lParam);
    }
    [StructLayout(LayoutKind.Sequential)]
    struct DEFCONTEXTMENU { public IntPtr hwnd; public IntPtr pcmcb; public IntPtr pidlFolder; public IntPtr psf; public uint cidl; public IntPtr apidl; public IntPtr punkAssociationInfo; public uint cKeys; public IntPtr aKeys; }
    [StructLayout(LayoutKind.Sequential)]
    struct MENUITEMINFO { public uint cbSize; public uint fMask; public uint fType; public uint fState; public uint wID; public IntPtr hSubMenu; public IntPtr hbmpChecked; public IntPtr hbmpUnchecked; public IntPtr dwItemData; public IntPtr dwTypeData; public uint cch; public IntPtr hbmpItem; }
    public static class ShellMenu {
        [DllImport("shell32.dll", CharSet = CharSet.Unicode)] static extern int SHParseDisplayName(string name, IntPtr bc, out IntPtr pidl, uint sfgaoIn, out uint sfgaoOut);
        [DllImport("shell32.dll")] static extern int SHBindToParent(IntPtr pidl, ref Guid riid, out IntPtr ppv, out IntPtr ppidlLast);
        [DllImport("shell32.dll")] static extern int SHCreateDefaultContextMenu(ref DEFCONTEXTMENU pdcm, ref Guid riid, out IntPtr ppv);
        [DllImport("advapi32.dll", CharSet = CharSet.Unicode)] static extern int RegOpenKeyEx(UIntPtr hKey, string subKey, uint options, int sam, out IntPtr result);
        [DllImport("advapi32.dll")] static extern int RegCloseKey(IntPtr hKey);
        [DllImport("user32.dll")] static extern IntPtr CreatePopupMenu();
        [DllImport("user32.dll")] static extern bool DestroyMenu(IntPtr hMenu);
        [DllImport("user32.dll")] static extern int GetMenuItemCount(IntPtr hMenu);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool GetMenuItemInfoW(IntPtr hMenu, uint item, bool byPosition, ref MENUITEMINFO mii);
        [DllImport("ole32.dll")] static extern void CoTaskMemFree(IntPtr pv);

        // One line per menu item: depth TAB kind TAB text. kind: I item, S separator, M submenu.
        public static string[] Build(string itemPath, string hkcuSubKey, uint flags) {
            List<string> lines = new List<string>();
            IntPtr pidl = IntPtr.Zero, psf = IntPtr.Zero, hkey = IntPtr.Zero, keys = IntPtr.Zero, apidl = IntPtr.Zero, unk = IntPtr.Zero, hmenu = IntPtr.Zero;
            object menuObject = null;
            try {
                uint attrs;
                int hr = SHParseDisplayName(itemPath, IntPtr.Zero, out pidl, 0, out attrs);
                if (hr != 0) throw new Exception("SHParseDisplayName " + hr.ToString("X8"));
                Guid iidFolder = new Guid("000214E6-0000-0000-C000-000000000046");
                IntPtr child;
                hr = SHBindToParent(pidl, ref iidFolder, out psf, out child);
                if (hr != 0) throw new Exception("SHBindToParent " + hr.ToString("X8"));
                hr = RegOpenKeyEx(new UIntPtr(0x80000001u), hkcuSubKey, 0, 0x20019, out hkey);
                if (hr != 0) throw new Exception("RegOpenKeyEx " + hr);
                keys = Marshal.AllocHGlobal(IntPtr.Size); Marshal.WriteIntPtr(keys, hkey);
                apidl = Marshal.AllocHGlobal(IntPtr.Size); Marshal.WriteIntPtr(apidl, child);
                DEFCONTEXTMENU dcm = new DEFCONTEXTMENU();
                dcm.psf = psf; dcm.cidl = 1; dcm.apidl = apidl; dcm.cKeys = 1; dcm.aKeys = keys;
                Guid iidMenu = new Guid("000214E4-0000-0000-C000-000000000046");
                hr = SHCreateDefaultContextMenu(ref dcm, ref iidMenu, out unk);
                if (hr != 0) throw new Exception("SHCreateDefaultContextMenu " + hr.ToString("X8"));
                menuObject = Marshal.GetObjectForIUnknown(unk);
                IContextMenu menu = (IContextMenu)menuObject;
                IContextMenu2 menu2 = menuObject as IContextMenu2;
                hmenu = CreatePopupMenu();
                hr = menu.QueryContextMenu(hmenu, 0, 1, 0x7FFF, flags);
                if (hr < 0) throw new Exception("QueryContextMenu " + hr.ToString("X8"));
                Walk(hmenu, 0, menu2, lines);
            }
            finally {
                if (hmenu != IntPtr.Zero) DestroyMenu(hmenu);
                if (menuObject != null) Marshal.ReleaseComObject(menuObject);
                if (unk != IntPtr.Zero) Marshal.Release(unk);
                if (psf != IntPtr.Zero) Marshal.Release(psf);
                if (hkey != IntPtr.Zero) RegCloseKey(hkey);
                if (keys != IntPtr.Zero) Marshal.FreeHGlobal(keys);
                if (apidl != IntPtr.Zero) Marshal.FreeHGlobal(apidl);
                if (pidl != IntPtr.Zero) CoTaskMemFree(pidl);
            }
            return lines.ToArray();
        }

        static void Walk(IntPtr hmenu, int depth, IContextMenu2 menu2, List<string> lines) {
            int count = GetMenuItemCount(hmenu);
            for (uint i = 0; i < count; i++) {
                MENUITEMINFO mii = new MENUITEMINFO();
                mii.cbSize = (uint)Marshal.SizeOf(typeof(MENUITEMINFO));
                mii.fMask = 0x100 | 0x40 | 0x4 | 0x2;
                GetMenuItemInfoW(hmenu, i, true, ref mii);
                string text = "";
                if (mii.cch > 0) {
                    IntPtr buffer = Marshal.AllocHGlobal(((int)mii.cch + 1) * 2);
                    try {
                        mii.dwTypeData = buffer; mii.cch = mii.cch + 1;
                        GetMenuItemInfoW(hmenu, i, true, ref mii);
                        text = Marshal.PtrToStringUni(buffer);
                    } finally { Marshal.FreeHGlobal(buffer); }
                }
                string kind = (mii.fType & 0x800) != 0 ? "S" : (mii.hSubMenu != IntPtr.Zero ? "M" : "I");
                if (mii.hSubMenu != IntPtr.Zero && menu2 != null) menu2.HandleMenuMsg(0x0117, mii.hSubMenu, new IntPtr((int)i));
                lines.Add(depth.ToString() + "\t" + kind + "\t" + text);
                if (mii.hSubMenu != IntPtr.Zero) Walk(mii.hSubMenu, depth + 1, menu2, lines);
            }
        }
    }
}
'@
}

$script:Passed = 0; $script:Failed = 0
$script:Report = New-Object Collections.Generic.List[object]
function Assert-Gate([bool]$condition, [string]$name, [string]$detail = '') {
    if ($condition) { $script:Passed++; Write-Host "  [PASS] $name" }
    else { $script:Failed++; Write-Host "  [FAIL] $name$(if ($detail) { " :: $detail" })" }
}
# The product's single budget constant (ADR 015). Expectations below are derived from it, so lowering it for headroom
# keeps this check valid; the budget re-measurement proves the constant is safe on this Windows build.
$budget = Get-Variable -Scope Script -Name PfiStaticMenuEntryBudget -ValueOnly -ErrorAction SilentlyContinue
Assert-Gate ($budget -is [int] -and $budget -ge 5) 'the product defines one static-menu entry budget constant (PfiStaticMenuEntryBudget)'
if (-not ($budget -is [int] -and $budget -ge 5)) { $budget = 16 }

# ---------------------------------------------------------------- independent expectations
$enDash = [string][char]0x2013; $ellipsis = [string][char]0x2026
function Get-SortedLabels([string[]]$labels) {
    # Specification (ADR 015): case-insensitive invariant-culture order, ordinal as the tie-break.
    $list = New-Object 'Collections.Generic.List[string]'
    foreach ($l in $labels) { $list.Add($l) }
    $list.Sort([Comparison[string]] {
        param($a, $b)
        $c = [string]::Compare($a, $b, [StringComparison]::InvariantCultureIgnoreCase)
        if ($c -eq 0) { $c = [string]::CompareOrdinal($a, $b) }
        $c
    })
    return $list.ToArray()
}
function Get-RangeEnd([string]$label) {
    # Specification: an end longer than 40 characters keeps its first 39 and gains an ellipsis.
    if ($label.Length -le 40) { return $label }
    return $label.Substring(0, 39).TrimEnd() + $ellipsis
}
function Get-ExpectedMenu([string[]]$labels, [int]$budget) {
    $sorted = @(Get-SortedLabels $labels)
    $primary = [Math]::Min($sorted.Count, $budget - 4)
    $pages = @()
    for ($start = $primary; $start -lt $sorted.Count; $start += $budget) {
        $chunk = @($sorted[$start..([Math]::Min($start + $budget, $sorted.Count) - 1)])
        $text = if ($chunk.Count -eq 1) { 'Folder Icons ({0})' -f (Get-RangeEnd $chunk[0]) }
                else { 'Folder Icons ({0}{1}{2})' -f (Get-RangeEnd $chunk[0]), $enDash, (Get-RangeEnd $chunk[-1]) }
        $pages += , ([pscustomobject]@{ Label = $text; Items = $chunk })
    }
    $utilities = @('Reset to Default', 'Repair Portable Folder Icons', 'Uninstall Portable Folder Icons')
    if ($sorted.Count -gt 0) { $utilities += 'Choose Folder Icon' }
    return [pscustomobject]@{
        Sorted = $sorted; Primary = @($(if ($primary -gt 0) { $sorted[0..($primary - 1)] }))
        Utilities = $utilities; Pages = $pages
        TopLevel = @('Folder Icons') + @($pages | ForEach-Object { $_.Label })
    }
}
function New-Labels([int]$count) {
    $words = @('alpha', 'Bravo', 'charlie', 'Delta', 'echo', 'Foxtrot', 'golf', 'Hotel', 'india', 'Juliet')
    $labels = @()
    for ($i = 1; $i -le $count; $i++) {
        $label = '{0} {1:D3}' -f $words[$i % $words.Count], $i
        if ($i % 10 -eq 0) { $label += ' long name segment beyond forty characters' }
        $labels += $label
    }
    return $labels
}
$realLabels = @('ai', 'Black', 'Blue', 'code', 'CSPW', 'excel', 'GitHub', 'Gray', 'Green', 'markdown', 'Orange',
    'Pink', 'Purple', 'python', 'react', 'Red', 'root', 'Teal', 'vscode', 'work', 'Yellow')
function New-Manifest([string[]]$labels) {
    if ($null -eq $labels) { $labels = @() }
    $entries = @()
    for ($i = $labels.Count - 1; $i -ge 0; $i--) {   # reverse input order: the product must sort
        $hash = ('{0:x}' -f (0xD000 + $i)).PadLeft(64, '0')
        $entries += [pscustomobject]@{ menuLabel = $labels[$i]; originalFilename = "x$i.ico"; hash = $hash
            cachedFilename = "$hash.ico"; validationState = 'Accepted' }
    }
    return [pscustomobject]@{ entries = $entries }
}

# ---------------------------------------------------------------- Shell menu reading
$item = Join-Path $FixtureRoot 'menu-target'; [void](New-Item -ItemType Directory -Force -Path $item)
function Get-ShellMenu([string]$subKey) {
    $root = [pscustomobject]@{ Kind = 'M'; Text = '<menu>'; Children = (New-Object Collections.Generic.List[object]) }
    $stack = New-Object Collections.Generic.List[object]; $stack.Add($root)
    foreach ($line in @([PfiGate.ShellMenu]::Build($item, $subKey, 0))) {
        $parts = $line.Split([char[]]@([char]9), 3)
        $depth = [int]$parts[0]
        $node = [pscustomobject]@{ Kind = $parts[1]; Text = $parts[2]; Children = (New-Object Collections.Generic.List[object]) }
        while ($stack.Count -gt $depth + 1) { $stack.RemoveAt($stack.Count - 1) }
        $stack[$stack.Count - 1].Children.Add($node)
        $stack.Add($node)
    }
    return $root
}
function Get-Entries($node) { return @($node.Children | Where-Object Kind -ne 'S') }
function Measure-Tree($node) {
    $n = 0
    foreach ($child in (Get-Entries $node)) { $n += 1 + (Measure-Tree $child) }
    return $n
}
function Format-Tree($node, [int]$depth = 0) {
    $out = @()
    foreach ($child in $node.Children) {
        $text = if ($child.Kind -eq 'S') { '----' } else { $child.Text }
        $out += ('  ' * $depth) + $text + $(if ($child.Kind -eq 'M') { ' >' + @(Get-Entries $child).Count } else { '' })
        $out += @(Format-Tree $child ($depth + 1))
    }
    return $out
}

# ---------------------------------------------------------------- isolated roots and fixture install
$guid = [guid]::NewGuid().ToString('N')
$unregisteredClsid = '{' + [guid]::NewGuid().ToString().ToUpperInvariant() + '}'
$neverRuns = '"C:\PfiMenuCheckNeverRuns\none.exe" "%1"'
$base = "HKCU:\Software\PortableFolderIcons\Tests\Menu-$guid"
$shellRoot = "$base\shell"
$parent = "$shellRoot\PortableFolderIcons"
$reference = "PortableFolderIcons.Tests.Menu$guid"
$subcommands = "HKCU:\Software\Classes\$reference"
$choicesReference = "$reference.IconChoices"
$choices = "HKCU:\Software\Classes\$choicesReference"
$testClsid = 'HKCU:\Software\Classes\CLSID\{' + [guid]::NewGuid().ToString().ToUpperInvariant() + '}'
$budgetBase = "HKCU:\Software\PortableFolderIcons\Tests\Budget-$guid"
$budgetReference = "PortableFolderIcons.Tests.Budget$guid"
$budgetProbeSize = 40
$installRoot = Join-Path $FixtureRoot 'install'
$exitCode = 0

function Get-TestKeys {
    $keys = @($base, $budgetBase, $testClsid)
    $classes = @((Get-Item -LiteralPath 'HKCU:\Software\Classes').GetSubKeyNames() | Where-Object {
        $_.StartsWith($reference, [StringComparison]::OrdinalIgnoreCase) -or $_.StartsWith($budgetReference, [StringComparison]::OrdinalIgnoreCase) })
    return @($keys + @($classes | ForEach-Object { "HKCU:\Software\Classes\$_" }) | Where-Object { Test-Path -LiteralPath $_ })
}
function Disable-TestCommands {
    # Neutralize every command the product wrote, then prove it before the Shell sees the keys.
    foreach ($root in @(Get-TestKeys | Where-Object { $_ -ne $testClsid })) {
        foreach ($key in @(@(Get-Item -LiteralPath $root) + @(Get-ChildItem -LiteralPath $root -Recurse))) {
            if ($null -ne $key.GetValue('DelegateExecute')) { Set-ItemProperty -LiteralPath $key.PSPath -Name 'DelegateExecute' -Value $unregisteredClsid }
            if ($key.PSChildName -eq 'command' -and -not [string]::IsNullOrEmpty([string]$key.GetValue(''))) { Set-Item -LiteralPath $key.PSPath -Value $neverRuns }
        }
    }
    $unsafe = @()
    foreach ($root in @(Get-TestKeys | Where-Object { $_ -ne $testClsid })) {
        foreach ($key in @(@(Get-Item -LiteralPath $root) + @(Get-ChildItem -LiteralPath $root -Recurse))) {
            $delegate = $key.GetValue('DelegateExecute')
            if ($null -ne $delegate -and [string]$delegate -cne $unregisteredClsid) { $unsafe += $key.Name }
            if ($key.PSChildName -eq 'command' -and -not [string]::IsNullOrEmpty([string]$key.GetValue('')) -and [string]$key.GetValue('') -cne $neverRuns) { $unsafe += $key.Name }
        }
    }
    if ($unsafe.Count -gt 0) { throw ('Refusing to build a menu with live commands: ' + ($unsafe -join ', ')) }
}

try {
    # Fixture install: only what Register-PfiContextMenu validates (broker identity), never executed.
    $platform = if ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' }
    $selection = Join-Path $installRoot 'runtime\SelectionHandler'
    [void](New-Item -ItemType Directory -Force -Path $selection)
    Copy-Item -LiteralPath (Join-Path $repoRoot "scripts\Windows\SelectionHandler\PortableFolderIcons.SelectionBroker.$platform.exe") `
        -Destination (Join-Path $selection 'PortableFolderIcons.SelectionBroker.exe') -Force
    Copy-Item -LiteralPath (Join-Path $repoRoot 'scripts\Windows\SelectionHandler\SelectionBroker.build.json') -Destination $selection -Force

    # Unrelated verb and an overflow-name lookalike: both must survive every registration and stay in the menu.
    foreach ($k in @(@("$shellRoot\UnrelatedMenuCheckTool", 'Unrelated Menu Check Tool'), @("$shellRoot\PortableFolderIcons.More.1", 'Lookalike Menu Check Entry'))) {
        [void](New-Item -Path "$($k[0])\command" -Force)
        Set-ItemProperty -LiteralPath $k[0] -Name 'MUIVerb' -Value $k[1]
        Set-Item -LiteralPath "$($k[0])\command" -Value $neverRuns
    }

    # ------------------------------------------------------------ budget re-measurement (control)
    Write-Host "== Budget: one raw static cascade with $budgetProbeSize entries (not product code)"
    [void](New-Item -Path "$budgetBase\shell\BudgetProbe" -Force)
    Set-ItemProperty -LiteralPath "$budgetBase\shell\BudgetProbe" -Name 'MUIVerb' -Value 'Budget Probe'
    Set-ItemProperty -LiteralPath "$budgetBase\shell\BudgetProbe" -Name 'ExtendedSubCommandsKey' -Value $budgetReference
    for ($i = 1; $i -le $budgetProbeSize; $i++) {
        $entry = "HKCU:\Software\Classes\$budgetReference\shell\Entry_{0:D2}" -f $i
        [void](New-Item -Path "$entry\command" -Force)
        Set-ItemProperty -LiteralPath $entry -Name 'MUIVerb' -Value ('Budget Entry {0:D2}' -f $i)
        Set-Item -LiteralPath "$entry\command" -Value $neverRuns
    }
    Disable-TestCommands
    $budgetMenu = Get-ShellMenu "Software\PortableFolderIcons\Tests\Budget-$guid"
    $probeNode = @(Get-Entries $budgetMenu | Where-Object Text -ceq 'Budget Probe')
    $measured = if ($probeNode.Count -eq 1) { @(Get-Entries $probeNode[0]).Count } else { -1 }
    Write-Host "  measured static-menu entry budget: $measured of $budgetProbeSize (product constant: $budget)"
    Assert-Gate ($measured -ge $budget) "the Shell renders at least the product's budget of $budget entries in one static cascade (measured $measured)"
    if ($measured -ge 0 -and $measured -lt $budgetProbeSize) {
        # Negative control: the comparison used below must see the entries this raw layout loses.
        $expectedRaw = @(for ($i = 1; $i -le $budgetProbeSize; $i++) { 'Budget Entry {0:D2}' -f $i })
        $missing = @($expectedRaw | Where-Object { $_ -notin @(Get-Entries $probeNode[0] | ForEach-Object Text) })
        Assert-Gate ($missing.Count -eq ($budgetProbeSize - $measured)) "negative control: the comparison detects the $($budgetProbeSize - $measured) entries the Shell drops from an over-budget cascade"
        if ($measured -ne 16) { Write-Host "  [FINDING] the measured budget ($measured) differs from the value recorded on 2026-11-16 (16)." }
    }
    else { Write-Host "  [FINDING] no truncation observed up to $budgetProbeSize entries; the negative control is not applicable on this build." }
    $script:Report.Add([pscustomobject][ordered]@{ Step = 'budget'; Measured = $measured; ProbeSize = $budgetProbeSize; Menu = ((Format-Tree $budgetMenu) -join "`n") })

    # ------------------------------------------------------------ product registration, expanding then shrinking
    $sequence = @(0, 1, 12, 13, 16, 21, 28, 29, 45, 120, 45, 13, 0, 29, 29)
    $previousSnapshot = $null; $previousMenuText = $null
    for ($stepIndex = 0; $stepIndex -lt $sequence.Count; $stepIndex++) {
        $n = $sequence[$stepIndex]
        $labels = @(if ($n -eq 21) { $realLabels } else { New-Labels $n })
        $tag = "[{0,2}] {1} icon(s)" -f ($stepIndex + 1), $n
        Write-Host "== $tag$(if ($n -eq 21) { ' (the 21 labels installed on the development machine)' })"
        [void](Register-PfiContextMenu -Manifest (New-Manifest $labels) -InstallRoot $installRoot -RegistryRoot $parent `
            -SubcommandsRoot $subcommands -SubcommandsReference $reference -IconChoicesRoot $choices `
            -IconChoicesReference $choicesReference -SelectionBrokerClsidRoot $testClsid -DirectoryShellRoot $shellRoot)
        Disable-TestCommands
        $menu = Get-ShellMenu "Software\PortableFolderIcons\Tests\Menu-$guid"
        $expected = Get-ExpectedMenu $labels $budget
        $top = @(Get-Entries $menu)
        $ours = @($top | Where-Object { $_.Text -ceq 'Folder Icons' -or $_.Text.StartsWith('Folder Icons (', [StringComparison]::Ordinal) })
        Assert-Gate ((@($ours | ForEach-Object Text) -join '|') -ceq ($expected.TopLevel -join '|')) "$tag top-level entries are exactly Folder Icons plus the expected overflow entries, in order (no stale or duplicate entry)" `
            ("expected <{0}> actual <{1}>" -f ($expected.TopLevel -join '|'), (@($ours | ForEach-Object Text) -join '|'))
        $primary = @($ours | Where-Object Text -ceq 'Folder Icons')
        $primaryItems = @(if ($primary.Count -eq 1) { Get-Entries $primary[0] })
        Assert-Gate ((@($primaryItems | ForEach-Object Text) -join '|') -ceq ($expected.Utilities -join '|')) "$tag Folder Icons lists Reset, Repair and Uninstall first, then Choose Folder Icon only with icons" `
            ("actual <{0}>" -f (@($primaryItems | ForEach-Object Text) -join '|'))
        $chooser = @($primaryItems | Where-Object Text -ceq 'Choose Folder Icon')
        $chooserItems = @(if ($chooser.Count -eq 1) { Get-Entries $chooser[0] | ForEach-Object Text })
        Assert-Gate (($chooserItems -join '|') -ceq ($expected.Primary -join '|')) "$tag Choose Folder Icon shows exactly the first $($expected.Primary.Count) icon(s) alphabetically" `
            ("actual {0} item(s)" -f $chooserItems.Count)
        $rendered = @($chooserItems)
        $pagesOk = $true
        for ($p = 0; $p -lt $expected.Pages.Count; $p++) {
            $node = @($ours | Where-Object Text -ceq $expected.Pages[$p].Label)
            $items = @(if ($node.Count -eq 1) { Get-Entries $node[0] | ForEach-Object Text })
            if (($items -join '|') -cne ($expected.Pages[$p].Items -join '|')) { $pagesOk = $false }
            $rendered += $items
        }
        Assert-Gate $pagesOk "$tag each overflow entry shows exactly its alphabetical range of icons"
        Assert-Gate ((($rendered -join '|') -ceq ($expected.Sorted -join '|')) -and $rendered.Count -eq $n) "$tag every accepted icon is exposed exactly once across the chooser and overflow entries ($($rendered.Count) of $n)"
        $largest = 0; foreach ($o in $ours) { $largest = [Math]::Max($largest, (Measure-Tree $o)) }
        Assert-Gate ($largest -le $budget -and $largest -le $measured) "$tag every top-level tree stays within the budget (largest $largest, budget $budget, measured $measured)"
        Assert-Gate ((@($top | Where-Object { $_.Text -ceq 'Unrelated Menu Check Tool' -or $_.Text -ceq 'Lookalike Menu Check Entry' }).Count -eq 2)) "$tag unrelated and lookalike entries are untouched and still shown"
        $menuText = (Format-Tree $menu) -join "`n"
        $script:Report.Add([pscustomobject][ordered]@{ Step = $stepIndex + 1; Icons = $n; Menu = $menuText })
        if ($n -in @(21, 120) -and $stepIndex -lt 10) { Format-Tree $menu | Where-Object { $_ -notmatch '^(Cu&t|&Copy|Create &shortcut|&Delete|P&roperties|----)$' } | ForEach-Object { Write-Host "     $_" } }
        $snapshot = (@(Get-TestKeys | Where-Object { $_ -ne $budgetBase -and $_ -notlike "*$budgetReference*" } | Sort-Object | ForEach-Object {
            foreach ($key in @(@(Get-Item -LiteralPath $_) + @(Get-ChildItem -LiteralPath $_ -Recurse))) {
                $key.Name; foreach ($v in @($key.GetValueNames() | Sort-Object)) { "  $v=$([string]$key.GetValue($v))" } } })) -join "`n"
        if ($stepIndex -eq $sequence.Count - 1) {
            Assert-Gate ($snapshot -ceq $previousSnapshot) "$tag repeated registration leaves the registry unchanged (idempotent)"
            Assert-Gate ($menuText -ceq $previousMenuText) "$tag repeated registration leaves the Shell-built menu unchanged"
        }
        $previousSnapshot = $snapshot; $previousMenuText = $menuText
    }
}
catch {
    $script:Failed++
    Write-Host "  [FAIL] menu check crashed at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"
    $exitCode = 1
}
finally {
    foreach ($key in @(Get-TestKeys | Sort-Object -Descending)) { if (Test-Path -LiteralPath $key) { Remove-Item -LiteralPath $key -Recurse -Force } }
    $left = @(Get-TestKeys).Count
    Assert-Gate ($left -eq 0) "every test registry key was removed ($left left)"
    $script:Report | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutputRoot 'menu-check.json') -Encoding UTF8
}
Write-Host ("Menu check: {0} passed, {1} failed" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0 -or $exitCode -ne 0) { exit 1 }
exit 0
