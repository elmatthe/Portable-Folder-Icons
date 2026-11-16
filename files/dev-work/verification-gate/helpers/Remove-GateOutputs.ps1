# Housekeeping for the gate's ignored outputs folder (files\dev-work\verification-gate\outputs): removes disposable
# run evidence once its results are recorded durably. Policy: AGENTS.md "Repository development artifact
# housekeeping"; rules: GATE.md "Output retention".
#
# Dry run by default; -Apply deletes. Scope: immediate child DIRECTORIES of the outputs folder only. Never removed:
#   - loose files (for example the runner's status index verify-state.json);
#   - a folder containing RETAIN.md (retained evidence: the file states why and when it can go);
#   - a run folder without summary.md whose newest write is under 60 minutes old (possibly still running);
#   - anything that is, or contains, a junction or symbolic link (links are never followed);
#   - anything outside this repository's outputs folder.
# Exit: 0 done (refusals are reported, not errors), 1 a deletion failed, 2 refused input (nothing deleted).
[CmdletBinding()]
param(
    # Delete the candidates. Without it, only report what would be removed.
    [switch]$Apply,
    # Limit the cleanup to these immediate child folder names.
    [string[]]$Name,
    # Test seam: a gate outputs folder inside this repository's outputs folder (used by check c-0008).
    [string]$OutputsRoot
)

$ErrorActionPreference = 'Stop'
$gateRoot = Split-Path -Parent $PSScriptRoot
$defaultRoot = [IO.Path]::GetFullPath((Join-Path $gateRoot 'outputs')).TrimEnd('\')
$repoRoot = [IO.Path]::GetFullPath((Join-Path $gateRoot '..\..\..')).TrimEnd('\')
$runPattern = '^\d{8}T\d{6}Z-[0-9a-f]{6}$'

function Stop-Refused([string]$Reason) {
    Write-Host ("REFUSED: {0}" -f $Reason)
    Write-Host 'Nothing was deleted.'
    exit 2
}

function Test-IsLink($Item) { return (($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) }

function Get-TreeInfo([IO.DirectoryInfo]$Directory) {
    # Walks the tree without following links: size, number of links found, newest write time.
    $bytes = [int64]0
    $links = 0
    $newest = $Directory.LastWriteTimeUtc
    $stack = New-Object 'Collections.Generic.Stack[IO.DirectoryInfo]'
    $stack.Push($Directory)
    while ($stack.Count -gt 0) {
        foreach ($entry in $stack.Pop().EnumerateFileSystemInfos()) {
            if ($entry.LastWriteTimeUtc -gt $newest) { $newest = $entry.LastWriteTimeUtc }
            if (Test-IsLink $entry) { $links++; continue }
            if ($entry -is [IO.DirectoryInfo]) { $stack.Push($entry) } else { $bytes += $entry.Length }
        }
    }
    return [pscustomobject]@{ Bytes = $bytes; Links = $links; Newest = $newest }
}

function Clear-ReadOnly([IO.DirectoryInfo]$Directory) {
    # Fixtures set ReadOnly on folders and desktop.ini; the recursive delete would otherwise fail on them.
    $stack = New-Object 'Collections.Generic.Stack[IO.DirectoryInfo]'
    $stack.Push($Directory)
    while ($stack.Count -gt 0) {
        $current = $stack.Pop()
        if (($current.Attributes -band [IO.FileAttributes]::ReadOnly) -ne 0) { $current.Attributes = $current.Attributes -band (-bnot [IO.FileAttributes]::ReadOnly) }
        foreach ($entry in $current.EnumerateFileSystemInfos()) {
            if (Test-IsLink $entry) { throw "link found during deletion: $($entry.FullName)" }
            if ($entry -is [IO.DirectoryInfo]) { $stack.Push($entry) }
            elseif (($entry.Attributes -band [IO.FileAttributes]::ReadOnly) -ne 0) { $entry.Attributes = $entry.Attributes -band (-bnot [IO.FileAttributes]::ReadOnly) }
        }
    }
}

# --- The outputs root must be this repository's gate outputs folder (or a test fixture inside it), ignored by Git,
#     and reached without passing through a link.
if ([string]::IsNullOrWhiteSpace($OutputsRoot)) { $OutputsRoot = $defaultRoot }
$root = [IO.Path]::GetFullPath($OutputsRoot).TrimEnd('\')
if (-not $root.EndsWith('\files\dev-work\verification-gate\outputs', [StringComparison]::OrdinalIgnoreCase)) {
    Stop-Refused "not a gate outputs folder: $root"
}
if (-not ($root -ieq $defaultRoot -or $root.StartsWith($defaultRoot + '\', [StringComparison]::OrdinalIgnoreCase))) {
    Stop-Refused "outside this repository's gate outputs folder ($defaultRoot): $root"
}
if (-not (Test-Path -LiteralPath $root -PathType Container)) {
    if ($root -ieq $defaultRoot) { Write-Host 'Nothing to clean: the outputs folder does not exist.'; exit 0 }
    Stop-Refused "missing: $root"
}
$cursor = $root
while ($cursor.Length -ge $repoRoot.Length) {
    if (Test-IsLink (Get-Item -LiteralPath $cursor -Force)) { Stop-Refused "the path passes through a link: $cursor" }
    if ($cursor -ieq $repoRoot) { break }
    $cursor = Split-Path -Parent $cursor
}
$git = Get-Command git.exe -ErrorAction SilentlyContinue
if ($null -eq $git) { Stop-Refused 'git.exe is required to confirm the folder is ignored (generated) content' }
$probe = $root.Substring($repoRoot.Length + 1).Replace('\', '/') + '/.pfi-ignore-probe'
& $git.Source -C $repoRoot check-ignore -q --no-index -- $probe
if ($LASTEXITCODE -ne 0) { Stop-Refused "not ignored by Git, so not generated output: $root" }

# --- Candidates: immediate child folders, optionally narrowed by -Name.
$children = @((New-Object IO.DirectoryInfo($root)).EnumerateFileSystemInfos())
$folders = @($children | Where-Object { $_ -is [IO.DirectoryInfo] })
# powershell.exe -File passes "-Name a,b" as one string; accept both that and a real array.
$Name = @($Name | Where-Object { $null -ne $_ } | ForEach-Object { ([string]$_).Split(',') } | ForEach-Object { $_.Trim() })
if ($Name.Count -gt 0) {
    foreach ($requested in $Name) {
        if ([string]::IsNullOrWhiteSpace($requested) -or $requested -in @('.', '..') -or $requested -match '[\\/:]' -or
            $requested.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) { Stop-Refused "not a plain folder name: $requested" }
        if (@($folders | Where-Object { $_.Name -ieq $requested }).Count -ne 1) { Stop-Refused "no such folder in outputs: $requested" }
    }
    $folders = @($folders | Where-Object { $Name -icontains $_.Name })
}

Write-Host ("Gate outputs: {0}" -f $root)
if (-not $Apply) { Write-Host 'DRY RUN: nothing will be deleted. Re-run with -Apply to delete.' }
$removedBytes = [int64]0
$removedCount = 0
$failures = 0
foreach ($folder in @($folders | Sort-Object Name)) {
    if (Test-IsLink $folder) { Write-Host ("  {0,-13} {1}  (is a link; never followed)" -f 'refused', $folder.Name); continue }
    $retain = Join-Path $folder.FullName 'RETAIN.md'
    if (Test-Path -LiteralPath $retain -PathType Leaf) {
        $why = @(Get-Content -LiteralPath $retain -TotalCount 3 | Where-Object { $_.Trim() }) -join ' '
        Write-Host ("  {0,-13} {1}  ({2})" -f 'retained', $folder.Name, $why)
        continue
    }
    $info = Get-TreeInfo $folder
    $kb = [Math]::Round($info.Bytes / 1KB)
    if ($info.Links -gt 0) { Write-Host ("  {0,-13} {1}  ({2} KB; contains {3} link(s); clean it by hand)" -f 'refused', $folder.Name, $kb, $info.Links); continue }
    $incomplete = $folder.Name -match $runPattern -and -not (Test-Path -LiteralPath (Join-Path $folder.FullName 'summary.md') -PathType Leaf)
    if ($incomplete -and $info.Newest -gt [DateTime]::UtcNow.AddMinutes(-60)) {
        Write-Host ("  {0,-13} {1}  ({2} KB; incomplete run written in the last hour, possibly active)" -f 'skipped', $folder.Name, $kb)
        continue
    }
    $reason = if ($incomplete) { 'interrupted run' } elseif ($folder.Name -match $runPattern) { 'completed run' } else { 'unretained evidence' }
    if (-not $Apply) { Write-Host ("  {0,-13} {1}  ({2} KB; {3})" -f 'would remove', $folder.Name, $kb, $reason); $removedBytes += $info.Bytes; $removedCount++; continue }
    try {
        if (-not ([IO.Path]::GetFullPath($folder.Parent.FullName).TrimEnd('\') -ieq $root)) { throw 'parent is not the outputs folder' }
        Clear-ReadOnly $folder
        [IO.Directory]::Delete($folder.FullName, $true)
        Write-Host ("  {0,-13} {1}  ({2} KB; {3})" -f 'removed', $folder.Name, $kb, $reason)
        $removedBytes += $info.Bytes
        $removedCount++
    }
    catch {
        $failures++
        Write-Host ("  {0,-13} {1}  ({2})" -f 'FAILED', $folder.Name, $_.Exception.Message)
    }
}
foreach ($file in @($children | Where-Object { $_ -isnot [IO.DirectoryInfo] } | Sort-Object Name)) {
    Write-Host ("  {0,-13} {1}  (loose file; never removed by this helper)" -f 'kept', $file.Name)
}
Write-Host ("{0}: {1} folder(s), {2:N1} MB" -f $(if ($Apply) { 'Removed' } else { 'Would remove' }), $removedCount, ($removedBytes / 1MB))
if ($failures -gt 0) { Write-Host ("{0} deletion(s) failed; see above." -f $failures); exit 1 }
exit 0
