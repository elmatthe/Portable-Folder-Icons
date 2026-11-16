Set-StrictMode -Version 2.0

$script:PfiProductionRegistryRoot = 'HKCU:\Software\Classes\Directory\shell\PortableFolderIcons'
$script:PfiProductionSubcommandsRoot = 'HKCU:\Software\Classes\PortableFolderIcons.ContextMenu'
$script:PfiProductionSubcommandsReference = 'PortableFolderIcons.ContextMenu'
$script:PfiProductionIconChoicesRoot = 'HKCU:\Software\Classes\PortableFolderIcons.ContextMenu.IconChoices'
$script:PfiProductionIconChoicesReference = 'PortableFolderIcons.ContextMenu.IconChoices'
$script:PfiProductionDirectoryShellRoot = 'HKCU:\Software\Classes\Directory\shell'
$script:PfiProductionSelectionBrokerClsidRoot = 'HKCU:\Software\Classes\CLSID\' + $script:PfiSelectionBrokerClsid
$script:PfiSelectionBrokerOwner = 'Portable-Folder-Icons.SelectionBroker'
$script:PfiResetVerbName = 'Utility_0100_Reset'
$script:PfiLegacyColorNames = @(
    'Black', 'Blue', 'Gray', 'Green', 'Orange',
    'Pink', 'Purple', 'Red', 'Teal', 'Yellow'
)

function Invoke-PfiShellAssociationChanged {
    [CmdletBinding()]
    param()

    if (-not ('PortableFolderIcons.IntegrationNativeMethods' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace PortableFolderIcons {
    public static class IntegrationNativeMethods {
        [DllImport("shell32.dll")]
        public static extern void SHChangeNotify(
            uint wEventId, uint uFlags, IntPtr dwItem1, IntPtr dwItem2
        );
    }
}
'@
    }
    [PortableFolderIcons.IntegrationNativeMethods]::SHChangeNotify(
        0x08000000,
        0,
        [IntPtr]::Zero,
        [IntPtr]::Zero
    )
}

function ConvertTo-PfiQuotedCommandArgument {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Value)

    if ($Value.Contains('"')) {
        throw 'Executable and script paths containing quotation marks are unsupported.'
    }
    return '"' + $Value + '"'
}

function New-PfiActionCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$PowerShellPath,
        [Parameter(Mandatory = $true)][string]$ActionScriptPath,
        [Parameter(Mandatory = $true)]
        [ValidateSet('Apply', 'Reset', 'Repair', 'Uninstall')]
        [string]$Action,
        [string]$IconHash,
        [switch]$IncludeTarget,
        [bool]$DeveloperMode = $false,
        [string]$HiddenLauncherPath,
        [string]$WScriptPath = (Join-Path $env:SystemRoot 'System32\wscript.exe')
    )

    if ($Action -in @('Apply', 'Reset') -and -not $DeveloperMode) {
        if ([string]::IsNullOrWhiteSpace($HiddenLauncherPath)) {
            throw 'The windowless action launcher path is required in normal mode.'
        }
        $hiddenParts = @(
            (ConvertTo-PfiQuotedCommandArgument $WScriptPath),
            (ConvertTo-PfiQuotedCommandArgument $HiddenLauncherPath),
            '-Action',
            $Action
        )
        if (-not [string]::IsNullOrWhiteSpace($IconHash)) {
            if ($IconHash -notmatch '^[a-fA-F0-9]{64}$') {
                throw 'Icon identity must be a full SHA-256 hash.'
            }
            $hiddenParts += @('-IconHash', $IconHash.ToLowerInvariant())
        }
        if ($IncludeTarget) { $hiddenParts += @('-TargetPath', '"%1"') }
        return ($hiddenParts -join ' ')
    }

    $parts = @(
        (ConvertTo-PfiQuotedCommandArgument $PowerShellPath),
        '-NoLogo',
        '-NoProfile',
        '-ExecutionPolicy Bypass',
        '-File',
        (ConvertTo-PfiQuotedCommandArgument $ActionScriptPath),
        '-Action',
        $Action
    )
    if ($Action -notin @('Apply', 'Reset')) {
        $parts = @($parts[0..2]) + @('-WindowStyle Hidden') + @($parts[3..($parts.Count - 1)])
    }
    if (-not [string]::IsNullOrWhiteSpace($IconHash)) {
        if ($IconHash -notmatch '^[a-fA-F0-9]{64}$') {
            throw 'Icon identity must be a full SHA-256 hash.'
        }
        $parts += @('-IconHash', $IconHash.ToLowerInvariant())
    }
    if ($IncludeTarget) {
        $parts += @('-TargetPath', '"%1"')
    }
    return ($parts -join ' ')
}

function New-PfiRegistryValue {
    param(
        [string]$Path,
        [AllowEmptyString()][string]$Name,
        $Value,
        [ValidateSet('String', 'DWord')][string]$Type = 'String'
    )
    return [pscustomobject][ordered]@{
        Path = $Path
        Name = $Name
        Value = $Value
        Type = $Type
    }
}

function Get-PfiRegistryPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Manifest,
        [Parameter(Mandatory = $true)][string]$InstallRoot,
        [string]$RegistryRoot = $script:PfiProductionRegistryRoot,
        [string]$SubcommandsRoot = $script:PfiProductionSubcommandsRoot,
        [string]$SubcommandsReference = $script:PfiProductionSubcommandsReference,
        [string]$IconChoicesRoot = $script:PfiProductionIconChoicesRoot,
        [string]$IconChoicesReference = $script:PfiProductionIconChoicesReference,
        [string]$SelectionBrokerClsidRoot = $script:PfiProductionSelectionBrokerClsidRoot,
        [Parameter(Mandatory = $true)][string]$SelectionBrokerHash,
        [string]$PowerShellPath = (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'),
        [bool]$DeveloperMode = $false
    )

    if (-not $RegistryRoot.StartsWith('HKCU:\', [StringComparison]::OrdinalIgnoreCase) -or
        -not $SubcommandsRoot.StartsWith('HKCU:\', [StringComparison]::OrdinalIgnoreCase) -or
        -not $IconChoicesRoot.StartsWith('HKCU:\', [StringComparison]::OrdinalIgnoreCase) -or
        -not $SelectionBrokerClsidRoot.StartsWith('HKCU:\Software\Classes\CLSID\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Context-menu registration is restricted to HKCU.'
    }
    if ([string]::IsNullOrWhiteSpace($SubcommandsReference) -or
        $SubcommandsReference.StartsWith('\') -or
        $SubcommandsReference.Contains(':')) {
        throw 'The submenu reference must be an HKCR-relative registry path.'
    }
    $referencedRoot = 'HKCU:\Software\Classes\' + $SubcommandsReference.TrimStart('\')
    if (-not $SubcommandsRoot.Equals($referencedRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'The submenu storage path does not match the HKCR-relative parent reference.'
    }
    if ([string]::IsNullOrWhiteSpace($IconChoicesReference) -or
        $IconChoicesReference.StartsWith('\') -or $IconChoicesReference.Contains(':')) {
        throw 'The icon chooser reference must be an HKCR-relative registry path.'
    }
    $referencedChoicesRoot = 'HKCU:\Software\Classes\' + $IconChoicesReference.TrimStart('\')
    if (-not $IconChoicesRoot.Equals($referencedChoicesRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'The icon chooser storage path does not match its HKCR-relative reference.'
    }
    $runtimeScript = Join-Path (Join-Path $InstallRoot 'runtime') 'Invoke-PortableFolderIcons.ps1'
    $hiddenLauncher = Join-Path (Join-Path $InstallRoot 'runtime') 'Invoke-PortableFolderIcons.Hidden.vbs'
    $selectionBroker = Join-Path (Join-Path (Join-Path $InstallRoot 'runtime') 'SelectionHandler') `
        'PortableFolderIcons.SelectionBroker.exe'
    $subcommandsShell = Join-Path $SubcommandsRoot 'shell'
    $iconChoicesShell = Join-Path $IconChoicesRoot 'shell'
    $plan = New-Object System.Collections.Generic.List[object]

    $plan.Add((New-PfiRegistryValue $RegistryRoot 'MUIVerb' 'Folder Icons'))
    if ($SelectionBrokerHash -cnotmatch '^[a-f0-9]{64}$') {
        throw 'The selection broker identity must be a lowercase SHA-256 hash.'
    }
    $plan.Add((New-PfiRegistryValue $RegistryRoot 'MultiSelectModel' 'Player'))
    $plan.Add((New-PfiRegistryValue $RegistryRoot 'Icon' 'shell32.dll,3'))
    $plan.Add((New-PfiRegistryValue $RegistryRoot 'ExtendedSubCommandsKey' $SubcommandsReference))

    $accepted = @($Manifest.entries |
        Where-Object validationState -eq 'Accepted' |
        Sort-Object @{ Expression = { $_.menuLabel }; Ascending = $true })
    if ($accepted.Count -gt 0) {
        $chooserPath = Join-Path $subcommandsShell 'Choice_0100_Icons'
        $plan.Add((New-PfiRegistryValue $chooserPath 'MUIVerb' 'Choose Folder Icon'))
        $plan.Add((New-PfiRegistryValue $chooserPath 'Icon' 'shell32.dll,3'))
        $plan.Add((New-PfiRegistryValue $chooserPath 'ExtendedSubCommandsKey' $IconChoicesReference))
    }
    $ordinal = 0
    foreach ($entry in $accepted) {
        if ([string]::IsNullOrWhiteSpace([string]$entry.menuLabel) -or
            ([string]$entry.hash -notmatch '^[a-fA-F0-9]{64}$')) {
            throw 'Manifest contains an invalid accepted menu entry.'
        }
        $ordinal++
        $verbName = 'PortableFolderIcons.Apply.{0:D4}' -f $ordinal
        $verbPath = Join-Path $iconChoicesShell $verbName
        $cachedIcon = Join-Path (Join-Path $InstallRoot 'icons') ([string]$entry.cachedFilename)
        $plan.Add((New-PfiRegistryValue $verbPath 'MUIVerb' ([string]$entry.menuLabel)))
        $plan.Add((New-PfiRegistryValue $verbPath 'Icon' ($cachedIcon + ',0')))
        $plan.Add((New-PfiRegistryValue $verbPath 'MultiSelectModel' 'Player'))
        $plan.Add((New-PfiRegistryValue $verbPath 'PfiAction' 'Apply'))
        $plan.Add((New-PfiRegistryValue $verbPath 'PfiIconHash' ([string]$entry.hash).ToLowerInvariant()))
        $plan.Add((New-PfiRegistryValue (Join-Path $verbPath 'command') 'DelegateExecute' $script:PfiSelectionBrokerClsid))
    }

    $resetPath = Join-Path $subcommandsShell $script:PfiResetVerbName
    $plan.Add((New-PfiRegistryValue $resetPath 'MUIVerb' 'Reset to Default'))
    $plan.Add((New-PfiRegistryValue $resetPath 'CommandFlags' 32 'DWord'))
    $plan.Add((New-PfiRegistryValue $resetPath 'MultiSelectModel' 'Player'))
    $plan.Add((New-PfiRegistryValue $resetPath 'PfiAction' 'Reset'))
    $plan.Add((New-PfiRegistryValue (Join-Path $resetPath 'command') 'DelegateExecute' $script:PfiSelectionBrokerClsid))

    $repairPath = Join-Path $subcommandsShell 'Utility_0200_Repair'
    $plan.Add((New-PfiRegistryValue $repairPath 'MUIVerb' 'Repair Portable Folder Icons'))
    $plan.Add((New-PfiRegistryValue $repairPath 'MultiSelectModel' 'Player'))
    $plan.Add((New-PfiRegistryValue (Join-Path $repairPath 'command') '' (
        New-PfiActionCommand $PowerShellPath $runtimeScript Repair
    )))

    $uninstallPath = Join-Path $subcommandsShell 'Utility_0300_Uninstall'
    $plan.Add((New-PfiRegistryValue $uninstallPath 'MUIVerb' 'Uninstall Portable Folder Icons'))
    $plan.Add((New-PfiRegistryValue $uninstallPath 'MultiSelectModel' 'Player'))
    $plan.Add((New-PfiRegistryValue (Join-Path $uninstallPath 'command') '' (
        New-PfiActionCommand $PowerShellPath $runtimeScript Uninstall
    )))
    $plan.Add((New-PfiRegistryValue $SelectionBrokerClsidRoot '' 'Portable Folder Icons Selection Broker'))
    $plan.Add((New-PfiRegistryValue $SelectionBrokerClsidRoot 'PfiOwner' $script:PfiSelectionBrokerOwner))
    $plan.Add((New-PfiRegistryValue $SelectionBrokerClsidRoot 'PfiBrokerSha256' $SelectionBrokerHash))
    $localServer = Join-Path $SelectionBrokerClsidRoot 'LocalServer32'
    $plan.Add((New-PfiRegistryValue $localServer '' (ConvertTo-PfiQuotedCommandArgument $selectionBroker)))
    $plan.Add((New-PfiRegistryValue $localServer 'ServerExecutable' $selectionBroker))
    return $plan.ToArray()
}

function Test-PfiApprovedRegistryRoots {
    param(
        [string]$RegistryRoot,
        [string]$SubcommandsRoot,
        [string]$IconChoicesRoot,
        [string]$SelectionBrokerClsidRoot,
        [string]$DirectoryShellRoot
    )

    $production = (
        $RegistryRoot.Equals($script:PfiProductionRegistryRoot, [StringComparison]::OrdinalIgnoreCase) -and
        $SubcommandsRoot.Equals($script:PfiProductionSubcommandsRoot, [StringComparison]::OrdinalIgnoreCase) -and
        $IconChoicesRoot.Equals($script:PfiProductionIconChoicesRoot, [StringComparison]::OrdinalIgnoreCase) -and
        $SelectionBrokerClsidRoot.Equals($script:PfiProductionSelectionBrokerClsidRoot, [StringComparison]::OrdinalIgnoreCase) -and
        $DirectoryShellRoot.Equals($script:PfiProductionDirectoryShellRoot, [StringComparison]::OrdinalIgnoreCase)
    )
    $testPrefix = 'HKCU:\Software\PortableFolderIcons\Tests\'
    $testClassesPrefix = 'HKCU:\Software\Classes\PortableFolderIcons.Tests.'
    $test = (
        $RegistryRoot.StartsWith($testPrefix, [StringComparison]::OrdinalIgnoreCase) -and
        $SubcommandsRoot.StartsWith($testClassesPrefix, [StringComparison]::OrdinalIgnoreCase) -and
        $IconChoicesRoot.StartsWith($testClassesPrefix, [StringComparison]::OrdinalIgnoreCase) -and
        $SelectionBrokerClsidRoot -match '(?i)^HKCU:\\Software\\Classes\\CLSID\\\{[0-9a-f-]{36}\}$' -and
        $DirectoryShellRoot.StartsWith($testPrefix, [StringComparison]::OrdinalIgnoreCase)
    )
    return ($production -or $test)
}

function Test-PfiSelectionBrokerRegistryOwnership {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$SelectionBrokerClsidRoot,
        [Parameter(Mandatory = $true)][string]$InstallRoot
    )

    if (-not (Test-Path -LiteralPath $SelectionBrokerClsidRoot)) { return $true }
    $localServer = Join-Path $SelectionBrokerClsidRoot 'LocalServer32'
    if (-not (Test-Path -LiteralPath $localServer)) { return $false }
    $expectedBroker = Join-Path (Join-Path (Join-Path $InstallRoot 'runtime') 'SelectionHandler') `
        'PortableFolderIcons.SelectionBroker.exe'
    $rootKey = Get-Item -LiteralPath $SelectionBrokerClsidRoot
    $localKey = Get-Item -LiteralPath $localServer
    return (
        [string]$rootKey.GetValue('') -ceq 'Portable Folder Icons Selection Broker' -and
        [string]$rootKey.GetValue('PfiOwner') -ceq $script:PfiSelectionBrokerOwner -and
        [string]$rootKey.GetValue('PfiBrokerSha256') -cmatch '^[a-f0-9]{64}$' -and
        [string]$localKey.GetValue('') -ceq (ConvertTo-PfiQuotedCommandArgument $expectedBroker) -and
        [string]$localKey.GetValue('ServerExecutable') -ceq $expectedBroker
    )
}

function Get-PfiRecognizedLegacyContextMenuPaths {
    [CmdletBinding()]
    param([string]$DirectoryShellRoot = $script:PfiProductionDirectoryShellRoot)

    $recognized = New-Object System.Collections.Generic.List[string]
    foreach ($color in $script:PfiLegacyColorNames) {
        $keyPath = Join-Path $DirectoryShellRoot ('FolderColor_' + $color)
        $commandPath = Join-Path $keyPath 'command'
        if (-not (Test-Path -LiteralPath $keyPath) -or
            -not (Test-Path -LiteralPath $commandPath)) {
            continue
        }
        $key = Get-Item -LiteralPath $keyPath
        $commandKey = Get-Item -LiteralPath $commandPath
        $label = [string]$key.GetValue('')
        $command = [string]$commandKey.GetValue('')
        $expectedIconArgument = '(?i)-iconPath\s+".*Folder_' + [regex]::Escape($color) + '\.ico,0"'
        if ($label -ceq ('Color: ' + $color) -and
            $command -match '(?i)[\\/]SetFolderColor\.ps1"' -and
            $command -match '(?i)-folderPath\s+"%1"' -and
            $command -match $expectedIconArgument) {
            $recognized.Add($keyPath)
        }
    }
    return $recognized.ToArray()
}

function Remove-PfiRecognizedLegacyContextMenus {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([string]$DirectoryShellRoot = $script:PfiProductionDirectoryShellRoot)

    foreach ($keyPath in @(Get-PfiRecognizedLegacyContextMenuPaths -DirectoryShellRoot $DirectoryShellRoot)) {
        if ($PSCmdlet.ShouldProcess($keyPath, 'Remove recognized legacy Portable Folder Icons verb')) {
            Remove-Item -LiteralPath $keyPath -Recurse -Force
        }
    }
}

function Register-PfiContextMenu {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]$Manifest,
        [Parameter(Mandatory = $true)][string]$InstallRoot,
        [string]$RegistryRoot = $script:PfiProductionRegistryRoot,
        [string]$SubcommandsRoot = $script:PfiProductionSubcommandsRoot,
        [string]$SubcommandsReference = $script:PfiProductionSubcommandsReference,
        [string]$IconChoicesRoot = $script:PfiProductionIconChoicesRoot,
        [string]$IconChoicesReference = $script:PfiProductionIconChoicesReference,
        [string]$SelectionBrokerClsidRoot = $script:PfiProductionSelectionBrokerClsidRoot,
        [string]$DirectoryShellRoot = $script:PfiProductionDirectoryShellRoot,
        [bool]$DeveloperMode = $false
    )

    if (-not (Test-PfiApprovedRegistryRoots $RegistryRoot $SubcommandsRoot $IconChoicesRoot `
        $SelectionBrokerClsidRoot $DirectoryShellRoot)) {
        throw 'Refusing to replace registry keys outside approved tool-owned roots.'
    }
    if (-not (Test-PfiSelectionBrokerRegistryOwnership $SelectionBrokerClsidRoot $InstallRoot)) {
        throw 'Refusing to replace a COM registration that is not exactly owned by Portable Folder Icons.'
    }
    $selectionRoot = Join-Path (Join-Path $InstallRoot 'runtime') 'SelectionHandler'
    $buildManifest = Read-PfiSelectionBrokerBuildManifest `
        (Join-Path $selectionRoot 'SelectionBroker.build.json')
    $brokerInfo = Test-PfiSelectionBrokerArtifact `
        (Join-Path $selectionRoot 'PortableFolderIcons.SelectionBroker.exe') $buildManifest
    $plan = @(Get-PfiRegistryPlan -Manifest $Manifest -InstallRoot $InstallRoot `
        -RegistryRoot $RegistryRoot -SubcommandsRoot $SubcommandsRoot `
        -SubcommandsReference $SubcommandsReference -IconChoicesRoot $IconChoicesRoot `
        -IconChoicesReference $IconChoicesReference `
        -SelectionBrokerClsidRoot $SelectionBrokerClsidRoot `
        -SelectionBrokerHash $brokerInfo.Sha256 -DeveloperMode $DeveloperMode)
    if (-not $PSCmdlet.ShouldProcess($RegistryRoot, 'Replace Portable Folder Icons context menu')) {
        return $plan
    }
    [void](Assert-PfiRegistryPath -RegistryPath $RegistryRoot -OwnedRoot $RegistryRoot -AllowRoot)
    [void](Assert-PfiRegistryPath -RegistryPath $SubcommandsRoot -OwnedRoot $SubcommandsRoot -AllowRoot)
    [void](Assert-PfiRegistryPath -RegistryPath $IconChoicesRoot -OwnedRoot $IconChoicesRoot -AllowRoot)
    [void](Assert-PfiRegistryPath -RegistryPath $SelectionBrokerClsidRoot `
        -OwnedRoot $SelectionBrokerClsidRoot -AllowRoot)
    if (Test-Path -LiteralPath $RegistryRoot) {
        Remove-Item -LiteralPath $RegistryRoot -Recurse -Force
    }
    if (Test-Path -LiteralPath $SubcommandsRoot) {
        Remove-Item -LiteralPath $SubcommandsRoot -Recurse -Force
    }
    if (Test-Path -LiteralPath $IconChoicesRoot) {
        Remove-Item -LiteralPath $IconChoicesRoot -Recurse -Force
    }
    if (Test-Path -LiteralPath $SelectionBrokerClsidRoot) {
        Remove-Item -LiteralPath $SelectionBrokerClsidRoot -Recurse -Force
    }
    foreach ($item in $plan) {
        if (-not (Test-Path -LiteralPath $item.Path)) {
            [void](New-Item -Path $item.Path -Force)
        }
        if ([string]::IsNullOrEmpty($item.Name)) {
            Set-Item -LiteralPath $item.Path -Value $item.Value
        }
        else {
            New-ItemProperty -LiteralPath $item.Path -Name $item.Name -Value $item.Value `
                -PropertyType $item.Type -Force | Out-Null
        }
    }
    Remove-PfiRecognizedLegacyContextMenus -DirectoryShellRoot $DirectoryShellRoot -Confirm:$false
    Invoke-PfiShellAssociationChanged
    return $plan
}

function Remove-PfiContextMenu {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)][string]$InstallRoot,
        [string]$RegistryRoot = $script:PfiProductionRegistryRoot,
        [string]$SubcommandsRoot = $script:PfiProductionSubcommandsRoot,
        [string]$IconChoicesRoot = $script:PfiProductionIconChoicesRoot,
        [string]$SelectionBrokerClsidRoot = $script:PfiProductionSelectionBrokerClsidRoot,
        [string]$DirectoryShellRoot = $script:PfiProductionDirectoryShellRoot
    )

    if (-not (Test-PfiApprovedRegistryRoots $RegistryRoot $SubcommandsRoot $IconChoicesRoot `
        $SelectionBrokerClsidRoot $DirectoryShellRoot)) {
        throw 'Refusing to remove registry keys outside approved tool-owned roots.'
    }
    if (-not (Test-PfiSelectionBrokerRegistryOwnership $SelectionBrokerClsidRoot $InstallRoot)) {
        throw 'Refusing to remove a COM registration that is not exactly owned by Portable Folder Icons.'
    }
    foreach ($ownedRoot in @($RegistryRoot, $SubcommandsRoot, $IconChoicesRoot, $SelectionBrokerClsidRoot)) {
        if ($PSCmdlet.ShouldProcess($ownedRoot, 'Remove Portable Folder Icons context menu') -and
            (Test-Path -LiteralPath $ownedRoot)) {
            Remove-Item -LiteralPath $ownedRoot -Recurse -Force
        }
    }
    Remove-PfiRecognizedLegacyContextMenus -DirectoryShellRoot $DirectoryShellRoot -Confirm:$false
    Invoke-PfiShellAssociationChanged
}
