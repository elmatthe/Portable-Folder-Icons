[CmdletBinding()]
param(
    # Passed through to the test suite. The compiled C# harness is launched only with explicit
    # authorization (-AllowNativeHarness, or PFI_GATE_NATIVE_HARNESS=allow); by default it is built
    # or reused but withheld. A withheld or denied launch makes the result BLOCKED, never PASS.
    [switch]$AllowNativeHarness,
    # Withhold the launch even when authorized.
    [switch]$SkipNativeHarness
)

$ErrorActionPreference = 'Stop'
$script:Failures = New-Object System.Collections.Generic.List[string]
$script:Blocked = New-Object System.Collections.Generic.List[string]
$repoRoot = Split-Path -Parent $PSScriptRoot

function Add-CheckBlocked {
    param([Parameter(Mandatory = $true)][string]$Message)
    $script:Blocked.Add($Message)
    Write-Host ("  [BLOCKED] {0}" -f $Message) -ForegroundColor Yellow
}

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
    $testArguments = @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $testScript)
    if ($AllowNativeHarness) { $testArguments += '-AllowNativeHarness' }
    if ($SkipNativeHarness) { $testArguments += '-SkipNativeHarness' }
    & (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') @testArguments
    if ($LASTEXITCODE -eq 0) {
        Add-CheckPass 'deterministic PowerShell tests'
    }
    elseif ($LASTEXITCODE -eq 3) {
        Add-CheckBlocked 'test suite: no assertion failed, but the compiled C# harness was not executed (BLOCKED_BY_ENDPOINT_SECURITY; see suite output)'
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
    'files\readme-assets\colored-folders-example.png',
    'files\readme-assets\folder-color-gallery.png',
    'files\readme-assets\folder-icons-submenu.png',
    'Setup_and_Run-Portable-Folder-Icons.bat',
    'Setup_and_Run-Portable-Folder-Icons.command',
    'md-instructions\Briefing.md',
    'md-instructions\Changelog.md',
    'md-instructions\Decisions.md',
    'md-instructions\Handoff.md',
    'AGENTS.md',
    'scripts\verify.ps1'
    'scripts\Windows\Cleanup-PortableFolderIcons.ps1'
    'scripts\Windows\Install-PortableFolderIcons.ps1'
    'scripts\Windows\Invoke-PortableFolderIcons.Hidden.vbs'
    'scripts\Windows\Invoke-PortableFolderIcons.ps1'
    'scripts\Windows\PortableFolderIcons.Actions.ps1'
    'scripts\Windows\PortableFolderIcons.Core.ps1'
    'scripts\Windows\PortableFolderIcons.Integration.ps1'
    'scripts\Windows\PortableFolderIcons.Maintenance.ps1'
    'scripts\Windows\PortableFolderIcons.Selection.ps1'
    'scripts\Windows\SelectionHandler\Build-SelectionBroker.ps1'
    'scripts\Windows\SelectionHandler\PortableFolderIcons.SelectionBroker.cs'
    'scripts\Windows\SelectionHandler\PortableFolderIcons.SelectionBroker.x64.exe'
    'scripts\Windows\SelectionHandler\PortableFolderIcons.SelectionBroker.x86.exe'
    'scripts\Windows\SelectionHandler\SelectionBroker.build.json'
    'files\tests\SelectionBrokerHarness.cs'
    'files\tests\Invoke-SelectionBrokerTests.ps1'
    'files\tests\Invoke-InstalledSelectionBrokerTests.ps1'
)
foreach ($relativePath in $required) {
    if (Test-Path -LiteralPath (Join-Path $repoRoot $relativePath) -PathType Leaf) {
        Add-CheckPass ("required file: {0}" -f $relativePath)
    }
    else {
        Add-CheckFailure ("missing required file: {0}" -f $relativePath)
    }
}

# Validate both distribution artifacts even when tests run in one architecture.
try {
    . (Join-Path $repoRoot 'scripts\Windows\PortableFolderIcons.Core.ps1')
    $brokerSourceRoot = Join-Path $repoRoot 'scripts\Windows\SelectionHandler'
    $brokerBuild = Read-PfiSelectionBrokerBuildManifest `
        (Join-Path $brokerSourceRoot 'SelectionBroker.build.json') `
        (Join-Path $brokerSourceRoot 'PortableFolderIcons.SelectionBroker.cs')
    foreach ($brokerPlatform in @('x64', 'x86')) {
        [void](Test-PfiSelectionBrokerArtifact `
            (Join-Path $brokerSourceRoot ('PortableFolderIcons.SelectionBroker.' + $brokerPlatform + '.exe')) `
            $brokerBuild $brokerPlatform)
        Add-CheckPass ("selection broker source/build/PE/assembly identity: {0}" -f $brokerPlatform)
    }
}
catch { Add-CheckFailure ("selection broker identity: {0}" -f $_.Exception.Message) }

# Setup checks the broker source's SHA-256 against the build manifest, which records the LF bytes. Without a fixed
# eol, a fresh clone with core.autocrlf=true checks the source out as CRLF and setup rejects the broker.
$gitAttributes = Get-Command git.exe -ErrorAction SilentlyContinue
if ($null -ne $gitAttributes) {
    $eolAttribute = @(& $gitAttributes.Source -C $repoRoot check-attr eol -- 'scripts/Windows/SelectionHandler/PortableFolderIcons.SelectionBroker.cs')
    if (($eolAttribute -join '') -match ':\s*eol:\s*lf\s*$') { Add-CheckPass 'broker source is checked out with LF line endings (eol=lf), matching its build manifest' }
    else { Add-CheckFailure 'broker source needs eol=lf in .gitattributes so fresh checkouts match its build manifest' }
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
if ($changelog -match '(?m)^## v0\.1\.1\b') {
    Add-CheckPass 'v0.1.1 changelog entry'
}
else {
    Add-CheckFailure 'missing v0.1.1 changelog entry'
}

$allowedRootNames = @(
    '.agents', '.ai', '.claude', '.codex', '.git', '.vscode',
    'files', 'md-instructions', 'scripts',
    '.gitattributes', '.gitignore', 'AGENTS.md', 'AI-WORKSPACE.md', 'LICENSE', 'README.md',
    'config.toml', 'Map-Repo-Structure.bat',
    'Setup_and_Run-Portable-Folder-Icons.bat',
    'Setup_and_Run-Portable-Folder-Icons.command'
)
# Exact local developer artifacts, not additions to the shipped root contract.
$developerRootFiles = @('REPO-STRUCTURE.md')
$unexpectedRoot = @(Get-ChildItem -LiteralPath $repoRoot -Force | Where-Object {
    $_.Name -notin $allowedRootNames -and
    -not (-not $_.PSIsContainer -and $_.Name -in $developerRootFiles)
})
if ($unexpectedRoot.Count -eq 0) {
    Add-CheckPass 'clean allowed root layout'
}
else {
    Add-CheckFailure ('forbidden root item(s): {0}' -f (($unexpectedRoot.Name | Sort-Object) -join ', '))
}

# Workspace guidance and the generated map must stay local and ignored.
$gitLayout = Get-Command git.exe -ErrorAction SilentlyContinue
if ($null -ne $gitLayout) {
    $trackedDeveloperFiles = @(& $gitLayout.Source -C $repoRoot ls-files -- .ai REPO-STRUCTURE.md)
    $unignoredDeveloperFiles = @()
    foreach ($localItem in @('.ai', 'REPO-STRUCTURE.md')) {
        if (Test-Path -LiteralPath (Join-Path $repoRoot $localItem)) {
            & $gitLayout.Source -C $repoRoot check-ignore -q -- $localItem
            if ($LASTEXITCODE -ne 0) { $unignoredDeveloperFiles += $localItem }
        }
    }
    if ($trackedDeveloperFiles.Count -eq 0 -and $unignoredDeveloperFiles.Count -eq 0) {
        Add-CheckPass 'workspace .ai and generated REPO-STRUCTURE.md are ignored and untracked'
    }
    else {
        Add-CheckFailure 'developer workspace guidance/map must be ignored and excluded from tracked shipping files'
    }
}

$shippedFiles = @(
    Get-ChildItem -LiteralPath (Join-Path $repoRoot 'scripts\Windows') -Filter '*.ps1' -File
)
$shippedFiles += Get-Item -LiteralPath (
    Join-Path $repoRoot 'scripts\Windows\SelectionHandler\PortableFolderIcons.SelectionBroker.cs'
)
$shippedFiles += Get-Item -LiteralPath (
    Join-Path $repoRoot 'scripts\Windows\Invoke-PortableFolderIcons.Hidden.vbs'
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
if ($config -match 'version\s*=\s*"0\.1\.1"' -and
    $config -match '(?m)^single_selection\s*=\s*false\s*$' -and
    $config -match '(?m)^multi_selection\s*=\s*true\s*$' -and
    $config -match '(?ms)^\[settings\]\s*.*?^developer_mode\s*=\s*false\s*(?:#.*)?$' -and
    $config -match 'requires_python\s*=\s*false' -and
    $config -match 'windows\s*=\s*true' -and
    $config -match 'macos\s*=\s*false') {
    Add-CheckPass 'config.toml v0.1.1 Windows-only metadata'
}
else {
    Add-CheckFailure 'config.toml metadata is incomplete or inaccurate'
}

$briefing = Get-Content -LiteralPath (Join-Path $repoRoot 'md-instructions\Briefing.md') -Raw
$readme = Get-Content -LiteralPath (Join-Path $repoRoot 'README.md') -Raw
if ($briefing -match 'v0\.1\.1' -and $readme -match 'SmartScreen' -and
    $readme -match 'Uninstall' -and $readme -match 'License and icon rights') {
    Add-CheckPass 'required v0.1.1 documentation'
}
else {
    Add-CheckFailure 'required v0.1.1 documentation is incomplete'
}

$agentsPath = Join-Path $repoRoot 'AGENTS.md'
$agentsText = if (Test-Path -LiteralPath $agentsPath -PathType Leaf) { Get-Content -LiteralPath $agentsPath -Raw } else { '' }
if ($agentsText -match '(?m)^### Repository development artifact housekeeping' -and
    $agentsText -match 'files/dev-work/verification-gate/outputs/' -and $agentsText -match 'RETAIN\.md' -and
    $agentsText -match 'Remove-GateOutputs\.ps1') {
    Add-CheckPass 'AGENTS.md documents development-artifact housekeeping'
}
else {
    Add-CheckFailure 'AGENTS.md must document development-artifact housekeeping (outputs retention, RETAIN.md, Remove-GateOutputs.ps1)'
}

$imageLinks = @([regex]::Matches($readme, '!\[[^\]]*\]\((files/readme-assets/[^)]+)\)') |
    ForEach-Object { $_.Groups[1].Value })
if ($imageLinks.Count -eq 3) {
    $invalidImageLinks = @()
    foreach ($relativeLink in $imageLinks) {
        $segments = $relativeLink -split '/'
        $cursor = $repoRoot
        foreach ($segment in $segments) {
            $exact = @(Get-ChildItem -LiteralPath $cursor -Force | Where-Object Name -ceq $segment)
            if ($exact.Count -ne 1) {
                $invalidImageLinks += $relativeLink
                break
            }
            $cursor = $exact[0].FullName
        }
    }
    if ($invalidImageLinks.Count -eq 0) {
        Add-CheckPass 'README image links resolve with exact committed filename casing'
    }
    else {
        Add-CheckFailure ('README image link casing/path failure: {0}' -f ($invalidImageLinks -join ', '))
    }
}
else {
    Add-CheckFailure ('README must reference exactly three release images; found {0}' -f $imageLinks.Count)
}
if ($readme -match 'Press F5, navigate away and back, or open a new Explorer window/view' -and
    $readme -match 'Reset normally updates immediately' -and
    $readme -notmatch '(?i)(always|guarantee)[^\r\n]{0,50}(immediate|repaint)') {
    Add-CheckPass 'README states the accepted Explorer refresh limitation'
}
else {
    Add-CheckFailure 'README refresh limitation is missing or overpromises repaint behavior'
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
    Write-Host ('RESULT: FAIL ({0} failure(s), {1} blocked)' -f $script:Failures.Count, $script:Blocked.Count) -ForegroundColor Red
    exit 1
}
if ($script:Blocked.Count -gt 0) {
    # A blocked check is never a pass: exit 2 matches the verification gate's BLOCKED code.
    Write-Host ('RESULT: BLOCKED ({0} check(s) could not be executed)' -f $script:Blocked.Count) -ForegroundColor Yellow
    exit 2
}

Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
