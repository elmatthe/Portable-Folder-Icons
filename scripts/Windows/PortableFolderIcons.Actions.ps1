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
        if ($existing) {
            # Preserve the existing file identity so Shell caches and UPDATEITEM
            # notifications refer to the same item before and after the write.
            [IO.File]::WriteAllText($iniPath, $Content, $encoding)
        }
        else {
            [IO.File]::WriteAllText($temporaryPath, $Content, $encoding)
            Move-Item -LiteralPath $temporaryPath -Destination $iniPath
        }
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
        [scriptblock]$ExplorerWindowsProvider,
        [scriptblock]$FullViewRefreshAction
    )

    $folder = [IO.Path]::GetFullPath($FolderPath).TrimEnd('\')
    $desktopIni = Join-Path $folder 'desktop.ini'
    $parent = [IO.Path]::GetFullPath((Split-Path -Parent $folder)).TrimEnd('\')
    if (-not ('PortableFolderIcons.NativeMethods' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace PortableFolderIcons {
    public static class NativeMethods {
        [DllImport("shell32.dll", EntryPoint = "SHChangeNotify",
            CharSet = CharSet.Unicode, ExactSpelling = true)]
        private static extern void SHChangeNotifyPath(
            long eventId, uint flags, string item1, IntPtr item2);

        [DllImport("shell32.dll", EntryPoint = "SHChangeNotify",
            ExactSpelling = true)]
        private static extern void SHChangeNotifyPidl(
            long eventId, uint flags, IntPtr item1, IntPtr item2);

        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        private static extern int SHParseDisplayName(
            string name, IntPtr bindContext, out IntPtr pidl,
            uint attributesIn, out uint attributesOut);

        public static int OutstandingPidls { get; private set; }

        public static void NotifyPath(long eventId, uint flags, string path) {
            SHChangeNotifyPath(eventId, flags, path, IntPtr.Zero);
        }

        public static void NotifyPidl(long eventId, uint flags, string path) {
            IntPtr pidl;
            uint attributes;
            int result = SHParseDisplayName(
                path, IntPtr.Zero, out pidl, 0, out attributes);
            if (result < 0) {
                Marshal.ThrowExceptionForHR(result);
            }
            OutstandingPidls++;
            try {
                SHChangeNotifyPidl(
                    eventId, flags, pidl, IntPtr.Zero);
            }
            finally {
                Marshal.FreeCoTaskMem(pidl);
                OutstandingPidls--;
            }
        }

        public static void ValidatePidl(string path) {
            IntPtr pidl;
            uint attributes;
            int result = SHParseDisplayName(
                path, IntPtr.Zero, out pidl, 0, out attributes);
            if (result < 0) {
                Marshal.ThrowExceptionForHR(result);
            }
            OutstandingPidls++;
            try {
                if (pidl == IntPtr.Zero) {
                    throw new InvalidOperationException(
                        "SHParseDisplayName returned an empty PIDL.");
                }
            }
            finally {
                Marshal.FreeCoTaskMem(pidl);
                OutstandingPidls--;
            }
        }
    }
}
'@
    }
    if ($null -eq $NotificationAction) {
        $NotificationAction = {
            param(
                [long]$EventId,
                [uint32]$Flags,
                [string]$Path,
                [string]$TargetKind
            )
            if ($TargetKind -eq 'Pidl') {
                [PortableFolderIcons.NativeMethods]::NotifyPidl($EventId, $Flags, $Path)
            }
            else {
                [PortableFolderIcons.NativeMethods]::NotifyPath($EventId, $Flags, $Path)
            }
        }
    }
    if ($null -eq $ExplorerWindowsProvider) {
        $ExplorerWindowsProvider = {
            $shell = New-Object -ComObject Shell.Application
            return @($shell.Windows())
        }
    }
    if ($null -eq $FullViewRefreshAction) {
        $FullViewRefreshAction = {
            param(
                $ExplorerWindow,
                [string]$LocationUrl,
                [string]$TemporaryLocationUrl,
                [string]$ExpectedLocationPath,
                [string]$TemporaryLocationPath
            )
            Add-Type -AssemblyName System.Windows.Forms
            $waitForLocation = {
                param([string]$ExpectedPath)
                $deadline = [DateTime]::UtcNow.AddSeconds(10)
                while ([DateTime]::UtcNow -lt $deadline) {
                    [Windows.Forms.Application]::DoEvents()
                    if (-not [bool]$ExplorerWindow.Busy) {
                        $currentUrl = [string]$ExplorerWindow.LocationURL
                        if (-not [string]::IsNullOrWhiteSpace($currentUrl)) {
                            $currentUri = New-Object Uri($currentUrl)
                            if ($currentUri.IsFile) {
                                $currentPath = [IO.Path]::GetFullPath(
                                    $currentUri.LocalPath
                                ).TrimEnd('\')
                                if ($currentPath.Equals(
                                    $ExpectedPath,
                                    [StringComparison]::OrdinalIgnoreCase
                                )) {
                                    return
                                }
                            }
                        }
                    }
                    [void][Threading.Thread]::Yield()
                }
                throw "Explorer did not complete targeted navigation to '$ExpectedPath'."
            }
            # A same-URL Navigate2 can be optimized away by tabbed Explorer.
            # Navigate this exact tab one level out and back, waiting on the
            # COM object's real URL and Busy state rather than a fixed delay.
            #
            # The return leg is in a finally block: if the outbound navigation
            # fails or times out, the tab must still be brought back. Without
            # this the view is left stranded at the temporary parent, which
            # violates the requirement that it finish at the original folder.
            try {
                $ExplorerWindow.Navigate2($TemporaryLocationUrl)
                & $waitForLocation $TemporaryLocationPath
            }
            finally {
                $ExplorerWindow.Navigate2($LocationUrl)
                & $waitForLocation $ExpectedLocationPath
            }
        }
    }

    $warnings = New-Object System.Collections.Generic.List[string]
    $notifications = New-Object System.Collections.Generic.List[object]
    # SHCNF_IDLIST/SHCNF_PATHW | SHCNF_FLUSH. Existing Shell items use
    # canonical PIDLs; a deleted desktop.ini must use its former path.
    [uint32]$pidlNotificationFlags = 0x00001000
    [uint32]$pathNotificationFlags = 0x00000005 -bor 0x00001000
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
            TargetKind = if ($DesktopIniChange -eq 'Delete') { 'Path' } else { 'Pidl' }
        })
    }
    $notifications.Add([pscustomobject]@{
        Event = 'Attributes'
        EventId = [long]0x00000800 # SHCNE_ATTRIBUTES
        Path = $folder
        TargetKind = 'Pidl'
    })
    $notifications.Add([pscustomobject]@{
        Event = 'UpdateItem'
        EventId = [long]0x00002000 # SHCNE_UPDATEITEM
        Path = $folder
        TargetKind = 'Pidl'
    })
    $notifications.Add([pscustomobject]@{
        Event = 'UpdateDirectory'
        EventId = [long]0x00001000 # SHCNE_UPDATEDIR
        Path = $parent
        TargetKind = 'Pidl'
    })

    $issued = 0
    foreach ($notification in $notifications) {
        try {
            $flags = if ($notification.TargetKind -eq 'Pidl') {
                $pidlNotificationFlags
            }
            else {
                $pathNotificationFlags
            }
            & $NotificationAction $notification.EventId $flags `
                $notification.Path $notification.TargetKind
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
    $refreshedWindowHandles = New-Object System.Collections.Generic.List[long]
    try {
        foreach ($window in @(& $ExplorerWindowsProvider)) {
            try {
                if ([string]::IsNullOrWhiteSpace([string]$window.LocationURL)) { continue }
                $locationUrl = [string]$window.LocationURL
                $uri = New-Object Uri($locationUrl)
                if (-not $uri.IsFile) { continue }
                $location = [IO.Path]::GetFullPath($uri.LocalPath).TrimEnd('\')
                if ($location.Equals($parent, [StringComparison]::OrdinalIgnoreCase)) {
                    $matchedWindows++
                    $temporaryParent = [IO.Path]::GetFullPath(
                        (Split-Path -Parent $parent)
                    ).TrimEnd('\')
                    if ($temporaryParent.Equals($parent, [StringComparison]::OrdinalIgnoreCase)) {
                        throw 'The matching Explorer view cannot be reloaded through a distinct parent location.'
                    }
                    $temporaryLocationUrl = (New-Object Uri($temporaryParent + '\')).AbsoluteUri
                    & $FullViewRefreshAction $window $locationUrl $temporaryLocationUrl `
                        $parent $temporaryParent
                    $refreshedWindows++
                    if ($null -ne $window.PSObject.Properties['HWND']) {
                        $refreshedWindowHandles.Add([long]$window.HWND)
                    }
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
        Notifications = $notifications.ToArray()
        PidlNotificationFlags = $pidlNotificationFlags
        PathNotificationFlags = $pathNotificationFlags
        Folder = $folder
        DesktopIni = $desktopIni
        Parent = $parent
        MatchedExplorerWindows = $matchedWindows
        RefreshedExplorerWindows = $refreshedWindows
        RefreshedWindowHandles = $refreshedWindowHandles.ToArray()
        ViewRefreshMechanism = 'NavigateAwayAndBack'
        # True only when every matched view was actually reloaded. Previously
        # this reported success purely from the notification count, so a run
        # that reloaded nothing still claimed the refresh had succeeded.
        RefreshSucceeded = (
            $issued -eq $notifications.Count -and
            $warnings.Count -eq 0 -and
            $refreshedWindows -eq $matchedWindows
        )
        # Whether an open view of the parent was found and reloaded at all.
        # Zero is normal when the parent folder is not open in Explorer.
        ViewReloadPerformed = ($refreshedWindows -gt 0)
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

function Get-PfiFolderResourcePrefix {
    param([Parameter(Mandatory = $true)][string]$FolderPath)

    $canonical = [IO.Path]::GetFullPath($FolderPath).TrimEnd('\').ToUpperInvariant()
    $bytes = (New-Object Text.UTF8Encoding($false)).GetBytes($canonical)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function New-PfiAppliedIconResource {
    param(
        [Parameter(Mandatory = $true)][string]$FolderPath,
        [Parameter(Mandatory = $true)][string]$CachedIconPath,
        [Parameter(Mandatory = $true)][string]$InstallRoot
    )

    $generatedRoot = Join-Path (Join-Path $InstallRoot 'icons') 'applied'
    [void](New-Item -ItemType Directory -Path $generatedRoot -Force)
    $prefix = Get-PfiFolderResourcePrefix $FolderPath
    $name = '{0}-{1}.ico' -f $prefix, [guid]::NewGuid().ToString('N')
    $destination = Join-Path $generatedRoot $name
    Copy-Item -LiteralPath $CachedIconPath -Destination $destination
    return $destination
}

function Remove-PfiObsoleteAppliedResources {
    param(
        [Parameter(Mandatory = $true)][string]$FolderPath,
        [Parameter(Mandatory = $true)][string]$InstallRoot,
        [string[]]$KeepPath
    )

    $generatedRoot = Join-Path (Join-Path $InstallRoot 'icons') 'applied'
    if (-not (Test-Path -LiteralPath $generatedRoot -PathType Container)) { return 0 }
    $keep = New-Object System.Collections.Generic.List[string]
    foreach ($path in @($KeepPath)) {
        if ([string]::IsNullOrWhiteSpace($path)) { continue }
        $keep.Add([IO.Path]::GetFullPath($path))
    }
    $prefix = (Get-PfiFolderResourcePrefix $FolderPath) + '-'
    $removed = 0
    foreach ($candidate in @(Get-ChildItem -LiteralPath $generatedRoot -File -Filter ($prefix + '*.ico'))) {
        $retain = $false
        foreach ($path in $keep) {
            if ($candidate.FullName.Equals($path, [StringComparison]::OrdinalIgnoreCase)) {
                $retain = $true
                break
            }
        }
        if ($retain) { continue }
        Remove-Item -LiteralPath $candidate.FullName -Force
        $removed++
    }
    return $removed
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
    # Explorer keeps resolving the PREVIOUS IconResource path for some time after
    # desktop.ini changes. Deleting that file immediately makes the icon resolve
    # to nothing, which Explorer then caches as "no customization" -- the folder
    # falls back to the plain default icon and does not recover. Retaining the
    # superseded resource for one more generation avoids that failure entirely.
    $supersededResource = Get-PfiDesktopIniIconResourcePath $existing
    Write-Host ('[1/4] Validated cached icon: {0}' -f ([IO.Path]::GetFileName($cachedPath)))
    $appliedResource = New-PfiAppliedIconResource $folder $cachedPath $InstallRoot
    $updated = Set-PfiDesktopIniIconContent $existing ($appliedResource + ',0')
    try {
        [void](Write-PfiDesktopIniSafely $folder $updated)
        Set-PfiFileAttributes $folder ($originalFolderAttributes -bor [IO.FileAttributes]::ReadOnly)
        Write-Host ('[2/4] Committed desktop.ini and folder attributes: {0}' -f $folder)
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
        if (Test-Path -LiteralPath $appliedResource -PathType Leaf) {
            Remove-Item -LiteralPath $appliedResource -Force -ErrorAction SilentlyContinue
        }
        throw
    }
    $refresh = $null
    if (-not $SkipRefresh) {
        $desktopIniChange = if ($iniExisted) { 'Update' } else { 'Create' }
        if ($null -eq $RefreshAction) {
            Write-Host ('[3/4] Invalidating Shell state and reloading parent view: {0}' -f
                (Split-Path -Parent $folder))
            $refresh = Send-PfiExplorerRefresh $folder -DesktopIniChange $desktopIniChange
        }
        else {
            $refresh = & $RefreshAction $folder $desktopIniChange
        }
    }
    # Deliberately no cleanup here. Explorer can lag several applies behind what
    # desktop.ini says, so there is no generation count that is safe to reclaim:
    # measuring showed a view still rendering the FIRST colour after two further
    # applies, and deleting that resource dropped the folder to the plain default
    # icon permanently. Every resource a folder has ever used is therefore kept
    # until Reset removes the customization and reclaims them all. The files are
    # a few hundred bytes each, and Repair reports how many exist.
    Write-Host '[4/4] Apply and targeted Explorer refresh completed.'
    return [pscustomobject]@{
        Action = 'Apply'
        Folder = $folder
        IconHash = $hash
        IconResource = $appliedResource
        SupersededIconResource = $supersededResource
        Applied = $true
        RefreshSucceeded = ($SkipRefresh -or $null -eq $refresh -or $refresh.RefreshSucceeded)
        Refresh = $refresh
    }
}

function Invoke-PfiReset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string[]]$TargetPath,
        [string]$InstallRoot,
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
        Write-Host ('[1/3] Removed owned icon customization and committed attributes: {0}' -f $folder)
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
            Write-Host ('[2/3] Invalidating Shell state and reloading parent view: {0}' -f
                (Split-Path -Parent $folder))
            $refresh = Send-PfiExplorerRefresh $folder -DesktopIniChange $desktopIniChange
        }
        else {
            $refresh = & $RefreshAction $folder $desktopIniChange
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($InstallRoot)) {
        [void](Remove-PfiObsoleteAppliedResources $folder $InstallRoot)
    }
    Write-Host '[3/3] Reset and targeted Explorer refresh completed.'
    return [pscustomobject]@{
        Action = 'Reset'
        Folder = $folder
        Applied = $true
        RefreshSucceeded = ($SkipRefresh -or $null -eq $refresh -or $refresh.RefreshSucceeded)
        Refresh = $refresh
    }
}
