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

try {
    switch ($Action) {
        'Apply' {
            [void](Invoke-PfiApply -TargetPath $TargetPath -IconHash $IconHash -InstallRoot $installRoot)
        }
        'Reset' {
            [void](Invoke-PfiReset -TargetPath $TargetPath)
        }
        'Repair' {
            throw 'Repair support is not installed yet. Rerun repository setup after Phase 5.'
        }
        'Uninstall' {
            throw 'Uninstall support is not installed yet. Rerun repository setup after Phase 5.'
        }
    }
    Add-Type -AssemblyName PresentationFramework
    [void][Windows.MessageBox]::Show(
        ('{0} completed successfully.' -f $Action),
        'Portable Folder Icons',
        [Windows.MessageBoxButton]::OK,
        [Windows.MessageBoxImage]::Information
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
