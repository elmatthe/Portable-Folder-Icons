Set-StrictMode -Version 2.0

$script:PfiSelectionPayloadSchema = 1
$script:PfiSelectionPayloadMaxAgeMinutes = 15

function Get-PfiSelectionPayloadPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$InstallRoot,
        [Parameter(Mandatory = $true)][string]$SelectionToken
    )

    if ($SelectionToken -cnotmatch '^[a-f0-9]{32}$') {
        throw 'The Explorer selection token is invalid.'
    }
    $requestsRoot = Join-Path (Join-Path $InstallRoot 'state') 'requests'
    $payloadPath = Join-Path $requestsRoot ('request-' + $SelectionToken + '.json')
    [void](Assert-PfiPathWithinRoot -CandidatePath $payloadPath -AllowedRoot $requestsRoot)
    return $payloadPath
}

function Get-PfiSha256Bytes {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Read-PfiSelectionPayload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$InstallRoot,
        [Parameter(Mandatory = $true)][string]$SelectionToken,
        [Parameter(Mandatory = $true)][string]$PayloadHash,
        [datetime]$UtcNow = [DateTime]::UtcNow
    )

    if ($PayloadHash -cnotmatch '^[a-f0-9]{64}$') {
        throw 'The Explorer selection payload hash is invalid.'
    }
    $payloadPath = Get-PfiSelectionPayloadPath $InstallRoot $SelectionToken
    if (-not (Test-Path -LiteralPath $payloadPath -PathType Leaf)) {
        throw 'The Explorer selection payload is missing or has already been consumed.'
    }
    $item = Get-Item -LiteralPath $payloadPath -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'The Explorer selection payload cannot be a reparse point.'
    }
    try { $bytes = [IO.File]::ReadAllBytes($payloadPath) }
    catch { throw "The Explorer selection payload could not be read: $($_.Exception.Message)" }
    if ((Get-PfiSha256Bytes $bytes) -cne $PayloadHash) {
        throw 'The Explorer selection payload failed its SHA-256 integrity check.'
    }
    try {
        $json = (New-Object Text.UTF8Encoding($false, $true)).GetString($bytes)
        $payload = $json | ConvertFrom-Json
    }
    catch { throw 'The Explorer selection payload is malformed or is not valid UTF-8 JSON.' }

    $propertyNames = @($payload.PSObject.Properties | Select-Object -ExpandProperty Name | Sort-Object)
    $expectedNames = if ($payload.action -ceq 'Apply') {
        @('action', 'createdUtc', 'iconHash', 'paths', 'schemaVersion', 'token')
    }
    else {
        @('action', 'createdUtc', 'paths', 'schemaVersion', 'token')
    }
    if (($propertyNames -join ',') -cne (($expectedNames | Sort-Object) -join ',')) {
        throw 'The Explorer selection payload contains missing or unsupported fields.'
    }
    if ($payload.schemaVersion -ne $script:PfiSelectionPayloadSchema -or
        [string]$payload.token -cne $SelectionToken) {
        throw 'The Explorer selection payload schema or token is invalid.'
    }
    $createdUtc = [datetime]::MinValue
    if (-not [datetime]::TryParseExact(
        [string]$payload.createdUtc,
        'o',
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::RoundtripKind,
        [ref]$createdUtc
    )) {
        throw 'The Explorer selection payload timestamp is invalid.'
    }
    $createdUtc = $createdUtc.ToUniversalTime()
    if ($createdUtc -lt $UtcNow.ToUniversalTime().AddMinutes(-$script:PfiSelectionPayloadMaxAgeMinutes) -or
        $createdUtc -gt $UtcNow.ToUniversalTime().AddMinutes(1)) {
        throw 'The Explorer selection payload is stale or has an invalid future timestamp.'
    }
    if ([string]$payload.action -cnotin @('Apply', 'Reset')) {
        throw 'The Explorer selection payload action is invalid.'
    }
    if ($payload.action -ceq 'Apply') {
        if ([string]$payload.iconHash -cnotmatch '^[a-f0-9]{64}$') {
            throw 'The Explorer selection payload icon identity is invalid.'
        }
    }
    $paths = @($payload.paths)
    if ($paths.Count -eq 0) {
        throw 'Explorer supplied an empty folder selection.'
    }
    foreach ($path in $paths) {
        if ($path -isnot [string] -or [string]::IsNullOrWhiteSpace($path) -or $path.Contains([char]0)) {
            throw 'The Explorer selection payload contains an invalid folder path.'
        }
    }
    return [pscustomobject][ordered]@{
        SchemaVersion = [int]$payload.schemaVersion
        Token = [string]$payload.token
        CreatedUtc = $createdUtc
        Action = [string]$payload.action
        IconHash = if ($payload.action -ceq 'Apply') { [string]$payload.iconHash } else { '' }
        Paths = [string[]]$paths
        PayloadPath = $payloadPath
    }
}

function Remove-PfiSelectionPayload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$InstallRoot,
        [Parameter(Mandatory = $true)][string]$SelectionToken
    )

    $payloadPath = Get-PfiSelectionPayloadPath $InstallRoot $SelectionToken
    if (-not (Test-Path -LiteralPath $payloadPath)) { return $false }
    $item = Get-Item -LiteralPath $payloadPath -Force
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'Refusing to remove an invalid Explorer selection payload target.'
    }
    Remove-Item -LiteralPath $payloadPath -Force
    return $true
}

function Format-PfiAggregateResult {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Result)

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add(('{0} selected; {1} attempted; {2} succeeded; {3} failed; {4} rejected; {5} refresh warning(s).' -f
        $Result.SelectedCount, $Result.AttemptedCount, $Result.SuccessCount,
        $Result.FailureCount, $Result.RejectedCount, $Result.RefreshWarningCount))
    foreach ($target in @($Result.Results | Where-Object Status -ne 'Succeeded')) {
        $lines.Add('')
        $lines.Add(('[{0}] {1}' -f $target.Status, $target.InputPath))
        if (-not [string]::IsNullOrWhiteSpace([string]$target.Reason)) {
            $lines.Add([string]$target.Reason)
        }
    }
    return ($lines -join "`r`n")
}
