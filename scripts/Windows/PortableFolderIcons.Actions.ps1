Set-StrictMode -Version 2.0

function Assert-PfiCustomizableFolder {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string[]]$TargetPath)

    $resolved = Assert-PfiSingleTarget -TargetPath $TargetPath
    if ($resolved.StartsWith('\\')) {
        throw 'Network/UNC folders are not supported in version 0.1.0.'
    }
    $protectedRoots = @(
        $env:SystemRoot,
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)},
        $env:ProgramData
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    foreach ($protectedRoot in $protectedRoots) {
        $normalized = [IO.Path]::GetFullPath($protectedRoot).TrimEnd('\')
        if ($resolved.Equals($normalized, [StringComparison]::OrdinalIgnoreCase) -or
            $resolved.StartsWith($normalized + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Windows system and protected application folders cannot be customized.'
        }
    }
    $drive = New-Object IO.DriveInfo([IO.Path]::GetPathRoot($resolved))
    if (-not $drive.IsReady) { throw 'The target drive is not ready.' }
    if ($drive.DriveFormat -notin @('NTFS', 'ReFS')) {
        throw "The target filesystem '$($drive.DriveFormat)' is unsupported."
    }
    return $resolved
}

function Assert-PfiDesktopIniWellFormed {
    param([AllowEmptyString()][string]$Content)

    if ($Content.Contains([char]0)) {
        throw 'The existing desktop.ini contains invalid NUL data.'
    }
    foreach ($line in [regex]::Split($Content, '\r\n|\n|\r')) {
        if ($line.TrimStart().StartsWith('[') -and $line.Trim() -notmatch '^\[[^\[\]]+\]$') {
            throw 'The existing desktop.ini contains a malformed section header.'
        }
    }
}

function Set-PfiFileAttributes {
    param([string]$LiteralPath, [IO.FileAttributes]$Attributes)
    [IO.File]::SetAttributes($LiteralPath, $Attributes)
}

function Write-PfiDesktopIniSafely {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$FolderPath,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content,
        [switch]$DeleteWhenEmpty
    )

    $iniPath = Join-Path $FolderPath 'desktop.ini'
    $existing = Test-Path -LiteralPath $iniPath -PathType Leaf
    $originalAttributes = $null
    $backupPath = Join-Path $FolderPath ('.pfi-backup-' + [guid]::NewGuid().ToString('N'))
    $temporaryPath = Join-Path $FolderPath ('.pfi-write-' + [guid]::NewGuid().ToString('N'))
    try {
        if ($existing) {
            $originalAttributes = [IO.File]::GetAttributes($iniPath)
            Copy-Item -LiteralPath $iniPath -Destination $backupPath
            $writable = $originalAttributes -band (-bnot (
                [IO.FileAttributes]::ReadOnly -bor
                [IO.FileAttributes]::Hidden -bor
                [IO.FileAttributes]::System
            ))
            Set-PfiFileAttributes $iniPath $writable
        }
        if ($DeleteWhenEmpty -and [string]::IsNullOrEmpty($Content)) {
            if ($existing) { Remove-Item -LiteralPath $iniPath -Force }
            return [pscustomobject]@{ Path = $iniPath; Deleted = $existing }
        }
        $encoding = New-Object Text.UnicodeEncoding($false, $true)
        [IO.File]::WriteAllText($temporaryPath, $Content, $encoding)
        Move-Item -LiteralPath $temporaryPath -Destination $iniPath -Force
        $newAttributes = [IO.File]::GetAttributes($iniPath) -bor
            [IO.FileAttributes]::Hidden -bor [IO.FileAttributes]::System
        Set-PfiFileAttributes $iniPath $newAttributes
        return [pscustomobject]@{ Path = $iniPath; Deleted = $false }
    }
    catch {
        if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
            if (Test-Path -LiteralPath $iniPath -PathType Leaf) {
                Set-PfiFileAttributes $iniPath ([IO.FileAttributes]::Normal)
            }
            Copy-Item -LiteralPath $backupPath -Destination $iniPath -Force
            if ($null -ne $originalAttributes) {
                Set-PfiFileAttributes $iniPath $originalAttributes
            }
        }
        throw
    }
    finally {
        foreach ($cleanupPath in @($temporaryPath, $backupPath)) {
            if (Test-Path -LiteralPath $cleanupPath -PathType Leaf) {
                Remove-Item -LiteralPath $cleanupPath -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

function Send-PfiExplorerRefresh {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$FolderPath)

    if (-not ('PortableFolderIcons.NativeMethods' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace PortableFolderIcons {
    public static class NativeMethods {
        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        public static extern void SHChangeNotify(
            long eventId, uint flags, string item1, IntPtr item2);
    }
}
'@
    }
    # SHCNE_ATTRIBUTES | SHCNE_UPDATEITEM, SHCNF_PATHW | SHCNF_FLUSHNOWAIT
    [PortableFolderIcons.NativeMethods]::SHChangeNotify(
        0x00000800 -bor 0x00002000,
        0x00000005 -bor 0x00003000,
        $FolderPath,
        [IntPtr]::Zero
    )

    $parent = Split-Path -Parent $FolderPath
    try {
        $shell = New-Object -ComObject Shell.Application
        foreach ($window in @($shell.Windows())) {
            try {
                if ([string]::IsNullOrWhiteSpace([string]$window.LocationURL)) { continue }
                $uri = New-Object Uri([string]$window.LocationURL)
                if (-not $uri.IsFile) { continue }
                $location = [IO.Path]::GetFullPath($uri.LocalPath).TrimEnd('\')
                if ($location.Equals($parent.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) {
                    $window.Refresh()
                }
            }
            catch {
                # An individual non-filesystem Explorer window must not block refresh.
            }
        }
    }
    catch {
        Write-Warning 'The Shell was notified, but open Explorer windows could not be refreshed directly.'
    }
}

function Get-PfiExistingDesktopIni {
    param([string]$FolderPath)
    $iniPath = Join-Path $FolderPath 'desktop.ini'
    if (-not (Test-Path -LiteralPath $iniPath -PathType Leaf)) { return '' }
    try {
        return [IO.File]::ReadAllText($iniPath)
    }
    catch {
        throw "The existing desktop.ini could not be read: $($_.Exception.Message)"
    }
}

function Invoke-PfiApply {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string[]]$TargetPath,
        [Parameter(Mandatory = $true)][string]$IconHash,
        [Parameter(Mandatory = $true)][string]$InstallRoot,
        [switch]$SkipRefresh
    )

    $folder = Assert-PfiCustomizableFolder $TargetPath
    if ($IconHash -notmatch '^[a-fA-F0-9]{64}$') { throw 'The icon identity is invalid.' }
    $hash = $IconHash.ToLowerInvariant()
    $manifest = Read-PfiManifest (Join-Path $InstallRoot 'manifest.json')
    $matches = @($manifest.entries | Where-Object {
        $_.validationState -eq 'Accepted' -and ([string]$_.hash).ToLowerInvariant() -eq $hash
    })
    if ($matches.Count -lt 1) { throw 'The requested icon is not present in the active manifest.' }
    $cachedPath = Join-Path (Join-Path $InstallRoot 'icons') ([string]$matches[0].cachedFilename)
    if (-not (Test-Path -LiteralPath $cachedPath -PathType Leaf)) {
        throw 'The cached icon is missing. Run Repair or rerun repository setup.'
    }
    if ((Get-PfiSha256 $cachedPath) -ne $hash) {
        throw 'The cached icon failed its SHA-256 integrity check.'
    }
    $existing = Get-PfiExistingDesktopIni $folder
    Assert-PfiDesktopIniWellFormed $existing
    $updated = Set-PfiDesktopIniIconContent $existing ($cachedPath + ',0')
    [void](Write-PfiDesktopIniSafely $folder $updated)
    $folderAttributes = [IO.File]::GetAttributes($folder)
    Set-PfiFileAttributes $folder ($folderAttributes -bor [IO.FileAttributes]::ReadOnly)
    if (-not $SkipRefresh) { Send-PfiExplorerRefresh $folder }
    return [pscustomobject]@{ Action = 'Apply'; Folder = $folder; IconHash = $hash }
}

function Invoke-PfiReset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string[]]$TargetPath,
        [switch]$SkipRefresh
    )

    $folder = Assert-PfiCustomizableFolder $TargetPath
    $existing = Get-PfiExistingDesktopIni $folder
    Assert-PfiDesktopIniWellFormed $existing
    $updated = Reset-PfiDesktopIniIconContent $existing
    [void](Write-PfiDesktopIniSafely $folder $updated -DeleteWhenEmpty)
    if ([string]::IsNullOrEmpty($updated)) {
        $folderAttributes = [IO.File]::GetAttributes($folder)
        Set-PfiFileAttributes $folder ($folderAttributes -band (-bnot [IO.FileAttributes]::ReadOnly))
    }
    if (-not $SkipRefresh) { Send-PfiExplorerRefresh $folder }
    return [pscustomobject]@{ Action = 'Reset'; Folder = $folder }
}
