# Gate check c-0005: the public distribution ships exactly the ten approved colour ICOs, and no personal ICO
# is tracked or staged. Untracked personal ICOs are reported, not failed: they are valid local imports.
# Exit: 0 PASS, 1 FAIL, 2 BLOCKED (Git unavailable).
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\..'))
$git = Get-Command git.exe -ErrorAction SilentlyContinue
if ($null -eq $git) { Write-Host 'BLOCKED: git.exe is required'; exit 2 }
$approved = @('Black', 'Blue', 'Gray', 'Green', 'Orange', 'Pink', 'Purple', 'Red', 'Teal', 'Yellow') |
    ForEach-Object { "files/ICO-Files/Folder_$_.ico" }
$tracked = @(& $git.Source -C $repoRoot ls-files -- 'files/ICO-Files' | Where-Object { $_ -match '(?i)\.ico$' })
$staged = @(& $git.Source -C $repoRoot diff --cached --name-only | Where-Object { $_ -match '(?i)\.ico$' })
$untracked = @(& $git.Source -C $repoRoot ls-files -o --exclude-standard -- 'files' | Where-Object { $_ -match '(?i)\.ico$' })
$failed = $false
$extraTracked = @($tracked | Where-Object { $_ -cnotin $approved })
$missing = @($approved | Where-Object { $_ -cnotin $tracked })
if ($extraTracked.Count -or $missing.Count) { $failed = $true; Write-Host ("  [FAIL] tracked public ICOs differ: extra <{0}> missing <{1}>" -f ($extraTracked -join ', '), ($missing -join ', ')) }
else { Write-Host '  [PASS] tracked files/ICO-Files contains exactly the ten approved colour ICOs' }
$stagedPersonal = @($staged | Where-Object { $_ -cnotin $approved })
if ($stagedPersonal.Count) { $failed = $true; Write-Host ("  [FAIL] personal ICOs are staged for commit: {0}" -f ($stagedPersonal -join ', ')) }
else { Write-Host '  [PASS] no personal ICO is staged' }
Write-Host ("  [INFO] untracked local ICOs (preserved, never staged by tooling): {0}" -f $untracked.Count)
foreach ($u in $untracked) { Write-Host "         $u" }
if ($failed) { exit 1 }
exit 0
