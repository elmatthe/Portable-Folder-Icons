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
# Phase 0B (ADR 015). OBSERVED COMPATIBILITY CONSTRAINT, not documented Windows behaviour: on the measured Windows 11
# build the Shell's static-menu builder showed at most this many entries per top-level static menu entry, counted
# depth-first across nested ExtendedSubCommandsKey submenus, and silently dropped the rest. Gate check c-0009
# re-measures it. Lower this one value for headroom; every allotment below is derived from it.
$script:PfiStaticMenuEntryBudget = 16
# Sorts after Utility_0100..0300, so Reset, Repair and Uninstall come first and can never be displaced by icons.
$script:PfiChooserVerbName = 'Utility_0900_Choose_Icons'
$script:PfiMaxOverflowMenus = 99
$script:PfiRangeLabelEndLength = 40
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

    # Normal mode starts every action through the installed windowless launcher: wscript.exe has no console, and the
    # launcher starts PowerShell with window style 0. Phase 0A.1: PowerShell's own '-WindowStyle Hidden' takes effect
    # only after Windows has created the console, and when that console is handed to Windows Terminal (the Windows 11
    # default terminal) it merely minimizes the terminal window, which stays open while a dialog is shown. Developer
    # Mode keeps its direct PowerShell commands unchanged.
    if (-not $DeveloperMode) {
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

function Get-PfiOrderedMenuEntries {
    # Accepted icons in menu order: case-insensitive invariant-culture label order with an ordinal tie-break, so the
    # order, the Apply command numbering and the overflow boundaries depend on neither the manifest order nor the
    # machine's culture. (Labels are unique ignoring case; setup rejects collisions.)
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Manifest)

    $entries = New-Object System.Collections.Generic.List[object]
    foreach ($entry in @($Manifest.entries | Where-Object validationState -eq 'Accepted')) {
        if ([string]::IsNullOrWhiteSpace([string]$entry.menuLabel) -or
            ([string]$entry.hash -notmatch '^[a-fA-F0-9]{64}$')) {
            throw 'Manifest contains an invalid accepted menu entry.'
        }
        $entries.Add($entry)
    }
    $entries.Sort([Comparison[object]] {
        param($left, $right)
        $order = [string]::Compare([string]$left.menuLabel, [string]$right.menuLabel,
            [StringComparison]::InvariantCultureIgnoreCase)
        if ($order -eq 0) { $order = [string]::CompareOrdinal([string]$left.menuLabel, [string]$right.menuLabel) }
        if ($order -eq 0) { $order = [string]::CompareOrdinal([string]$left.hash, [string]$right.hash) }
        return $order
    })
    return $entries.ToArray()
}

function Get-PfiOverflowMenuLabel {
    # 'Folder Icons (First<en dash>Last)', or 'Folder Icons (Only)' for one icon. Each end longer than the limit keeps
    # its first characters and gains an ellipsis. Non-ASCII characters are built from code points because Windows
    # PowerShell 5.1 reads this BOM-less script as ANSI.
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string[]]$Labels)

    $ends = @(foreach ($label in @($Labels[0], $Labels[$Labels.Count - 1])) {
        if ($label.Length -le $script:PfiRangeLabelEndLength) { $label; continue }
        $cut = $script:PfiRangeLabelEndLength - 1
        if ([char]::IsHighSurrogate($label[$cut - 1])) { $cut-- }
        $label.Substring(0, $cut).TrimEnd() + [char]0x2026
    })
    if ($Labels.Count -eq 1) { return ('Folder Icons ({0})' -f $ends[0]) }
    return ('Folder Icons ({0}{1}{2})' -f $ends[0], [char]0x2013, $ends[1])
}

function Get-PfiMenuLayout {
    # Primary chooser: a reserved allotment of the budget minus Reset, Repair, Uninstall and the chooser itself, so
    # the utilities never compete with icons. Remaining icons: top-level overflow entries of at most one budget each.
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Manifest)

    $ordered = @(Get-PfiOrderedMenuEntries -Manifest $Manifest)
    $primaryAllotment = $script:PfiStaticMenuEntryBudget - 4
    $overflowCapacity = $script:PfiStaticMenuEntryBudget
    $primaryCount = [Math]::Min($ordered.Count, $primaryAllotment)
    $overflowCount = [int][Math]::Ceiling(($ordered.Count - $primaryCount) / $overflowCapacity)
    if ($overflowCount -gt $script:PfiMaxOverflowMenus) {
        throw ('{0} icons were accepted, but the classic context menu can show at most {1}. Remove some ICO files, then rerun Setup_and_Run-Portable-Folder-Icons.bat.' -f
            $ordered.Count, ($primaryAllotment + $script:PfiMaxOverflowMenus * $overflowCapacity))
    }
    $overflow = @()
    for ($number = 1; $number -le $overflowCount; $number++) {
        $start = $primaryCount + ($number - 1) * $overflowCapacity
        $end = [Math]::Min($start + $overflowCapacity, $ordered.Count) - 1
        $pageEntries = @($ordered[$start..$end])
        $overflow += [pscustomobject]@{
            Number = $number
            Label = Get-PfiOverflowMenuLabel -Labels @($pageEntries | ForEach-Object { [string]$_.menuLabel })
            Entries = $pageEntries
        }
    }
    return [pscustomobject]@{
        Primary = @($(if ($primaryCount -gt 0) { $ordered[0..($primaryCount - 1)] }))
        Overflow = $overflow
    }
}

function Get-PfiOwnedOverflowRegistryPaths {
    # The overflow keys this product owns: exact siblings '<parent>.More.NN' and '<chooser store>.MoreNN' with
    # NN = 01..99. Any other name, including near lookalikes, is never returned and therefore never removed.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RegistryRoot,
        [Parameter(Mandatory = $true)][string]$IconChoicesRoot
    )

    $owned = New-Object System.Collections.Generic.List[string]
    foreach ($pair in @(@($RegistryRoot, '.More.'), @($IconChoicesRoot, '.More'))) {
        $container = Split-Path -Parent $pair[0]
        if (-not (Test-Path -LiteralPath $container)) { continue }
        $pattern = '^' + [regex]::Escape((Split-Path -Leaf $pair[0]) + $pair[1]) + '(0[1-9]|[1-9][0-9])$'
        foreach ($name in @((Get-Item -LiteralPath $container).GetSubKeyNames() | Sort-Object)) {
            if ($name -match $pattern) { $owned.Add((Join-Path $container $name)) }
        }
    }
    return $owned.ToArray()
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

    # Phase 0B (ADR 015): Reset, Repair and Uninstall first, then the chooser with a reserved allotment of icons; the
    # remaining icons go to top-level overflow entries, each its own static tree within the entry budget.
    $layout = Get-PfiMenuLayout -Manifest $Manifest
    $iconStores = New-Object System.Collections.Generic.List[object]
    if ($layout.Primary.Count -gt 0) {
        $chooserPath = Join-Path $subcommandsShell $script:PfiChooserVerbName
        $plan.Add((New-PfiRegistryValue $chooserPath 'MUIVerb' 'Choose Folder Icon'))
        $plan.Add((New-PfiRegistryValue $chooserPath 'Icon' 'shell32.dll,3'))
        $plan.Add((New-PfiRegistryValue $chooserPath 'ExtendedSubCommandsKey' $IconChoicesReference))
        # ECF_SEPARATORBEFORE: divides the utilities from the chooser (it previously sat on Reset).
        $plan.Add((New-PfiRegistryValue $chooserPath 'CommandFlags' 32 'DWord'))
        $iconStores.Add([pscustomobject]@{ Shell = $iconChoicesShell; Entries = $layout.Primary })
    }
    foreach ($page in @($layout.Overflow)) {
        $overflowParent = '{0}.More.{1:D2}' -f $RegistryRoot, $page.Number
        $plan.Add((New-PfiRegistryValue $overflowParent 'MUIVerb' ([string]$page.Label)))
        $plan.Add((New-PfiRegistryValue $overflowParent 'MultiSelectModel' 'Player'))
        $plan.Add((New-PfiRegistryValue $overflowParent 'Icon' 'shell32.dll,3'))
        $plan.Add((New-PfiRegistryValue $overflowParent 'ExtendedSubCommandsKey' (
            '{0}.More{1:D2}' -f $IconChoicesReference, $page.Number)))
        $iconStores.Add([pscustomobject]@{
            Shell = Join-Path ('{0}.More{1:D2}' -f $IconChoicesRoot, $page.Number) 'shell'
            Entries = $page.Entries
        })
    }
    # Apply command identities keep one ordinal sequence in menu order, wherever a verb is stored.
    $ordinal = 0
    foreach ($store in $iconStores) {
        foreach ($entry in @($store.Entries)) {
            $ordinal++
            $verbName = 'PortableFolderIcons.Apply.{0:D4}' -f $ordinal
            $verbPath = Join-Path $store.Shell $verbName
            $cachedIcon = Join-Path (Join-Path $InstallRoot 'icons') ([string]$entry.cachedFilename)
            $plan.Add((New-PfiRegistryValue $verbPath 'MUIVerb' ([string]$entry.menuLabel)))
            $plan.Add((New-PfiRegistryValue $verbPath 'Icon' ($cachedIcon + ',0')))
            $plan.Add((New-PfiRegistryValue $verbPath 'MultiSelectModel' 'Player'))
            $plan.Add((New-PfiRegistryValue $verbPath 'PfiAction' 'Apply'))
            $plan.Add((New-PfiRegistryValue $verbPath 'PfiIconHash' ([string]$entry.hash).ToLowerInvariant()))
            $plan.Add((New-PfiRegistryValue (Join-Path $verbPath 'command') 'DelegateExecute' $script:PfiSelectionBrokerClsid))
        }
    }

    $resetPath = Join-Path $subcommandsShell $script:PfiResetVerbName
    $plan.Add((New-PfiRegistryValue $resetPath 'MUIVerb' 'Reset to Default'))
    $plan.Add((New-PfiRegistryValue $resetPath 'MultiSelectModel' 'Player'))
    $plan.Add((New-PfiRegistryValue $resetPath 'PfiAction' 'Reset'))
    $plan.Add((New-PfiRegistryValue (Join-Path $resetPath 'command') 'DelegateExecute' $script:PfiSelectionBrokerClsid))

    $repairPath = Join-Path $subcommandsShell 'Utility_0200_Repair'
    $plan.Add((New-PfiRegistryValue $repairPath 'MUIVerb' 'Repair Portable Folder Icons'))
    $plan.Add((New-PfiRegistryValue $repairPath 'MultiSelectModel' 'Player'))
    $plan.Add((New-PfiRegistryValue (Join-Path $repairPath 'command') '' (
        New-PfiActionCommand $PowerShellPath $runtimeScript Repair -DeveloperMode $DeveloperMode -HiddenLauncherPath $hiddenLauncher
    )))

    $uninstallPath = Join-Path $subcommandsShell 'Utility_0300_Uninstall'
    $plan.Add((New-PfiRegistryValue $uninstallPath 'MUIVerb' 'Uninstall Portable Folder Icons'))
    $plan.Add((New-PfiRegistryValue $uninstallPath 'MultiSelectModel' 'Player'))
    $plan.Add((New-PfiRegistryValue (Join-Path $uninstallPath 'command') '' (
        New-PfiActionCommand $PowerShellPath $runtimeScript Uninstall -DeveloperMode $DeveloperMode -HiddenLauncherPath $hiddenLauncher
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
    # Reconcile overflow entries: remove every owned one, then the plan recreates exactly those the inventory needs,
    # so a smaller inventory leaves no obsolete entry behind.
    foreach ($overflowKey in @(Get-PfiOwnedOverflowRegistryPaths -RegistryRoot $RegistryRoot -IconChoicesRoot $IconChoicesRoot)) {
        Remove-Item -LiteralPath $overflowKey -Recurse -Force
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
    $overflowKeys = @(Get-PfiOwnedOverflowRegistryPaths -RegistryRoot $RegistryRoot -IconChoicesRoot $IconChoicesRoot)
    foreach ($ownedRoot in @($RegistryRoot, $SubcommandsRoot, $IconChoicesRoot, $SelectionBrokerClsidRoot) + $overflowKeys) {
        if ($PSCmdlet.ShouldProcess($ownedRoot, 'Remove Portable Folder Icons context menu') -and
            (Test-Path -LiteralPath $ownedRoot)) {
            Remove-Item -LiteralPath $ownedRoot -Recurse -Force
        }
    }
    Remove-PfiRecognizedLegacyContextMenus -DirectoryShellRoot $DirectoryShellRoot -Confirm:$false
    Invoke-PfiShellAssociationChanged
}
