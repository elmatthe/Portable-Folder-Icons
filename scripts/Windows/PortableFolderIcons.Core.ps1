Set-StrictMode -Version 2.0

$script:PfiVersion = '0.1.0'
$script:PfiManifestSchema = 1

function ConvertTo-PfiMenuLabel {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$FileName)

    $label = [IO.Path]::GetFileName($FileName)
    if ($label -match '(?i)\.ico$') {
        $label = $label.Substring(0, $label.Length - 4)
    }
    $label = [regex]::Replace($label, '^(?i:Folder[_\- ])', '')
    $label = $label.Replace('_', ' ')
    $label = [regex]::Replace($label, '\s+', ' ').Trim()
    if ([string]::IsNullOrWhiteSpace($label)) {
        throw "The filename '$FileName' produces an empty menu label."
    }
    return $label
}

function Get-PfiSha256 {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$LiteralPath)

    $stream = $null
    $sha = $null
    try {
        $stream = [IO.File]::Open(
            $LiteralPath,
            [IO.FileMode]::Open,
            [IO.FileAccess]::Read,
            [IO.FileShare]::Read
        )
        $sha = [Security.Cryptography.SHA256]::Create()
        return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        if ($null -ne $sha) { $sha.Dispose() }
        if ($null -ne $stream) { $stream.Dispose() }
    }
}

function Test-PfiIcoFile {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$LiteralPath)

    $result = [ordered]@{
        IsValid = $false
        Reason = ''
        Hash = $null
        Width = $null
        Height = $null
    }
    $stream = $null
    $icon = $null
    try {
        $item = Get-Item -LiteralPath $LiteralPath -Force -ErrorAction Stop
        if ($item.PSIsContainer) { throw 'Candidate is not a regular file.' }
        if ($item.Extension -ine '.ico') { throw 'Candidate does not have the .ico extension.' }
        if ($item.Length -eq 0) { throw 'ICO file is empty.' }
        $stream = [IO.File]::Open(
            $item.FullName,
            [IO.FileMode]::Open,
            [IO.FileAccess]::Read,
            [IO.FileShare]::Read
        )
        $icon = New-Object Drawing.Icon($stream)
        $result.Width = $icon.Width
        $result.Height = $icon.Height
        if ($result.Width -lt 1 -or $result.Height -lt 1) {
            throw 'ICO has unsupported dimensions.'
        }
        $result.Hash = Get-PfiSha256 -LiteralPath $item.FullName
        $result.IsValid = $true
        $result.Reason = 'Valid ICO.'
    }
    catch {
        $result.Reason = $_.Exception.Message
    }
    finally {
        if ($null -ne $icon) { $icon.Dispose() }
        if ($null -ne $stream) { $stream.Dispose() }
    }
    return [pscustomobject]$result
}

function Get-PfiIconInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$SourceDirectory,
        [Parameter(Mandatory = $true)][string]$CacheDirectory
    )

    $results = New-Object System.Collections.Generic.List[object]
    if (-not (Test-Path -LiteralPath $SourceDirectory -PathType Container)) {
        return @()
    }
    $candidates = @(Get-ChildItem -LiteralPath $SourceDirectory -Filter '*.ico' -File -Force |
        Sort-Object Name)
    foreach ($candidate in $candidates) {
        $label = $null
        try { $label = ConvertTo-PfiMenuLabel -FileName $candidate.Name }
        catch {
            $results.Add([pscustomobject][ordered]@{
                Status = 'Rejected'; MenuLabel = ''; SourceFile = $candidate.Name
                Hash = ''; CachedFile = ''; CacheAction = 'None'; Reason = $_.Exception.Message
            })
            continue
        }
        $validation = Test-PfiIcoFile -LiteralPath $candidate.FullName
        if (-not $validation.IsValid) {
            $results.Add([pscustomobject][ordered]@{
                Status = 'Rejected'; MenuLabel = $label; SourceFile = $candidate.Name
                Hash = ''; CachedFile = ''; CacheAction = 'None'; Reason = $validation.Reason
            })
            continue
        }
        $cachedFile = '{0}.ico' -f $validation.Hash
        $cachePath = Join-Path $CacheDirectory $cachedFile
        $action = 'Copy'
        if (Test-Path -LiteralPath $cachePath -PathType Leaf) {
            try {
                if ((Get-PfiSha256 -LiteralPath $cachePath) -eq $validation.Hash) {
                    $action = 'Reuse'
                }
                else {
                    $action = 'RejectCacheConflict'
                }
            }
            catch { $action = 'RejectCacheConflict' }
        }
        $status = if ($action -eq 'RejectCacheConflict') { 'Rejected' } else { 'Accepted' }
        $reason = if ($status -eq 'Accepted') { 'Valid ICO.' } else { 'Cached hash filename contains different content.' }
        $results.Add([pscustomobject][ordered]@{
            Status = $status; MenuLabel = $label; SourceFile = $candidate.Name
            Hash = $validation.Hash; CachedFile = $cachedFile; CacheAction = $action; Reason = $reason
        })
    }

    $accepted = @($results | Where-Object { $_.Status -eq 'Accepted' })
    foreach ($group in @($accepted | Group-Object { $_.MenuLabel.ToUpperInvariant() })) {
        if ($group.Count -gt 1) {
            foreach ($entry in $group.Group) {
                $entry.Status = 'Rejected'
                $entry.CacheAction = 'None'
                $entry.Reason = 'Menu label collision; rename all colliding source files.'
            }
        }
    }
    return $results.ToArray()
}

function New-PfiManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$Inventory,
        [datetime]$InstalledAt = (Get-Date)
    )

    $entries = @($Inventory | ForEach-Object {
        [ordered]@{
            menuLabel = $_.MenuLabel
            originalFilename = $_.SourceFile
            hash = $_.Hash
            cachedFilename = $_.CachedFile
            validationState = $_.Status
            reason = $_.Reason
        }
    })
    return [ordered]@{
        schemaVersion = $script:PfiManifestSchema
        productVersion = $script:PfiVersion
        installedAt = $InstalledAt.ToUniversalTime().ToString('o')
        entries = $entries
    }
}

function Write-PfiManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Manifest,
        [Parameter(Mandatory = $true)][string]$LiteralPath
    )

    $parent = Split-Path -Parent $LiteralPath
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $parent -Force)
    }
    $temporaryPath = '{0}.{1}.tmp' -f $LiteralPath, [guid]::NewGuid().ToString('N')
    try {
        $json = $Manifest | ConvertTo-Json -Depth 8
        [IO.File]::WriteAllText($temporaryPath, $json, (New-Object Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $temporaryPath -Destination $LiteralPath -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
    }
}

function Read-PfiManifest {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$LiteralPath)

    try {
        $manifest = Get-Content -LiteralPath $LiteralPath -Raw -ErrorAction Stop | ConvertFrom-Json
    }
    catch {
        throw "Manifest is missing or corrupt: $($_.Exception.Message)"
    }
    if ($manifest.schemaVersion -ne $script:PfiManifestSchema -or
        [string]::IsNullOrWhiteSpace([string]$manifest.productVersion) -or
        $null -eq $manifest.entries) {
        throw 'Manifest schema or required fields are invalid.'
    }
    return $manifest
}

function Assert-PfiPathWithinRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$CandidatePath,
        [Parameter(Mandatory = $true)][string]$AllowedRoot,
        [switch]$AllowRoot
    )

    $root = [IO.Path]::GetFullPath($AllowedRoot).TrimEnd('\', '/')
    $candidate = [IO.Path]::GetFullPath($CandidatePath).TrimEnd('\', '/')
    if ($candidate.Equals($root, [StringComparison]::OrdinalIgnoreCase)) {
        if ($AllowRoot) { return $candidate }
        throw 'The allowed root itself is not a permitted cleanup target.'
    }
    $prefix = $root + [IO.Path]::DirectorySeparatorChar
    if (-not $candidate.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside the allowed root: $candidate"
    }
    return $candidate
}

function Assert-PfiRegistryPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RegistryPath,
        [Parameter(Mandatory = $true)][string]$OwnedRoot,
        [switch]$AllowRoot
    )

    $root = $OwnedRoot.TrimEnd('\')
    $candidate = $RegistryPath.TrimEnd('\')
    if ($candidate.Equals($root, [StringComparison]::OrdinalIgnoreCase)) {
        if ($AllowRoot) { return $candidate }
        throw 'The owned registry root itself requires explicit permission.'
    }
    if (-not $candidate.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Registry path is outside the tool-owned HKCU subtree.'
    }
    return $candidate
}

function Assert-PfiSingleTarget {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string[]]$TargetPath)

    if ($TargetPath.Count -ne 1 -or [string]::IsNullOrWhiteSpace($TargetPath[0])) {
        throw 'Exactly one folder must be selected.'
    }
    if (-not (Test-Path -LiteralPath $TargetPath[0] -PathType Container)) {
        throw 'The selected target is missing or is not a directory.'
    }
    $resolved = (Resolve-Path -LiteralPath $TargetPath[0]).ProviderPath
    $root = [IO.Path]::GetPathRoot($resolved).TrimEnd('\')
    if ($resolved.TrimEnd('\').Equals($root, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Filesystem roots cannot be customized.'
    }
    return $resolved
}

function Set-PfiDesktopIniIconContent {
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$Content,
        [Parameter(Mandatory = $true)][string]$IconResource
    )

    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($line in [regex]::Split([string]$Content, '\r\n|\n|\r')) { $lines.Add($line) }
    while ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -eq '') { $lines.RemoveAt($lines.Count - 1) }
    $sectionStart = -1
    $sectionEnd = $lines.Count
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index].Trim() -ieq '[.ShellClassInfo]') {
            $sectionStart = $index
            for ($next = $index + 1; $next -lt $lines.Count; $next++) {
                if ($lines[$next].Trim() -match '^\[.+\]$') { $sectionEnd = $next; break }
            }
            break
        }
    }
    if ($sectionStart -lt 0) {
        if ($lines.Count -gt 0) { $lines.Insert(0, '') }
        $lines.Insert(0, 'IconResource=' + $IconResource)
        $lines.Insert(0, '[.ShellClassInfo]')
    }
    else {
        for ($index = $sectionEnd - 1; $index -gt $sectionStart; $index--) {
            if ($lines[$index] -match '^\s*(IconResource|IconFile|IconIndex)\s*=') {
                $lines.RemoveAt($index)
            }
        }
        $lines.Insert($sectionStart + 1, 'IconResource=' + $IconResource)
    }
    return (($lines -join "`r`n") + "`r`n")
}

function Reset-PfiDesktopIniIconContent {
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Content)

    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($line in [regex]::Split([string]$Content, '\r\n|\n|\r')) { $lines.Add($line) }
    while ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -eq '') { $lines.RemoveAt($lines.Count - 1) }
    $sectionStart = -1
    $sectionEnd = $lines.Count
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index].Trim() -ieq '[.ShellClassInfo]') {
            $sectionStart = $index
            for ($next = $index + 1; $next -lt $lines.Count; $next++) {
                if ($lines[$next].Trim() -match '^\[.+\]$') { $sectionEnd = $next; break }
            }
            break
        }
    }
    if ($sectionStart -ge 0) {
        for ($index = $sectionEnd - 1; $index -gt $sectionStart; $index--) {
            if ($lines[$index] -match '^\s*(IconResource|IconFile|IconIndex)\s*=') {
                $lines.RemoveAt($index)
            }
        }
        $nextSection = $lines.Count
        for ($index = $sectionStart + 1; $index -lt $lines.Count; $index++) {
            if ($lines[$index].Trim() -match '^\[.+\]$') { $nextSection = $index; break }
        }
        $meaningful = @()
        if ($nextSection -gt ($sectionStart + 1)) {
            $meaningful = @($lines[($sectionStart + 1)..($nextSection - 1)] |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        }
        if ($meaningful.Count -eq 0) {
            $removeCount = $nextSection - $sectionStart
            $lines.RemoveRange($sectionStart, $removeCount)
        }
    }
    while ($lines.Count -gt 0 -and [string]::IsNullOrWhiteSpace($lines[0])) { $lines.RemoveAt(0) }
    while ($lines.Count -gt 0 -and [string]::IsNullOrWhiteSpace($lines[$lines.Count - 1])) {
        $lines.RemoveAt($lines.Count - 1)
    }
    if ($lines.Count -eq 0) { return '' }
    return (($lines -join "`r`n") + "`r`n")
}

function Get-PfiDesktopIniIconResourcePath {
    <#
        Returns the file path currently referenced by IconResource, without the
        trailing ',<index>', or '' when there is none.

        Apply needs this to know which generated resource Explorer may still be
        rendering from, so that resource can be retained rather than deleted.
    #>
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Content)

    foreach ($line in [regex]::Split([string]$Content, '\r\n|\n|\r')) {
        if ($line -match '^\s*IconResource\s*=\s*(.+?)\s*$') {
            $value = $matches[1]
            # Strip the icon index, but not a drive colon (for example 'C:\x.ico,0').
            $separator = $value.LastIndexOf(',')
            if ($separator -gt 0) { $value = $value.Substring(0, $separator) }
            return $value.Trim()
        }
    }
    return ''
}
