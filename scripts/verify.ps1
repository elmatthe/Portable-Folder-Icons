[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$script:Failures = New-Object System.Collections.Generic.List[string]
$repoRoot = Split-Path -Parent $PSScriptRoot

function Add-CheckFailure {
    param([Parameter(Mandatory = $true)][string]$Message)
    $script:Failures.Add($Message)
    Write-Host ("  [FAIL] {0}" -f $Message) -ForegroundColor Red
}

function Add-CheckPass {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host ("  [PASS] {0}" -f $Message) -ForegroundColor Green
}

Write-Host 'Portable Folder Icons verification'
Write-Host ('Repository: {0}' -f $repoRoot)

$testScript = Join-Path $repoRoot 'files\tests\Invoke-Tests.ps1'
if (Test-Path -LiteralPath $testScript -PathType Leaf) {
    & (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') `
        -NoLogo -NoProfile -ExecutionPolicy Bypass -File $testScript
    if ($LASTEXITCODE -eq 0) {
        Add-CheckPass 'deterministic PowerShell tests'
    }
    else {
        Add-CheckFailure ("test suite exited with code {0}" -f $LASTEXITCODE)
    }
}
else {
    Add-CheckFailure 'missing files\tests\Invoke-Tests.ps1'
}

$required = @(
    '.gitattributes',
    '.gitignore',
    'LICENSE',
    'README.md',
    'config.toml',
    'Setup_and_Run-Portable-Folder-Icons.bat',
    'Setup_and_Run-Portable-Folder-Icons.command',
    'md-instructions\Briefing.md',
    'md-instructions\Changelog.md',
    'md-instructions\Decisions.md',
    'md-instructions\Handoff.md',
    'scripts\verify.ps1'
    'scripts\Windows\PortableFolderIcons.Core.ps1'
)
foreach ($relativePath in $required) {
    if (Test-Path -LiteralPath (Join-Path $repoRoot $relativePath) -PathType Leaf) {
        Add-CheckPass ("required file: {0}" -f $relativePath)
    }
    else {
        Add-CheckFailure ("missing required file: {0}" -f $relativePath)
    }
}

$powershellFiles = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'scripts') -Filter '*.ps1' -File -Recurse)
$parseErrors = @()
foreach ($file in $powershellFiles) {
    $tokens = $null
    $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile(
        $file.FullName,
        [ref]$tokens,
        [ref]$errors
    )
    foreach ($error in @($errors)) {
        $parseErrors += ('{0}: {1}' -f $file.FullName, $error.Message)
    }
}
if ($parseErrors.Count -eq 0) {
    Add-CheckPass ("PowerShell parse: {0} script(s)" -f $powershellFiles.Count)
}
else {
    foreach ($parseError in $parseErrors) {
        Add-CheckFailure $parseError
    }
}

Add-Type -AssemblyName System.Drawing
$iconFiles = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'files\ICO-FIles') -Filter '*.ico' -File)
foreach ($iconFile in $iconFiles) {
    $stream = $null
    $icon = $null
    try {
        $stream = [IO.File]::Open(
            $iconFile.FullName,
            [IO.FileMode]::Open,
            [IO.FileAccess]::Read,
            [IO.FileShare]::Read
        )
        $icon = New-Object Drawing.Icon($stream)
        Add-CheckPass ("ICO validates: {0}" -f $iconFile.Name)
    }
    catch {
        Add-CheckFailure ("ICO invalid: {0} ({1})" -f $iconFile.Name, $_.Exception.Message)
    }
    finally {
        if ($null -ne $icon) { $icon.Dispose() }
        if ($null -ne $stream) { $stream.Dispose() }
    }
}

$changelog = Get-Content -LiteralPath (Join-Path $repoRoot 'md-instructions\Changelog.md') -Raw
if ($changelog -match '(?m)^## v0\.1\.0\b') {
    Add-CheckPass 'v0.1.0 changelog entry'
}
else {
    Add-CheckFailure 'missing v0.1.0 changelog entry'
}

if ($script:Failures.Count -gt 0) {
    Write-Host ('RESULT: FAIL ({0} failure(s))' -f $script:Failures.Count) -ForegroundColor Red
    exit 1
}

Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
