# Resolves each folder's Shell icon in THIS fresh process (SHGetFileInfo), so the answer reflects
# persisted state plus the system icon cache, not any state held by the caller.
# It proves Shell resolution only. It does not prove what an Explorer window paints.
param(
    [Parameter(Mandatory = $true)][string]$PathsFile,
    [Parameter(Mandatory = $true)][string]$OutFile
)
$ErrorActionPreference = 'Stop'
if (-not ('PfiGate.ShellIcon' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace PfiGate {
    public static class ShellIcon {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        public struct SHFILEINFO {
            public IntPtr hIcon; public int iIcon; public uint dwAttributes;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string szDisplayName;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 80)] public string szTypeName;
        }
        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        private static extern IntPtr SHGetFileInfo(string path, uint attributes, ref SHFILEINFO info, uint size, uint flags);
        public static string Location(string path) {
            SHFILEINFO info = new SHFILEINFO();
            IntPtr ok = SHGetFileInfo(path, 0, ref info, (uint)Marshal.SizeOf(typeof(SHFILEINFO)), 0x1000);
            return ok == IntPtr.Zero ? "<failed>" : (info.szDisplayName + "," + info.iIcon);
        }
        public static int SystemIndex(string path) {
            SHFILEINFO info = new SHFILEINFO();
            IntPtr ok = SHGetFileInfo(path, 0, ref info, (uint)Marshal.SizeOf(typeof(SHFILEINFO)), 0x4000);
            return ok == IntPtr.Zero ? -1 : info.iIcon;
        }
    }
}
'@
}
$results = @()
foreach ($path in [IO.File]::ReadAllLines($PathsFile)) {
    if ([string]::IsNullOrWhiteSpace($path)) { continue }
    $results += [pscustomobject]@{
        Path = $path
        IconLocation = [PfiGate.ShellIcon]::Location($path)
        SystemImageIndex = [PfiGate.ShellIcon]::SystemIndex($path)
    }
}
[IO.File]::WriteAllText($OutFile, ($results | ConvertTo-Json -Depth 3), (New-Object Text.UTF8Encoding($false)))
