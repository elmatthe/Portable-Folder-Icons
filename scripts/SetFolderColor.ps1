[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$folderPath,

    [Parameter(Mandatory)]
    [string]$iconPath
)

$ErrorActionPreference = 'Stop'
$toolRoot = $PSScriptRoot
$logPath = Join-Path $toolRoot 'SetFolderColor.log'

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('INFO', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff zzz'), $Level, $Message
    Add-Content -LiteralPath $logPath -Value $line -Encoding utf8
}

try {
    Write-Log -Message ('Request: folder="{0}"; icon="{1}"' -f $folderPath, $iconPath)

    if (-not (Test-Path -LiteralPath $folderPath -PathType Container)) {
        throw "Folder does not exist or is not a directory: $folderPath"
    }

    $iconFilePath = $iconPath
    $iconIndex = 0
    if ($iconPath -match '^(?<path>.*),(?<index>-?\d+)$') {
        $iconFilePath = $Matches.path
        $iconIndex = [int]$Matches.index
    }

    if (-not (Test-Path -LiteralPath $iconFilePath -PathType Leaf)) {
        throw "Icon file does not exist: $iconFilePath"
    }

    $resolvedFolderPath = (Resolve-Path -LiteralPath $folderPath).ProviderPath
    $resolvedIconPath = (Resolve-Path -LiteralPath $iconFilePath).ProviderPath
    $iniPath = Join-Path $resolvedFolderPath 'desktop.ini'
    $iconResource = '{0},{1}' -f $resolvedIconPath, $iconIndex

    $lines = [System.Collections.Generic.List[string]]::new()
    if (Test-Path -LiteralPath $iniPath -PathType Leaf) {
        $attributes = [IO.File]::GetAttributes($iniPath)
        $writableAttributes = $attributes -band (-bnot ([IO.FileAttributes]::Hidden -bor [IO.FileAttributes]::System -bor [IO.FileAttributes]::ReadOnly))
        [IO.File]::SetAttributes($iniPath, $writableAttributes)

        $existingText = [IO.File]::ReadAllText($iniPath)
        foreach ($line in [regex]::Split($existingText, '\r\n|\n|\r')) {
            $lines.Add($line)
        }
    }

    $sectionStart = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -ieq '[.ShellClassInfo]') {
            $sectionStart = $i
            break
        }
    }

    if ($sectionStart -ge 0) {
        $sectionEnd = $lines.Count
        for ($i = $sectionStart + 1; $i -lt $lines.Count; $i++) {
            if ($lines[$i].Trim() -match '^\[.+\]$') {
                $sectionEnd = $i
                break
            }
        }

        for ($i = $sectionEnd - 1; $i -gt $sectionStart; $i--) {
            if ($lines[$i] -match '^\s*IconResource\s*=') {
                $lines.RemoveAt($i)
            }
        }
        $lines.Insert($sectionStart + 1, "IconResource=$iconResource")
    }
    else {
        if ($lines.Count -gt 0 -and $lines[0] -ne '') {
            $lines.Insert(0, '')
        }
        $lines.Insert(0, "IconResource=$iconResource")
        $lines.Insert(0, '[.ShellClassInfo]')
    }

    while ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -eq '') {
        $lines.RemoveAt($lines.Count - 1)
    }

    $desktopIniText = ($lines -join "`r`n") + "`r`n"
    $utf16LeWithBom = [Text.UnicodeEncoding]::new($false, $true)
    [IO.File]::WriteAllText($iniPath, $desktopIniText, $utf16LeWithBom)

    $iniAttributes = [IO.File]::GetAttributes($iniPath)
    [IO.File]::SetAttributes(
        $iniPath,
        $iniAttributes -bor [IO.FileAttributes]::Hidden -bor [IO.FileAttributes]::System
    )

    $folderAttributes = [IO.File]::GetAttributes($resolvedFolderPath)
    [IO.File]::SetAttributes(
        $resolvedFolderPath,
        $folderAttributes -bor [IO.FileAttributes]::ReadOnly
    )

    if (-not ('FolderColor.NativeMethods' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace FolderColor {
    public static class NativeMethods {
        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        public static extern void SHChangeNotify(
            uint wEventId,
            uint uFlags,
            string dwItem1,
            IntPtr dwItem2
        );
    }
}
'@
    }

    [FolderColor.NativeMethods]::SHChangeNotify(0x00002000, 0x0005, $resolvedFolderPath, [IntPtr]::Zero)
    [FolderColor.NativeMethods]::SHChangeNotify(0x08000000, 0x0000, $null, [IntPtr]::Zero)

    Write-Log -Message ('Success: folder="{0}"; IconResource="{1}"' -f $resolvedFolderPath, $iconResource)
    exit 0
}
catch {
    $details = $_ | Out-String
    try {
        Write-Log -Level ERROR -Message $details.Trim()
    }
    catch {
        [Console]::Error.WriteLine("Folder colour failed, and the log could not be written: $($_.Exception.Message)")
    }
    [Console]::Error.WriteLine($details.Trim())
    exit 1
}
