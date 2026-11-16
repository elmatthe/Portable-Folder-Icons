# Builds the classic context menu exactly as the Windows Shell would from a static registry layout, and
# reports which entries the Shell actually puts in the menu (and its submenus).
#
# Isolation: every layout is written beneath GUID-named HKCU test keys (Software\PortableFolderIcons\Tests\Probe-*
# and Software\Classes\PortableFolderIcons.Tests.Probe*), which are deleted in finally. Production keys are only
# read (via the product's own registry plan generator, which writes nothing). DelegateExecute values are replaced
# by a random UNREGISTERED CLSID and static commands point at a path that does not exist, so no COM server,
# broker or command can start. The menu is built with SHCreateDefaultContextMenu from those test keys only, so no
# third-party shell extension is loaded, and no command is ever invoked.
#
# This proves what the Shell's static-verb menu builder produces. It does not prove pixels or scrolling.
# Exit: 0 report written (findings are in the report), 2 prerequisite missing.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$OutputRoot,
    [Parameter(Mandatory = $true)][string]$FixtureRoot
)
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -ne 5) { Write-Host 'BLOCKED: Windows PowerShell 5.1 is required.'; exit 2 }
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\..'))
foreach ($p in @($OutputRoot, $FixtureRoot)) {
    if (-not ([IO.Path]::GetFullPath($p)).StartsWith((Join-Path $repoRoot 'files') + '\', [StringComparison]::OrdinalIgnoreCase)) { Write-Host "BLOCKED: $p must be inside files\"; exit 2 }
}
[void](New-Item -ItemType Directory -Force -Path $OutputRoot, $FixtureRoot)
foreach ($module in @('Core', 'Integration')) { . (Join-Path $repoRoot "scripts\Windows\PortableFolderIcons.$module.ps1") }

if (-not ('PfiGate.MenuProbe' -as [type])) {
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
    public static class MenuProbe {
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
                if ((mii.fType & 0x800) != 0) text = "----";
                if (mii.hSubMenu != IntPtr.Zero && menu2 != null) menu2.HandleMenuMsg(0x0117, mii.hSubMenu, new IntPtr((int)i));
                int children = mii.hSubMenu == IntPtr.Zero ? -1 : GetMenuItemCount(mii.hSubMenu);
                lines.Add(new string(' ', depth * 2) + text + (children >= 0 ? " >" + children : ""));
                if (mii.hSubMenu != IntPtr.Zero) Walk(mii.hSubMenu, depth + 1, menu2, lines);
            }
        }
    }
}
'@
}

$unregisteredClsid = '{' + [guid]::NewGuid().ToString().ToUpperInvariant() + '}'
$neverRuns = '"C:\PfiProbeNeverRuns\none.exe" "%1"'
$createdKeys = New-Object Collections.Generic.List[string]
$item = Join-Path $FixtureRoot 'probe-target'; [void](New-Item -ItemType Directory -Force -Path $item)

function New-ProbeLayout([object[]]$manifestEntries, [scriptblock]$transform) {
    # Product plan for these entries, rooted at fresh test keys. Nothing is written by the generator.
    $g = [guid]::NewGuid().ToString('N')
    $base = "HKCU:\Software\PortableFolderIcons\Tests\Probe-$g"
    $reference = "PortableFolderIcons.Tests.Probe$g"
    $manifest = [pscustomobject]@{ schemaVersion = 1; productVersion = '0.1.1'; entries = $manifestEntries }
    $plan = @(Get-PfiRegistryPlan -Manifest $manifest -InstallRoot (Join-Path $FixtureRoot 'install') `
        -RegistryRoot "$base\shell\PortableFolderIcons" -SubcommandsRoot "HKCU:\Software\Classes\$reference" `
        -SubcommandsReference $reference -IconChoicesRoot "HKCU:\Software\Classes\$reference.IconChoices" `
        -IconChoicesReference "$reference.IconChoices" -SelectionBrokerClsidRoot ('HKCU:\Software\Classes\CLSID\' + $unregisteredClsid) `
        -SelectionBrokerHash ('0' * 64))
    # Never create the COM registration; never point at a real CLSID or a real command.
    $plan = @($plan | Where-Object { $_.Path -notlike 'HKCU:\Software\Classes\CLSID\*' } | ForEach-Object {
        $v = $_.Value
        if ($_.Name -eq 'DelegateExecute') { $v = $unregisteredClsid }
        elseif ($_.Path -like '*\command' -and [string]::IsNullOrEmpty($_.Name)) { $v = $neverRuns }
        [pscustomobject]@{ Path = $_.Path; Name = $_.Name; Value = $v; Type = $_.Type }
    })
    if ($null -ne $transform) { $plan = @(& $transform $plan $reference) }
    $createdKeys.Add($base); $createdKeys.Add("HKCU:\Software\Classes\$reference")
    foreach ($p in @($plan | Where-Object { $_.Path -like "HKCU:\Software\Classes\$reference*" } | ForEach-Object { ($_.Path -split '\\')[0..3] -join '\' } | Sort-Object -Unique)) { $createdKeys.Add($p) }
    foreach ($entry in $plan) {
        if (-not ($entry.Path.StartsWith("$base\") -or $entry.Path.StartsWith("HKCU:\Software\Classes\$reference"))) { throw "probe refused to write outside its test keys: $($entry.Path)" }
        if (-not (Test-Path -LiteralPath $entry.Path)) { [void](New-Item -Path $entry.Path -Force) }
        if ([string]::IsNullOrEmpty($entry.Name)) { Set-Item -LiteralPath $entry.Path -Value $entry.Value }
        else { New-ItemProperty -LiteralPath $entry.Path -Name $entry.Name -Value $entry.Value -PropertyType $entry.Type -Force | Out-Null }
    }
    return [pscustomobject]@{ SubKey = "Software\PortableFolderIcons\Tests\Probe-$g"; Reference = $reference; Plan = $plan }
}
function Get-Entries([int]$count, [object[]]$source) {
    $list = @()
    for ($i = 0; $i -lt $count; $i++) {
        if ($null -ne $source -and $i -lt $source.Count) { $list += $source[$i] }
        else { $h = ('{0:x64}' -f $i); $list += [pscustomobject]@{ menuLabel = ('Icon {0:D3}' -f $i); hash = ([string]$i).PadLeft(64, 'a'); cachedFilename = "x$i.ico"; validationState = 'Accepted' } }
    }
    return $list
}
function Measure-Menu($layout) {
    # Only the probe's own keys feed this menu, so every line is relevant (the Shell may add its own items).
    $lines = @([PfiGate.MenuProbe]::Build($item, $layout.SubKey, 0))
    return [pscustomobject]@{ All = $lines; Tree = $lines }
}

$installed = Read-PfiManifest (Join-Path $env:LOCALAPPDATA 'Portable-Folder-Icons\manifest.json')
$installedAccepted = @($installed.entries | Where-Object validationState -eq 'Accepted')
$results = New-Object Collections.Generic.List[object]
function Add-Result([string]$name, [string]$description, $layout) {
    $m = Measure-Menu $layout
    $results.Add([pscustomobject][ordered]@{ Experiment = $name; Description = $description
        RegisteredVerbs = @($layout.Plan | Where-Object { $_.Name -eq 'MUIVerb' -and $_.Path -notlike '*\shell\PortableFolderIcons' }).Count
        ShellMenu = ($m.Tree -join "`n") })
    Write-Host "== $name : $description"; $m.Tree | ForEach-Object { Write-Host "   $_" }
}

try {
    # Fidelity: the installed manifest through the product's own plan, as registered today.
    Add-Result 'E1-installed-21' 'installed manifest (21 icons), current layout' (New-ProbeLayout $installedAccepted $null)
    foreach ($n in @(10, 12, 13, 14)) {
        Add-Result ("E2-current-$n") "$n synthetic icons, current layout" (New-ProbeLayout (Get-Entries $n $null) $null)
    }
    # Remedy candidates (layouts only; nothing here changes the product).
    $utilitiesFirst = { param($plan, $ref)
        $plan | ForEach-Object { $p = $_.Path -replace '\\shell\\Choice_0100_Icons', '\shell\Utility_0900_Choice_Icons'; [pscustomobject]@{ Path = $p; Name = $_.Name; Value = $_.Value; Type = $_.Type } } }
    Add-Result 'E3-utilities-first-21' '21 icons, utilities sorted before the chooser' (New-ProbeLayout $installedAccepted $utilitiesFirst)
    $grouped = { param($plan, $ref)
        # Move icon verbs into three group stores of at most 7, each its own ExtendedSubCommandsKey.
        $out = @(); $index = 0
        foreach ($e in $plan) {
            if ($e.Path -like "HKCU:\Software\Classes\$ref.IconChoices\shell\PortableFolderIcons.Apply.*") {
                $ordinal = [int](($e.Path -split '\\')[5] -replace '^PortableFolderIcons\.Apply\.(\d{4}).*$', '$1')
                $group = [Math]::Floor(($ordinal - 1) / 7) + 1
                $out += [pscustomobject]@{ Path = $e.Path.Replace("$ref.IconChoices\shell", "$ref.IconChoices.G$group\shell"); Name = $e.Name; Value = $e.Value; Type = $e.Type }
            } else { $out += $e }
        }
        for ($g = 1; $g -le 3; $g++) {
            $out += [pscustomobject]@{ Path = "HKCU:\Software\Classes\$ref.IconChoices\shell\Group_0$g"; Name = 'MUIVerb'; Value = "Group $g"; Type = 'String' }
            $out += [pscustomobject]@{ Path = "HKCU:\Software\Classes\$ref.IconChoices\shell\Group_0$g"; Name = 'ExtendedSubCommandsKey'; Value = "$ref.IconChoices.G$g"; Type = 'String' }
        }
        $out }
    Add-Result 'E4-grouped-3x7' '21 icons in three alphabetical groups of 7 under the chooser' (New-ProbeLayout $installedAccepted $grouped)
    $twoParents = { param($plan, $ref)
        # Split icons across two top-level parents, each its own static cascade tree.
        $out = @()
        foreach ($e in $plan) {
            $out += $e
            if ($e.Path -like '*\shell\PortableFolderIcons' -and $e.Name -eq 'MUIVerb') {
                $p2 = $e.Path + 'B'
                $out += [pscustomobject]@{ Path = $p2; Name = 'MUIVerb'; Value = 'Folder Icons B'; Type = 'String' }
                $out += [pscustomobject]@{ Path = $p2; Name = 'ExtendedSubCommandsKey'; Value = "$ref.IconChoices"; Type = 'String' }
            }
        }
        $out }
    Add-Result 'E5-second-parent' '21 icons; second top-level parent pointing straight at the icon store' (New-ProbeLayout $installedAccepted $twoParents)
    # Candidate fix: every top-level static tree stays within the observed 16-entry budget.
    # "Folder Icons" = Reset, Repair, Uninstall first, then "Choose Folder Icon" with the first 12 icons
    # (3 + 1 + 12 = 16). Remaining icons go to extra top-level cascades of at most 16. Apply/Reset verb key
    # names, PfiAction and PfiIconHash are unchanged, so the broker's registration-derived contract is unchanged.
    $budgeted = { param($plan, $ref)
        $out = @(); $topLevel = $null
        foreach ($e in $plan) {
            if ($e.Path -like '*\shell\PortableFolderIcons' -and $e.Name -eq 'MUIVerb') { $topLevel = $e.Path }
            $path = $e.Path -replace '\\shell\\Choice_0100_Icons', '\shell\Utility_0900_Choose_Icons'
            if ($path -like "HKCU:\Software\Classes\$ref.IconChoices\shell\PortableFolderIcons.Apply.*") {
                $ordinal = [int](($path -split '\\')[5] -replace '^PortableFolderIcons\.Apply\.(\d{4}).*$', '$1')
                if ($ordinal -gt 12) {
                    $page = [int]([Math]::Floor(($ordinal - 13) / 16) + 1)
                    $path = $path.Replace("$ref.IconChoices\shell", ("$ref.IconChoices.More{0:D2}\shell" -f $page))
                }
            }
            $out += [pscustomobject]@{ Path = $path; Name = $e.Name; Value = $e.Value; Type = $e.Type }
        }
        $moved = @($out | Where-Object { $_.Path -like "HKCU:\Software\Classes\$ref.IconChoices.More*" -and $_.Name -eq 'MUIVerb' })
        foreach ($group in @($moved | Group-Object { ($_.Path -split '\\')[3] })) {
            $labels = @($group.Group | ForEach-Object { [string]$_.Value })
            $page = $group.Name.Substring($group.Name.Length - 2)
            $verb = "$topLevel.More.$page"
            $out += [pscustomobject]@{ Path = $verb; Name = 'MUIVerb'; Value = ('Folder Icons: {0} - {1}' -f $labels[0], $labels[-1]); Type = 'String' }
            $out += [pscustomobject]@{ Path = $verb; Name = 'MultiSelectModel'; Value = 'Player'; Type = 'String' }
            $out += [pscustomobject]@{ Path = $verb; Name = 'ExtendedSubCommandsKey'; Value = $group.Name; Type = 'String' }
        }
        $out }
    Add-Result 'E6-budgeted-21' 'candidate: utilities first, 12 icons in parent chooser, rest in extra top-level cascades (installed 21)' (New-ProbeLayout $installedAccepted $budgeted)
    Add-Result 'E7-budgeted-45' 'candidate layout at 45 synthetic icons' (New-ProbeLayout (Get-Entries 45 $null) $budgeted)
}
finally {
    foreach ($key in @($createdKeys | Sort-Object -Unique -Descending)) { if (Test-Path -LiteralPath $key) { Remove-Item -LiteralPath $key -Recurse -Force } }
    $left = @(Get-ChildItem 'HKCU:\Software\Classes' | Where-Object PSChildName -like 'PortableFolderIcons.Tests.Probe*').Count +
        @(Get-ChildItem 'HKCU:\Software\PortableFolderIcons\Tests' -ErrorAction SilentlyContinue | Where-Object PSChildName -like 'Probe-*').Count
    Write-Host "Probe registry keys left behind: $left"
    $results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutputRoot 'menu-probe.json') -Encoding UTF8
}
