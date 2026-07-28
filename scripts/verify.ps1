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
    'scripts\Windows\Cleanup-PortableFolderIcons.ps1'
    'scripts\Windows\Install-PortableFolderIcons.ps1'
    'scripts\Windows\Invoke-PortableFolderIcons.ps1'
    'scripts\Windows\PortableFolderIcons.Actions.ps1'
    'scripts\Windows\PortableFolderIcons.Core.ps1'
    'scripts\Windows\PortableFolderIcons.Integration.ps1'
    'scripts\Windows\PortableFolderIcons.Maintenance.ps1'
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
$iconDirectory = Get-ChildItem -LiteralPath (Join-Path $repoRoot 'files') -Directory |
    Where-Object { $_.Name -ceq 'ICO-Files' } |
    Select-Object -First 1
if ($null -eq $iconDirectory) {
    Add-CheckFailure 'icon source directory must use exact spelling files\ICO-Files'
    $iconFiles = @()
}
else {
    Add-CheckPass 'exact icon source directory spelling: files\ICO-Files'
    $iconFiles = @(Get-ChildItem -LiteralPath $iconDirectory.FullName -Filter '*.ico' -File)
}
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

$allowedRootNames = @(
    '.agents', '.claude', '.codex', '.git', '.vscode',
    'files', 'md-instructions', 'scripts',
    '.gitattributes', '.gitignore', 'AI-WORKSPACE.md', 'LICENSE', 'README.md',
    'config.toml', 'Map-Repo-Structure.bat',
    'Setup_and_Run-Portable-Folder-Icons.bat',
    'Setup_and_Run-Portable-Folder-Icons.command'
)
$unexpectedRoot = @(Get-ChildItem -LiteralPath $repoRoot -Force | Where-Object {
    $_.Name -notin $allowedRootNames
})
if ($unexpectedRoot.Count -eq 0) {
    Add-CheckPass 'clean allowed root layout'
}
else {
    Add-CheckFailure ('forbidden root item(s): {0}' -f (($unexpectedRoot.Name | Sort-Object) -join ', '))
}

$shippedFiles = @(
    Get-ChildItem -LiteralPath (Join-Path $repoRoot 'scripts\Windows') -Filter '*.ps1' -File
)
$shippedFiles += Get-Item -LiteralPath (Join-Path $repoRoot 'Setup_and_Run-Portable-Folder-Icons.bat')
$shippedText = ($shippedFiles | ForEach-Object {
    Get-Content -LiteralPath $_.FullName -Raw
}) -join "`n"
$batchText = Get-Content -LiteralPath (Join-Path $repoRoot 'Setup_and_Run-Portable-Folder-Icons.bat') -Raw
if ($batchText -match '(?im)^\s*echo[^\r\n]*(%CD%|%INSTALLER%)') {
    Add-CheckFailure 'batch echoes an untrusted dynamic path through cmd parsing'
}
else {
    Add-CheckPass 'batch does not echo untrusted dynamic paths'
}
$forbiddenPatterns = [ordered]@{
    'hardcoded user checkout path' = 'C:\\Users\\ematthew'
    'HKLM registry write/reference' = '(?i)\bHKLM(?::|\\)'
    'Explorer process termination/restart' = '(?i)(Stop-Process|taskkill|TerminateProcess).{0,80}explorer'
    'Python/pip/venv setup' = '(?i)(python(?:\.exe)?\s+-m|\bpip(?:\.exe)?\s+install|\bwinget\s+install|\.venv)'
    'network download code' = '(?i)(Invoke-WebRequest|Start-BitsTransfer|curl\.exe|wget\.exe|https?://)'
}
foreach ($check in $forbiddenPatterns.GetEnumerator()) {
    if ($shippedText -match $check.Value) {
        Add-CheckFailure $check.Key
    }
    else {
        Add-CheckPass ('no {0}' -f $check.Key)
    }
}

$config = Get-Content -LiteralPath (Join-Path $repoRoot 'config.toml') -Raw
if ($config -match 'version\s*=\s*"0\.1\.0"' -and
    $config -match 'requires_python\s*=\s*false' -and
    $config -match 'windows\s*=\s*true' -and
    $config -match 'macos\s*=\s*false') {
    Add-CheckPass 'config.toml v0.1.0 Windows-only metadata'
}
else {
    Add-CheckFailure 'config.toml metadata is incomplete or inaccurate'
}

$briefing = Get-Content -LiteralPath (Join-Path $repoRoot 'md-instructions\Briefing.md') -Raw
$readme = Get-Content -LiteralPath (Join-Path $repoRoot 'README.md') -Raw
if ($briefing -match 'v0\.1\.0' -and $readme -match 'SmartScreen' -and
    $readme -match 'Uninstall' -and $readme -match 'License and icon rights') {
    Add-CheckPass 'required v0.1.0 documentation'
}
else {
    Add-CheckFailure 'required v0.1.0 documentation is incomplete'
}

if ($PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSVersion.Minor -ge 1) {
    Add-CheckPass ('running under Windows PowerShell {0}' -f $PSVersionTable.PSVersion)
}
else {
    Add-CheckFailure ('verification must run under Windows PowerShell 5.1; actual {0}' -f $PSVersionTable.PSVersion)
}

$git = Get-Command git.exe -ErrorAction SilentlyContinue
if ($null -ne $git) {
    $savedErrorPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $diffCheck = & $git.Source -C $repoRoot diff --check 2>&1
    $diffExit = $LASTEXITCODE
    $ErrorActionPreference = $savedErrorPreference
    if ($diffExit -eq 0) {
        Add-CheckPass 'git diff --check'
    }
    else {
        Add-CheckFailure ('git diff --check: {0}' -f ($diffCheck -join ' '))
    }
}
else {
    Add-CheckFailure 'git.exe is required for the diff whitespace gate'
}

if ($script:Failures.Count -gt 0) {
    Write-Host ('RESULT: FAIL ({0} failure(s))' -f $script:Failures.Count) -ForegroundColor Red
    exit 1
}

Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
