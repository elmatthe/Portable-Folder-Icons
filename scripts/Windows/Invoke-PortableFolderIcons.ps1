[CmdletBinding()]
param(
    [ValidateSet('Apply', 'Reset', 'Repair', 'Uninstall')]
    [string]$Action,
    [string]$IconHash,
    [string[]]$TargetPath,
    [string]$TargetPathHex,
    [string]$SelectionToken,
    [string]$PayloadHash
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$installRoot = Split-Path -Parent $PSScriptRoot
# Repeated here because the runtime modules that also hold it may be the thing that is missing.
$pfiSetupGuidance = 'To restore Portable Folder Icons, double-click Setup_and_Run-Portable-Folder-Icons.bat in your Portable Folder Icons folder. It needs no administrator rights.'

# Verification seam (Phase 0A, ADR 021). The gate runs this real dispatcher from a disposable install root and records
# its dialogs as JSON files instead of showing them. It is honoured ONLY when PFI_TEST_DIALOG_DIR is set AND this
# runtime is not the production install root, so the installed product always shows its dialogs. In test mode the
# Explorer menu is changed only under approved test registry roots (PFI_TEST_REGISTRY_ROOTS), never production keys.
$pfiTestDialogDir = $null
$pfiTestAnswers = New-Object 'System.Collections.Generic.Queue[string]'
$pfiTestSequence = 0
if (-not [string]::IsNullOrWhiteSpace($env:PFI_TEST_DIALOG_DIR) -and
    -not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
    $pfiProductionRoot = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'Portable-Folder-Icons')).TrimEnd('\')
    if (-not ([IO.Path]::GetFullPath($installRoot).TrimEnd('\')).Equals($pfiProductionRoot, [StringComparison]::OrdinalIgnoreCase)) {
        $pfiTestDialogDir = [IO.Path]::GetFullPath($env:PFI_TEST_DIALOG_DIR)
        foreach ($pfiAnswer in @(([string]$env:PFI_TEST_DIALOG_ANSWERS) -split ',')) {
            if (-not [string]::IsNullOrWhiteSpace($pfiAnswer)) { $pfiTestAnswers.Enqueue($pfiAnswer.Trim()) }
        }
    }
}

function Write-PfiTestRecord {
    param([string]$Kind, [System.Collections.IDictionary]$Record)
    $script:pfiTestSequence++
    $Record['processId'] = $PID
    $Record['sequence'] = $script:pfiTestSequence
    $Record['utcTicks'] = [DateTime]::UtcNow.Ticks
    $path = Join-Path $script:pfiTestDialogDir ('{0}-{1}.jsonl' -f $Kind, $PID)
    [IO.File]::AppendAllText($path, (($Record | ConvertTo-Json -Compress) + "`n"), (New-Object Text.UTF8Encoding($false)))
}

function Show-PfiDialog {
    # The one place this dispatcher shows a message box (Apply's completion box and the batch window excepted).
    param(
        [string]$Message,
        [string]$Title = 'Portable Folder Icons',
        [ValidateSet('OK', 'YesNo')][string]$Buttons = 'OK',
        [ValidateSet('Information', 'Warning', 'Error')][string]$Image = 'Information'
    )
    if ($null -ne $script:pfiTestDialogDir) {
        $answer = 'OK'
        if ($Buttons -eq 'YesNo') {
            $answer = if ($script:pfiTestAnswers.Count -gt 0) { $script:pfiTestAnswers.Dequeue() } else { 'No' }
        }
        Write-PfiTestRecord 'dialogs' ([ordered]@{ title = $Title; buttons = $Buttons; image = $Image; answer = $answer; message = $Message })
        return $answer
    }
    Add-Type -AssemblyName PresentationFramework
    $buttonValue = if ($Buttons -eq 'YesNo') { [Windows.MessageBoxButton]::YesNo } else { [Windows.MessageBoxButton]::OK }
    $imageValue = switch ($Image) {
        'Error' { [Windows.MessageBoxImage]::Error }
        'Warning' { [Windows.MessageBoxImage]::Warning }
        default { [Windows.MessageBoxImage]::Information }
    }
    return [string][Windows.MessageBox]::Show($Message, $Title, $buttonValue, $imageValue)
}

# Startup boundary (D3): the registered Repair/Uninstall commands run hidden, so a missing or unloadable module must
# end in one visible dialog that names it, in normal and Developer Mode alike (settings cannot be read yet).
$pfiModule = $null
try {
    foreach ($pfiModule in @(
        'PortableFolderIcons.Core.ps1',
        'PortableFolderIcons.Selection.ps1',
        'PortableFolderIcons.Integration.ps1',
        'PortableFolderIcons.Actions.ps1',
        'PortableFolderIcons.Maintenance.ps1'
    )) {
        $pfiModulePath = Join-Path $PSScriptRoot $pfiModule
        if (-not (Test-Path -LiteralPath $pfiModulePath -PathType Leaf)) {
            throw (New-Object System.IO.FileNotFoundException('The file is missing.', $pfiModulePath))
        }
        . $pfiModulePath
    }
}
catch {
    $pfiProblem = if ($_.Exception -is [System.IO.FileNotFoundException]) { 'is missing' }
    else { 'could not be loaded (' + ($_.Exception.Message -replace '\s+', ' ').Trim() + ')' }
    $pfiRequest = if ([string]::IsNullOrWhiteSpace($Action)) { 'The requested action' } else { $Action }
    try {
        [void](Show-PfiDialog ("Portable Folder Icons could not start because its installed runtime file {0} {1}.`n`n{2} did not run. Nothing was changed.`n`n{3}" -f $pfiModule, $pfiProblem, $pfiRequest, $pfiSetupGuidance) `
            'Portable Folder Icons' 'OK' 'Error')
    }
    catch { }
    exit 1
}
if ($null -ne $pfiTestDialogDir) {
    $script:PfiMaintenanceTrace = { param($EventName, $Detail) Write-PfiTestRecord 'trace' ([ordered]@{ event = $EventName; detail = $Detail }) }
}

try {
    $selectionMode = (
        -not [string]::IsNullOrEmpty($SelectionToken) -or
        -not [string]::IsNullOrEmpty($PayloadHash)
    )
    if ($selectionMode) {
        if ([string]::IsNullOrEmpty($SelectionToken) -or
            [string]::IsNullOrEmpty($PayloadHash)) {
            throw 'The Explorer selection token and payload hash must be supplied together.'
        }
        foreach ($legacyParameter in @('Action', 'IconHash', 'TargetPath', 'TargetPathHex')) {
            if ($PSBoundParameters.ContainsKey($legacyParameter)) {
                throw 'The Explorer selection payload cannot be combined with legacy action arguments.'
            }
        }
        $payload = $null
        try {
            $payload = Read-PfiSelectionPayload -InstallRoot $installRoot `
                -SelectionToken $SelectionToken -PayloadHash $PayloadHash
            $installedSettings = Read-PfiInstalledSettings (Join-Path $installRoot 'settings.json')
            $developerMode = [bool]$installedSettings.developerMode
            $batchResult = Invoke-PfiBatchAction -Action $payload.Action `
                -TargetPath $payload.Paths -IconHash $payload.IconHash -InstallRoot $installRoot
        }
        finally {
            if (Test-Path -LiteralPath (Get-PfiSelectionPayloadPath $installRoot $SelectionToken)) {
                [void](Remove-PfiSelectionPayload $installRoot $SelectionToken)
            }
        }
        if (-not $developerMode -and $batchResult.AllSucceeded) { exit 0 }

        $summary = Format-PfiAggregateResult $batchResult
        if ($developerMode -and $batchResult.AllSucceeded -and $payload.Action -eq 'Apply') {
            $summary += "`r`n`r`nAn already-open Explorer view may retain the previous folder color until refreshed. Press F5, navigate away and back, or open a new Explorer window/view."
        }
        Add-Type -AssemblyName PresentationFramework
        $window = New-Object Windows.Window
        $window.Title = 'Portable Folder Icons'
        $window.Width = 760
        $window.Height = 520
        $window.MinWidth = 520
        $window.MinHeight = 320
        $window.WindowStartupLocation = [Windows.WindowStartupLocation]::CenterScreen
        $panel = New-Object Windows.Controls.DockPanel
        $panel.Margin = '14'
        $button = New-Object Windows.Controls.Button
        $button.Content = 'OK'
        $button.Width = 90
        $button.Height = 28
        $button.Margin = '0,12,0,0'
        $button.HorizontalAlignment = [Windows.HorizontalAlignment]::Right
        $button.Add_Click({ $window.DialogResult = $true })
        [Windows.Controls.DockPanel]::SetDock($button, [Windows.Controls.Dock]::Bottom)
        [void]$panel.Children.Add($button)
        $details = New-Object Windows.Controls.TextBox
        $details.Text = $summary
        $details.IsReadOnly = $true
        $details.TextWrapping = [Windows.TextWrapping]::Wrap
        $details.VerticalScrollBarVisibility = [Windows.Controls.ScrollBarVisibility]::Auto
        $details.HorizontalScrollBarVisibility = [Windows.Controls.ScrollBarVisibility]::Auto
        [void]$panel.Children.Add($details)
        $window.Content = $panel
        [void]$window.ShowDialog()
        if ($batchResult.FailureCount -gt 0 -or $batchResult.RejectedCount -gt 0) { exit 1 }
        exit 0
    }
    if ([string]::IsNullOrWhiteSpace($Action)) {
        throw 'An action is required.'
    }
    if ($Action -in @('Repair', 'Uninstall')) {
        # Phase 0A: coordinated, accurately reported maintenance (PortableFolderIcons.Maintenance.ps1).
        $maintenanceArguments = @{
            Action = $Action
            InstallRoot = $installRoot
            ShowDialog = ${function:Show-PfiDialog}
        }
        if ($null -ne $pfiTestDialogDir) {
            # Test mode never touches the production menu: approved test roots, or no registry change at all.
            $maintenanceArguments['SkipRegistry'] = $true
            if (-not [string]::IsNullOrWhiteSpace($env:PFI_TEST_REGISTRY_ROOTS)) {
                $testRoots = $env:PFI_TEST_REGISTRY_ROOTS | ConvertFrom-Json
                $registryRoots = @{}
                foreach ($rootName in @('RegistryRoot', 'SubcommandsRoot', 'SubcommandsReference', 'IconChoicesRoot',
                        'IconChoicesReference', 'SelectionBrokerClsidRoot', 'DirectoryShellRoot')) {
                    $registryRoots[$rootName] = [string]$testRoots.$rootName
                }
                if (-not $registryRoots['RegistryRoot'].StartsWith('HKCU:\Software\PortableFolderIcons\Tests\', [StringComparison]::OrdinalIgnoreCase) -or
                    -not (Test-PfiApprovedRegistryRoots $registryRoots['RegistryRoot'] $registryRoots['SubcommandsRoot'] `
                        $registryRoots['IconChoicesRoot'] $registryRoots['SelectionBrokerClsidRoot'] $registryRoots['DirectoryShellRoot'])) {
                    throw 'Test mode accepts only approved test registry roots.'
                }
                $maintenanceArguments['RegistryRoots'] = $registryRoots
                $maintenanceArguments['SkipRegistry'] = $false
            }
            $testTimeout = 0
            if ([int]::TryParse([string]$env:PFI_TEST_LOCK_TIMEOUT_SECONDS, [ref]$testTimeout) -and $testTimeout -ge 0) {
                $maintenanceArguments['LockTimeoutSeconds'] = $testTimeout
            }
        }
        $maintenanceExit = @(Invoke-PfiMaintenanceRequest @maintenanceArguments)
        exit ([int]$maintenanceExit[-1])
    }
    if (-not [string]::IsNullOrEmpty($TargetPathHex)) {
        if ($TargetPathHex -notmatch '^(?:[0-9A-Fa-f]{4})+$') {
            throw 'The windowless launcher supplied an invalid target path.'
        }
        $characters = New-Object char[] ($TargetPathHex.Length / 4)
        for ($index = 0; $index -lt $characters.Length; $index++) {
            $characters[$index] = [char][Convert]::ToUInt16(
                $TargetPathHex.Substring($index * 4, 4),
                16
            )
        }
        $TargetPath = -join $characters
    }
    $installedSettings = Read-PfiInstalledSettings (Join-Path $installRoot 'settings.json')
    $developerMode = [bool]$installedSettings.developerMode
    $actionResult = $null
    switch ($Action) {
        'Apply' {
            $actionResult = Invoke-PfiApply -TargetPath $TargetPath -IconHash $IconHash -InstallRoot $installRoot
        }
        'Reset' {
            $actionResult = Invoke-PfiReset -TargetPath $TargetPath -InstallRoot $installRoot
        }
    }
    if (-not $developerMode -and
        ($null -eq $actionResult -or $actionResult.RefreshSucceeded)) {
        exit 0
    }
    Add-Type -AssemblyName PresentationFramework
    # This reports what was actually done, not what is on screen. Explorer caches
    # a folder's icon resource process-wide and may keep drawing the previous
    # icon for a while; that is a documented Explorer limitation, not a failure
    # of the operation. Claiming "completed successfully" without qualification
    # would assert something that has not been verified.
    $completionMessage = if ($null -ne $actionResult -and -not $actionResult.RefreshSucceeded) {
        ('{0} completed and the folder customization was saved, but Explorer could not be refreshed automatically. The icon may update after Explorer processes the change.' -f $Action)
    }
    elseif ($Action -eq 'Apply') {
        "Apply completed. The folder customization was saved.`n`nAn already-open Explorer view may retain the previous folder color until refreshed. Press F5, navigate away and back, or open a new Explorer window/view to display the current color."
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
    $failureMessage = $_.Exception.Message
    if ($_.Exception -is [System.Management.Automation.CommandNotFoundException]) {
        $failureMessage = 'The installed runtime is damaged: ' + $failureMessage
    }
    if ($Action -in @('Repair', 'Uninstall') -and
        $failureMessage -notmatch 'Setup_and_Run-Portable-Folder-Icons\.bat') {
        $failureMessage = "{0} could not complete.`n`n{1}`n`n{2}" -f $Action, $failureMessage, $pfiSetupGuidance
    }
    try { [void](Show-PfiDialog $failureMessage 'Portable Folder Icons' 'OK' 'Error') }
    catch { }
    exit 1
}
