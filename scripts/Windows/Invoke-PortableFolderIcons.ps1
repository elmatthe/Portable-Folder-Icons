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

try {
    switch ($Action) {
        'Apply' {
            [void](Assert-PfiSingleTarget -TargetPath $TargetPath)
            if ($IconHash -notmatch '^[a-fA-F0-9]{64}$') {
                throw 'The requested icon identity is invalid.'
            }
            throw 'Apply support is not installed yet. Rerun repository setup after Phase 4.'
        }
        'Reset' {
            [void](Assert-PfiSingleTarget -TargetPath $TargetPath)
            throw 'Reset support is not installed yet. Rerun repository setup after Phase 4.'
        }
        'Repair' {
            throw 'Repair support is not installed yet. Rerun repository setup after Phase 5.'
        }
        'Uninstall' {
            throw 'Uninstall support is not installed yet. Rerun repository setup after Phase 5.'
        }
    }
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
