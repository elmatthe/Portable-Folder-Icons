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
    $sections = @{}
    foreach ($line in [regex]::Split($Content, '\r\n|\n|\r')) {
        if ($line.TrimStart().StartsWith('[') -and $line.Trim() -notmatch '^\[[^\[\]]+\]$') {
            throw 'The existing desktop.ini contains a malformed section header.'
        }
        if ($line.Trim() -match '^\[([^\[\]]+)\]$') {
            $sectionName = $Matches[1].ToUpperInvariant()
            if ($sections.ContainsKey($sectionName)) {
                throw "The existing desktop.ini contains a duplicate [$($Matches[1])] section."
            }
            $sections[$sectionName] = $true
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
        $baseAttributes = if ($null -ne $originalAttributes) {
            $originalAttributes
        }
        else {
            [IO.File]::GetAttributes($iniPath)
        }
        $newAttributes = $baseAttributes -bor
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
        elseif (-not $existing -and (Test-Path -LiteralPath $iniPath -PathType Leaf)) {
            Set-PfiFileAttributes $iniPath ([IO.FileAttributes]::Normal)
            Remove-Item -LiteralPath $iniPath -Force
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
    param(
        [Parameter(Mandatory = $true)][string]$FolderPath,
        [ValidateSet('Create', 'Update', 'Delete', 'None')]
        [string]$DesktopIniChange = 'Update',
        [scriptblock]$NotificationAction,
        [scriptblock]$ExplorerWindowsProvider
    )

    $folder = [IO.Path]::GetFullPath($FolderPath).TrimEnd('\')
    $desktopIni = Join-Path $folder 'desktop.ini'
    $parent = [IO.Path]::GetFullPath((Split-Path -Parent $folder)).TrimEnd('\')
    if ($null -eq $NotificationAction) {
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
        $NotificationAction = {
            param([long]$EventId, [uint32]$Flags, [string]$Path)
            [PortableFolderIcons.NativeMethods]::SHChangeNotify(
                $EventId,
                $Flags,
                $Path,
                [IntPtr]::Zero
            )
        }
    }
    if ($null -eq $ExplorerWindowsProvider) {
        $ExplorerWindowsProvider = {
            $shell = New-Object -ComObject Shell.Application
            return @($shell.Windows())
        }
    }

    $warnings = New-Object System.Collections.Generic.List[string]
    $notifications = New-Object System.Collections.Generic.List[object]
    # SHCNF_PATHW | SHCNF_FLUSH. FLUSH waits for delivery before refreshing views.
    [uint32]$notificationFlags = 0x00000005 -bor 0x00001000
    if ($DesktopIniChange -ne 'None') {
        [long]$desktopIniEvent = switch ($DesktopIniChange) {
            'Create' { 0x00000002 } # SHCNE_CREATE
            'Delete' { 0x00000004 } # SHCNE_DELETE
            default { 0x00002000 }  # SHCNE_UPDATEITEM
        }
        $notifications.Add([pscustomobject]@{
            Event = $DesktopIniChange
            EventId = $desktopIniEvent
            Path = $desktopIni
        })
    }
    $notifications.Add([pscustomobject]@{
        Event = 'Attributes'
        EventId = [long]0x00000800 # SHCNE_ATTRIBUTES
        Path = $folder
    })
    $notifications.Add([pscustomobject]@{
        Event = 'UpdateItem'
        EventId = [long]0x00002000 # SHCNE_UPDATEITEM
        Path = $folder
    })
    $notifications.Add([pscustomobject]@{
        Event = 'UpdateDirectory'
        EventId = [long]0x00001000 # SHCNE_UPDATEDIR
        Path = $parent
    })

    $issued = 0
    foreach ($notification in $notifications) {
        try {
            & $NotificationAction $notification.EventId $notificationFlags $notification.Path
            $issued++
        }
        catch {
            $warnings.Add(
                "Shell notification '$($notification.Event)' failed: $($_.Exception.Message)"
            )
        }
    }

    $matchedWindows = 0
    $refreshedWindows = 0
    try {
        foreach ($window in @(& $ExplorerWindowsProvider)) {
            try {
                if ([string]::IsNullOrWhiteSpace([string]$window.LocationURL)) { continue }
                $uri = New-Object Uri([string]$window.LocationURL)
                if (-not $uri.IsFile) { continue }
                $location = [IO.Path]::GetFullPath($uri.LocalPath).TrimEnd('\')
                if ($location.Equals($parent, [StringComparison]::OrdinalIgnoreCase)) {
                    $matchedWindows++
                    $window.Refresh()
                    $refreshedWindows++
                }
            }
            catch {
                # An individual non-filesystem Explorer window must not block refresh.
                $warnings.Add("An Explorer window could not be refreshed: $($_.Exception.Message)")
            }
        }
    }
    catch {
        $warnings.Add("Explorer windows could not be enumerated: $($_.Exception.Message)")
    }
    foreach ($warning in $warnings) {
        Write-Warning $warning
    }
    return [pscustomobject]@{
        NotificationsPlanned = $notifications.Count
        NotificationsIssued = $issued
        NotificationFlags = $notificationFlags
        Folder = $folder
        DesktopIni = $desktopIni
        Parent = $parent
        MatchedExplorerWindows = $matchedWindows
        RefreshedExplorerWindows = $refreshedWindows
        RefreshSucceeded = ($issued -eq $notifications.Count -and $warnings.Count -eq 0)
        Warnings = $warnings.ToArray()
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
        [switch]$SkipRefresh,
        [scriptblock]$RefreshAction
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
    $iniPath = Join-Path $folder 'desktop.ini'
    $iniExisted = Test-Path -LiteralPath $iniPath -PathType Leaf
    $originalIniAttributes = if ($iniExisted) { [IO.File]::GetAttributes($iniPath) } else { $null }
    $originalFolderAttributes = [IO.File]::GetAttributes($folder)
    $existing = Get-PfiExistingDesktopIni $folder
    Assert-PfiDesktopIniWellFormed $existing
    $updated = Set-PfiDesktopIniIconContent $existing ($cachedPath + ',0')
    try {
        [void](Write-PfiDesktopIniSafely $folder $updated)
        Set-PfiFileAttributes $folder ($originalFolderAttributes -bor [IO.FileAttributes]::ReadOnly)
    }
    catch {
        try {
            if ($iniExisted) {
                [void](Write-PfiDesktopIniSafely $folder $existing)
                Set-PfiFileAttributes $iniPath $originalIniAttributes
            }
            else {
                [void](Write-PfiDesktopIniSafely $folder '' -DeleteWhenEmpty)
            }
            Set-PfiFileAttributes $folder $originalFolderAttributes
        }
        catch { Write-Warning 'Apply failed and the original folder state could not be fully restored.' }
        throw
    }
    $refresh = $null
    if (-not $SkipRefresh) {
        $desktopIniChange = if ($iniExisted) { 'Update' } else { 'Create' }
        if ($null -eq $RefreshAction) {
            $refresh = Send-PfiExplorerRefresh $folder -DesktopIniChange $desktopIniChange
        }
        else {
            $refresh = & $RefreshAction $folder $desktopIniChange
        }
    }
    return [pscustomobject]@{
        Action = 'Apply'
        Folder = $folder
        IconHash = $hash
        Applied = $true
        RefreshSucceeded = ($SkipRefresh -or $null -eq $refresh -or $refresh.RefreshSucceeded)
        Refresh = $refresh
    }
}

function Invoke-PfiReset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string[]]$TargetPath,
        [switch]$SkipRefresh,
        [scriptblock]$RefreshAction
    )

    $folder = Assert-PfiCustomizableFolder $TargetPath
    $iniPath = Join-Path $folder 'desktop.ini'
    $iniExisted = Test-Path -LiteralPath $iniPath -PathType Leaf
    $originalIniAttributes = if ($iniExisted) { [IO.File]::GetAttributes($iniPath) } else { $null }
    $originalFolderAttributes = [IO.File]::GetAttributes($folder)
    $existing = Get-PfiExistingDesktopIni $folder
    Assert-PfiDesktopIniWellFormed $existing
    $updated = Reset-PfiDesktopIniIconContent $existing
    $writeResult = $null
    try {
        $writeResult = Write-PfiDesktopIniSafely $folder $updated -DeleteWhenEmpty
        if ([string]::IsNullOrEmpty($updated)) {
            Set-PfiFileAttributes $folder ($originalFolderAttributes -band (-bnot [IO.FileAttributes]::ReadOnly))
        }
    }
    catch {
        try {
            if ($iniExisted) {
                [void](Write-PfiDesktopIniSafely $folder $existing)
                Set-PfiFileAttributes $iniPath $originalIniAttributes
            }
            Set-PfiFileAttributes $folder $originalFolderAttributes
        }
        catch { Write-Warning 'Reset failed and the original folder state could not be fully restored.' }
        throw
    }
    $refresh = $null
    if (-not $SkipRefresh) {
        $desktopIniChange = if ($writeResult.Deleted) {
            'Delete'
        }
        elseif ($iniExisted) {
            'Update'
        }
        else {
            'None'
        }
        if ($null -eq $RefreshAction) {
            $refresh = Send-PfiExplorerRefresh $folder -DesktopIniChange $desktopIniChange
        }
        else {
            $refresh = & $RefreshAction $folder $desktopIniChange
        }
    }
    return [pscustomobject]@{
        Action = 'Reset'
        Folder = $folder
        Applied = $true
        RefreshSucceeded = ($SkipRefresh -or $null -eq $refresh -or $refresh.RefreshSucceeded)
        Refresh = $refresh
    }
}
