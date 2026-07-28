Set-StrictMode -Version 2.0

$script:PfiProductionRegistryRoot = 'HKCU:\Software\Classes\Directory\shell\PortableFolderIcons'

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
        [switch]$IncludeTarget
    )

    $parts = @(
        (ConvertTo-PfiQuotedCommandArgument $PowerShellPath),
        '-NoLogo',
        '-NoProfile',
        '-WindowStyle Hidden',
        '-ExecutionPolicy Bypass',
        '-File',
        (ConvertTo-PfiQuotedCommandArgument $ActionScriptPath),
        '-Action',
        $Action
    )
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
        [string]$PowerShellPath = (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')
    )

    if (-not $RegistryRoot.StartsWith('HKCU:\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Context-menu registration is restricted to HKCU.'
    }
    $runtimeScript = Join-Path (Join-Path $InstallRoot 'runtime') 'Invoke-PortableFolderIcons.ps1'
    $subcommandsRoot = Join-Path $RegistryRoot 'ExtendedSubCommandsKey\shell'
    $plan = New-Object System.Collections.Generic.List[object]

    $plan.Add((New-PfiRegistryValue $RegistryRoot 'MUIVerb' 'Folder Icons'))
    $plan.Add((New-PfiRegistryValue $RegistryRoot 'MultiSelectModel' 'Single'))
    $plan.Add((New-PfiRegistryValue $RegistryRoot 'Icon' 'shell32.dll,3'))

    $accepted = @($Manifest.entries |
        Where-Object validationState -eq 'Accepted' |
        Sort-Object @{ Expression = { $_.menuLabel }; Ascending = $true })
    $ordinal = 0
    foreach ($entry in $accepted) {
        if ([string]::IsNullOrWhiteSpace([string]$entry.menuLabel) -or
            ([string]$entry.hash -notmatch '^[a-fA-F0-9]{64}$')) {
            throw 'Manifest contains an invalid accepted menu entry.'
        }
        $ordinal++
        $verbName = 'Icon_{0:D4}_{1}' -f $ordinal, ([string]$entry.hash).ToLowerInvariant()
        $verbPath = Join-Path $subcommandsRoot $verbName
        $cachedIcon = Join-Path (Join-Path $InstallRoot 'icons') ([string]$entry.cachedFilename)
        $command = New-PfiActionCommand $PowerShellPath $runtimeScript Apply ([string]$entry.hash) -IncludeTarget
        $plan.Add((New-PfiRegistryValue $verbPath 'MUIVerb' ([string]$entry.menuLabel)))
        $plan.Add((New-PfiRegistryValue $verbPath 'Icon' ($cachedIcon + ',0')))
        $plan.Add((New-PfiRegistryValue (Join-Path $verbPath 'command') '' $command))
    }

    $resetPath = Join-Path $subcommandsRoot 'Utility_0100_Reset'
    $plan.Add((New-PfiRegistryValue $resetPath 'MUIVerb' 'Reset to Default'))
    $plan.Add((New-PfiRegistryValue $resetPath 'CommandFlags' 32 'DWord'))
    $plan.Add((New-PfiRegistryValue (Join-Path $resetPath 'command') '' (
        New-PfiActionCommand $PowerShellPath $runtimeScript Reset -IncludeTarget
    )))

    $repairPath = Join-Path $subcommandsRoot 'Utility_0200_Repair'
    $plan.Add((New-PfiRegistryValue $repairPath 'MUIVerb' 'Repair Portable Folder Icons'))
    $plan.Add((New-PfiRegistryValue (Join-Path $repairPath 'command') '' (
        New-PfiActionCommand $PowerShellPath $runtimeScript Repair
    )))

    $uninstallPath = Join-Path $subcommandsRoot 'Utility_0300_Uninstall'
    $plan.Add((New-PfiRegistryValue $uninstallPath 'MUIVerb' 'Uninstall Portable Folder Icons'))
    $plan.Add((New-PfiRegistryValue (Join-Path $uninstallPath 'command') '' (
        New-PfiActionCommand $PowerShellPath $runtimeScript Uninstall
    )))
    return $plan.ToArray()
}

function Register-PfiContextMenu {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]$Manifest,
        [Parameter(Mandatory = $true)][string]$InstallRoot,
        [string]$RegistryRoot = $script:PfiProductionRegistryRoot
    )

    if (-not $RegistryRoot.Equals($script:PfiProductionRegistryRoot, [StringComparison]::OrdinalIgnoreCase) -and
        -not $RegistryRoot.StartsWith('HKCU:\Software\PortableFolderIcons\Tests\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Refusing to replace a registry key outside approved tool-owned roots.'
    }
    $plan = @(Get-PfiRegistryPlan -Manifest $Manifest -InstallRoot $InstallRoot -RegistryRoot $RegistryRoot)
    if (-not $PSCmdlet.ShouldProcess($RegistryRoot, 'Replace Portable Folder Icons context menu')) {
        return $plan
    }
    [void](Assert-PfiRegistryPath -RegistryPath $RegistryRoot -OwnedRoot $RegistryRoot -AllowRoot)
    if (Test-Path -LiteralPath $RegistryRoot) {
        Remove-Item -LiteralPath $RegistryRoot -Recurse -Force
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
    return $plan
}

function Remove-PfiContextMenu {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([string]$RegistryRoot = $script:PfiProductionRegistryRoot)

    if (-not $RegistryRoot.Equals($script:PfiProductionRegistryRoot, [StringComparison]::OrdinalIgnoreCase) -and
        -not $RegistryRoot.StartsWith('HKCU:\Software\PortableFolderIcons\Tests\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Refusing to remove a registry key outside approved tool-owned roots.'
    }
    if ($PSCmdlet.ShouldProcess($RegistryRoot, 'Remove Portable Folder Icons context menu') -and
        (Test-Path -LiteralPath $RegistryRoot)) {
        Remove-Item -LiteralPath $RegistryRoot -Recurse -Force
    }
}
