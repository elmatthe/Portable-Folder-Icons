[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Apply', 'Reset', 'Repair', 'Uninstall')]
    [string]$Action,
    [string]$IconHash,
    [string[]]$TargetPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$installRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'PortableFolderIcons.Core.ps1')
. (Join-Path $PSScriptRoot 'PortableFolderIcons.Integration.ps1')
. (Join-Path $PSScriptRoot 'PortableFolderIcons.Actions.ps1')
. (Join-Path $PSScriptRoot 'PortableFolderIcons.Maintenance.ps1')

try {
    $actionResult = $null
    switch ($Action) {
        'Apply' {
            $actionResult = Invoke-PfiApply -TargetPath $TargetPath -IconHash $IconHash -InstallRoot $installRoot
        }
        'Reset' {
            $actionResult = Invoke-PfiReset -TargetPath $TargetPath -InstallRoot $installRoot
        }
        'Repair' {
            $repair = Invoke-PfiRepair -InstallRoot $installRoot
            Add-Type -AssemblyName PresentationFramework
            [void][Windows.MessageBox]::Show(
                ("Repair completed.`nRuntime: valid`nCached icons checked: {0}`nRegistry: recreated`n`nRepair does not import repository icons. Rerun repository setup to rescan them." -f $repair.ValidatedIcons),
                'Portable Folder Icons',
                [Windows.MessageBoxButton]::OK,
                [Windows.MessageBoxImage]::Information
            )
            exit 0
        }
        'Uninstall' {
            Add-Type -AssemblyName PresentationFramework
            $confirm = [Windows.MessageBox]::Show(
                "Remove the Folder Icons context menu and installed runtime?`n`nCustomized folders will not be changed. The hashed icon cache will be preserved by default so their icons keep working.",
                'Uninstall Portable Folder Icons',
                [Windows.MessageBoxButton]::YesNo,
                [Windows.MessageBoxImage]::Warning
            )
            if ($confirm -ne [Windows.MessageBoxResult]::Yes) { exit 2 }
            $purge = [Windows.MessageBox]::Show(
                "Optional cache purge:`n`nPurging cached icons can BREAK icons already applied to folders.`n`nChoose Yes only if you intentionally want to purge the cache. Choose No to preserve it (recommended).",
                'Purge cached icons?',
                [Windows.MessageBoxButton]::YesNo,
                [Windows.MessageBoxImage]::Warning
            ) -eq [Windows.MessageBoxResult]::Yes
            $result = Invoke-PfiUninstall -InstallRoot $installRoot -Confirmed -PurgeCache:$purge
            [void][Windows.MessageBox]::Show(
                $(if ($result.CachePreserved) {
                    "Uninstall completed. Cached icons were preserved at:`n$($result.CachePath)`n`nThis keeps icons on already-customized folders working."
                } else {
                    'Uninstall completed and the cached icons were purged as requested.'
                }),
                'Portable Folder Icons',
                [Windows.MessageBoxButton]::OK,
                [Windows.MessageBoxImage]::Information
            )
            exit 0
        }
    }
    Add-Type -AssemblyName PresentationFramework
    $completionMessage = if ($null -ne $actionResult -and -not $actionResult.RefreshSucceeded) {
        ('{0} completed and the folder customization was saved, but Explorer could not be refreshed automatically. The icon may update after Explorer processes the change.' -f $Action)
    }
    else {
        ('{0} completed successfully.' -f $Action)
    }
    $completionImage = if ($null -ne $actionResult -and -not $actionResult.RefreshSucceeded) {
        [Windows.MessageBoxImage]::Warning
    }
    else {
        [Windows.MessageBoxImage]::Information
    }
    [void][Windows.MessageBox]::Show(
        $completionMessage,
        'Portable Folder Icons',
        [Windows.MessageBoxButton]::OK,
        $completionImage
    )
    exit 0
}
catch {
    Add-Type -AssemblyName PresentationFramework
    [void][Windows.MessageBox]::Show(
        $_.Exception.Message,
        'Portable Folder Icons',
        [Windows.MessageBoxButton]::OK,
        [Windows.MessageBoxImage]::Error
    )
    exit 1
}
