[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$source = Join-Path $PSScriptRoot 'PortableFolderIcons.SelectionBroker.cs'
$compiler = Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) {
    throw 'The developer build requires the inbox .NET Framework 4.x C# compiler on 64-bit Windows.'
}
if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
    throw 'Selection broker source is missing.'
}

$sourceHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
$artifacts = New-Object System.Collections.Generic.List[object]
$outputs = @(
    @{ Platform = 'x64'; Name = 'PortableFolderIcons.SelectionBroker.x64.exe' },
    @{ Platform = 'x86'; Name = 'PortableFolderIcons.SelectionBroker.x86.exe' }
)
foreach ($output in $outputs) {
    $destination = Join-Path $PSScriptRoot $output.Name
    & $compiler /nologo /optimize+ /target:winexe `
        ('/platform:' + $output.Platform) `
        /reference:System.Runtime.Serialization.dll `
        ('/out:' + $destination) $source
    if ($LASTEXITCODE -ne 0) {
        throw "The $($output.Platform) selection broker build failed."
    }
    $hash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
    $artifacts.Add([ordered]@{
        platform = $output.Platform
        filename = $output.Name
        sha256 = $hash
    })
    Write-Host ("{0}  {1}" -f $hash, $output.Name)
}
$manifest = [ordered]@{
    schemaVersion = 1
    sourceFilename = 'PortableFolderIcons.SelectionBroker.cs'
    sourceSha256 = $sourceHash
    compiler = [Diagnostics.FileVersionInfo]::GetVersionInfo($compiler).FileVersion
    artifacts = $artifacts.ToArray()
}
$manifestPath = Join-Path $PSScriptRoot 'SelectionBroker.build.json'
[IO.File]::WriteAllText(
    $manifestPath,
    (($manifest | ConvertTo-Json -Depth 5) + "`r`n"),
    (New-Object Text.UTF8Encoding($false))
)
Write-Host ("{0}  {1}" -f $sourceHash, $manifest.sourceFilename)
