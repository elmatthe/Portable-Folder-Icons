[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$InstallRoot,
    [Parameter(Mandatory = $true)][int]$ParentProcessId,
    [switch]$PurgeCache
)

$ErrorActionPreference = 'SilentlyContinue'
$root = [IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
$expected = [IO.Path]::GetFullPath(
    (Join-Path $env:LOCALAPPDATA 'Portable-Folder-Icons')
).TrimEnd('\')
if (-not $root.Equals($expected, [StringComparison]::OrdinalIgnoreCase)) { exit 40 }

for ($attempt = 0; $attempt -lt 100; $attempt++) {
    if ($null -eq (Get-Process -Id $ParentProcessId -ErrorAction SilentlyContinue)) { break }
    Start-Sleep -Milliseconds 100
}
if ($null -ne (Get-Process -Id $ParentProcessId -ErrorAction SilentlyContinue)) { exit 41 }

foreach ($relativePath in @('runtime', 'manifest.json')) {
    $target = Join-Path $root $relativePath
    if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
}
if ($PurgeCache) {
    $icons = Join-Path $root 'icons'
    if (Test-Path -LiteralPath $icons) { Remove-Item -LiteralPath $icons -Recurse -Force }
}
$self = $MyInvocation.MyCommand.Path
if (Test-Path -LiteralPath $self) { Remove-Item -LiteralPath $self -Force }
exit 0
