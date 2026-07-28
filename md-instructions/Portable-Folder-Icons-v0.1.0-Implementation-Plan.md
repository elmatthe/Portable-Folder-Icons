# Portable Folder Icons v0.1.0 — Implementation Plan

## Status and purpose

This is a temporary implementation drop for the local
`elmatthe/Portable-Folder-Icons` checkout. Read it completely before changing
anything. Implement and verify the plan on a working branch. Delete this file
only after the entire plan is complete, manually approved, and ready to merge.

The public GitHub repository was confirmed empty on 2026-07-28. The local
checkout is therefore the source of truth for the current scaffold, ICO files,
licence, configuration, and any uncommitted work.

## Product goal

Build a small Windows 10/11, current-user-only tool that lets a non-technical
user:

1. Download or copy the repository anywhere under their Windows user profile.
2. Double-click `Setup_and_Run-Portable-Folder-Icons.bat`.
3. Install or repair a stable runtime under
   `%LOCALAPPDATA%\Portable-Folder-Icons` without administrator rights.
4. Right-click one folder, open **Show more options**, then open the nested
   **Folder Icons** submenu.
5. Select any valid bundled/custom ICO listed there and see the folder icon
   update immediately or as close to immediately as Windows Explorer permits.
6. Add more `.ico` files to the repository-relative `files\ICO-FIles` folder,
   rerun the setup batch, and receive updated menu choices.
7. Reset a folder to its default icon, repair the installed integration, or
   uninstall the tool.

After a successful setup, moving or deleting the repository must not break the
installed context menu or icons already applied to folders. Rerunning setup
from a moved checkout must update the stable runtime correctly.

## Finalized user decisions

1. Use the classic Windows context menu under **Show more options**.
2. Use one nested **Folder Icons** submenu with one entry per valid ICO.
3. Install a stable, self-contained current-user runtime in
   `%LOCALAPPDATA%\Portable-Folder-Icons`.
4. Store applied icons in a content-hashed cache under that runtime so old
   folder customizations remain stable after source files are renamed or
   replaced.
5. Treat `files\ICO-FIles` as the exact repository-relative icon source.
   The user's current example location is:
   `C:\Users\ematthew\Portable-User-Installs\Portable-Folder-Icons\files\ICO-FIles`.
   Never hardcode that absolute path or username.
6. Generate display labels automatically from filenames:
   `Folder_Blue.ico` becomes `Blue`; `Work Projects.ico` remains
   `Work Projects`.
7. Include **Reset to Default**, **Repair**, and **Uninstall**.
8. Version 1 supports exactly one selected folder. Record multi-folder
   application as a future enhancement, not hidden unfinished functionality.
9. Use targeted Explorer notification/refresh. Preserve open Explorer window
   locations and never restart Explorer.
10. Do not use Python, pip, or `.venv`. The setup terminal should explicitly
    report that Python is unnecessary.
11. The user confirms they own or have redistribution permission for the ten
    current ICO files and wants them in the public repository.
12. Direct integration into the first Windows 11 context menu is out of scope.

## Project-specific structure decision

`AI-WORKSPACE.md` normally defines `files/` as development-only. The user has
explicitly selected `files\ICO-FIles` as the distributable installer-source
location for this project. Record this narrow project-specific exception in
`md-instructions/Decisions.md`.

The installed context-menu runtime must never depend on that repository folder:
setup validates and copies accepted icons into the stable `%LOCALAPPDATA%`
cache. A missing or empty source folder must produce a clear result rather than
a crash. Reset, Repair, and Uninstall must remain available where technically
possible even when no assignable icon is present.

Preserve the clean root:

```text
.claude/                              local/ignored if already scaffolded
.codex/                               local/ignored if already scaffolded
.vscode/                              local/ignored if already scaffolded
scripts/
  Windows/                            product PowerShell runtime
  verify.ps1                          one-command verification gate
files/
  ICO-FIles/                          redistributable installer-source ICOs
  tests/                              deterministic PowerShell tests
  test-files/                         generated or safe test fixtures
  test-logs/                          ignored manual QA logs
md-instructions/
  Briefing.md
  Changelog.md
  Decisions.md
  Handoff.md
  Portable-Folder-Icons-v0.1.0-Implementation-Plan.md
README.md
AI-WORKSPACE.md                       follow existing ignore policy
config.toml
.gitignore
.gitattributes
.env                                  only if already required; no secrets needed
LICENSE
Setup_and_Run-Portable-Folder-Icons.bat
Setup_and_Run-Portable-Folder-Icons.command
```

Do not create extra root files. If the `.command` launcher exists, retain it as
a short, friendly “Windows-only project” notice. If the existing scaffold
requires it but it is absent, add that notice rather than pretending macOS is
supported.

## Licence and configuration

- Keep the root `LICENSE`. Do not delete it.
- Inspect it for unfilled template placeholders or terms that do not match the
  intended public release. Do not silently choose a different licence.
- State in `README.md` whether the bundled ICO assets are covered by the root
  licence, but make that claim only if the existing licence and the user's
  confirmed redistribution rights support it.
- Explain that future icons added by individual users remain their
  responsibility and are not automatically granted redistribution rights.
- Keep `config.toml` because `AI-WORKSPACE.md` defines it as the committed
  project metadata/configuration file. Populate accurate Windows-only project
  metadata and version `0.1.0`.
- Do not add a TOML parser merely so runtime code can consume metadata. Runtime
  settings that PowerShell must read may live in a small PowerShell data file
  under `scripts\Windows`, while `config.toml` remains authoritative
  project/agent metadata.

## Required architecture

### 1. Portable installer source

All paths in the repository must be resolved from the launcher location
(`%~dp0` in batch and `$PSScriptRoot` in PowerShell). The setup must work from a
path containing spaces and from any writable location under a user's profile.

The root batch file must:

- Detect supported Windows and Windows PowerShell.
- Prefer the inbox Windows PowerShell executable so the tool does not depend on
  PowerShell 7.
- run without elevation and refuse to relaunch as administrator;
- say plainly that Python and a virtual environment are not required;
- invoke the PowerShell installer/repair entry point;
- retain a readable terminal with progress, warnings, a final results table,
  installed paths, totals, and “Press Enter to close” behavior;
- propagate a meaningful nonzero exit code on failure;
- avoid hardcoded checkout paths, usernames, and drive letters.

The product should target Windows PowerShell 5.1 compatibility unless an actual
Windows API limitation makes that impossible.

### 2. Stable installed runtime

Setup installs a self-contained copy of every script needed by the context menu
under:

```text
%LOCALAPPDATA%\Portable-Folder-Icons\
  runtime\
  icons\
  manifest.json
  logs\                 only if logs are genuinely needed; keep bounded
```

The precise internal layout may be improved, but the following rules are
mandatory:

- Registry commands point only to stable installed-runtime paths, never the
  repository.
- Stage and validate new runtime files before replacing the active runtime.
- Reruns are idempotent install/update/repair/rescan operations.
- Do not delete old content-hashed icons during an ordinary setup or repair.
- Never copy source paths, credentials, or secrets into logs.
- Keep logs small and rotate or overwrite them if persistent logging is used.

### 3. ICO discovery, validation, labels, and cache

Scan only immediate `.ico` files from the exact repository-relative
`files\ICO-FIles` source unless a documented reason supports recursion.

For every candidate:

- Confirm it is a regular file with the `.ico` extension.
- Reject zero-byte, unreadable, malformed, or unsupported files without
  stopping the entire setup.
- Validate by loading it through a Windows/.NET icon API, not merely checking
  the extension.
- Calculate a SHA-256 content hash.
- Copy valid content to a stable cache filename derived from the full hash,
  such as `icons\<sha256>.ico`.
- Reuse an existing identical cached file.
- Do not overwrite a different hash in place.
- Produce a manifest containing the normalized menu label, original filename,
  full hash, cached filename, validation state, and install timestamp/version.
  Keep it free of unnecessary machine-specific source paths.

Label normalization must be deterministic:

1. remove the `.ico` suffix;
2. remove a leading `Folder_`, `Folder-`, or `Folder ` prefix,
   case-insensitively;
3. convert remaining underscores to spaces;
4. collapse repeated whitespace and trim;
5. preserve the remaining human-readable capitalization.

Use hash-derived internal registry key names so punctuation or Unicode in a
display label cannot corrupt registry layout. Reject an empty normalized label.
If two different source files normalize to the same label, mark the collision
clearly in the setup table and omit both ambiguous menu entries until the user
renames them. Identical content with different unambiguous labels may reuse one
cached file.

The setup output table should include, at minimum:

```text
Status | Menu Label | Source File | Hash | Result / Reason
```

Show totals for discovered, accepted, reused, copied, and rejected files.

### 4. Classic nested context menu

Register only under `HKCU`; never write to `HKLM` and never require admin.
Use a tool-owned subtree beneath:

```text
HKCU\Software\Classes\Directory\shell
```

The visible root verb is **Folder Icons**. It contains:

1. one alphabetically ordered command for every valid current manifest entry;
2. a separator where supported;
3. **Reset to Default**;
4. **Repair Portable Folder Icons**;
5. **Uninstall Portable Folder Icons**.

Use a reliable classic cascading-menu registry pattern supported for current
users on Windows 10/11. Research and validate the exact `shell`, `SubCommands`,
`ExtendedSubCommandsKey`, or CommandStore arrangement before committing to it.
Do not build a COM shell extension.

Version 1 must explicitly use single-selection behavior (for example, the
appropriate `MultiSelectModel` registration plus runtime target validation).
Every action must independently reject a missing target, a non-directory
target, more than one target, or a filesystem root with a clear message.

Registry command quoting must be tested with:

- spaces in `%LOCALAPPDATA%`;
- spaces, ampersands, apostrophes, parentheses, and Unicode in folder names;
- literal `%`, `!`, and other shell-sensitive characters where Windows allows
  them.

Never interpolate an untrusted path into executable PowerShell code. Pass it as
an argument to a fixed installed script.

On setup/rescan, replace only the tool-owned registry subtree. Validate the new
runtime and manifest first so a failed icon scan cannot destroy an otherwise
working installed menu.

### 5. Applying an icon

Applying a menu icon to one selected folder must:

- resolve the requested icon by hash/manifest identity, not an arbitrary path;
- confirm the cached ICO still exists and still matches its expected hash;
- update only the folder-icon keys in the selected folder's `desktop.ini`;
- preserve unrelated `desktop.ini` sections and keys;
- write using an Explorer-compatible encoding;
- apply only the minimum required file/folder attributes;
- handle read-only/hidden/system attributes without wiping unrelated
  attributes;
- report access-denied, protected-folder, unsupported-filesystem, or malformed
  existing-INI failures clearly;
- leave the folder in a recoverable state if writing fails partway through;
- invoke the targeted Explorer refresh described below.

Use the Windows-supported folder customization mechanism (`desktop.ini` plus a
stable cached icon path). Test paths with spaces and non-ASCII characters.

Do not apply icons to filesystem roots, Windows special/protected folders, or
locations the user cannot write. Do not recursively modify folder contents.

### 6. Reset to Default

Reset must remove only icon customization owned by the applicable
`desktop.ini` fields. Preserve unrelated folder customization. Delete
`desktop.ini` only when it contains no meaningful unrelated content and it is
safe to do so. Never broadly clear attributes or delete other hidden/system
files.

Reset must be idempotent and refresh Explorer even when the folder was already
at its default icon.

### 7. Targeted Explorer refresh

After Apply or Reset:

1. notify the Windows Shell of the changed folder/item using the appropriate
   `SHChangeNotify` event(s);
2. refresh only Explorer windows displaying the affected folder's parent when
   a refresh is still necessary;
3. keep every Explorer window open and at the same location;
4. never terminate or restart `explorer.exe`;
5. do not globally clear/rebuild the Windows icon cache during normal use.

Windows caching means a literal zero-delay change cannot be guaranteed on every
machine. Implement the strongest safe targeted method, allow a short bounded
retry if justified, and report a nonfatal warning if Windows still displays a
stale icon.

Do not promise preservation of selection or scroll state unless testing proves
it. The hard requirement is preserving open windows and their locations while
minimizing visible disruption.

### 8. Repair

The installed Repair command must work without the repository. It should:

- verify the installed runtime and current manifest;
- verify cached files referenced by the manifest;
- recreate the tool-owned context-menu registry entries;
- report missing or corrupt installed files clearly;
- preserve old hashed cache entries;
- never claim it imported newly added repository icons.

Rerunning the repository setup batch is the documented way to import or rescan
new source ICO files.

### 9. Uninstall

Uninstall must require an explicit, readable confirmation and then:

- remove only the tool-owned context-menu registry subtree;
- remove the installed executable/runtime scripts and active manifest;
- preserve the content-hashed `icons` cache by default so folders already using
  custom icons do not break;
- state clearly that cached icons were preserved and why;
- provide an explicitly separate purge-cache option only if it warns that
  purging can break icons already applied to folders;
- handle safe cleanup of the currently executing installed script after it
  exits;
- never modify customized folders automatically during uninstall.

Running uninstall twice must be safe.

## Security and safety requirements

- No elevation, scheduled task, service, background process, installer MSI/EXE,
  downloaded binary, Python runtime, or third-party package.
- No network access during setup or ordinary use.
- No broad or recursive registry deletion. Verify every registry target is
  inside the exact tool-owned HKCU subtree before removing it.
- No broad filesystem deletion. Verify every cleanup target is beneath the
  exact `%LOCALAPPDATA%\Portable-Folder-Icons` root.
- No Explorer restart.
- No hidden telemetry.
- PowerShell execution-policy bypass, if needed for a downloaded script, must
  be process-scoped on the invocation only and must not alter the user's
  persistent execution policy.
- Treat source filenames, selected folder paths, existing INI content, and
  manifest data as untrusted input.
- Use atomic/temp-file writes where practical and clean up only validated temp
  paths.

## Documentation requirements

Update the permanent documents without mixing their roles:

- `README.md`: end-user purpose, supported Windows versions, one-click setup,
  Show more options workflow, adding icons, rerunning setup, reset/repair/
  uninstall, limitations, licence note, troubleshooting, and SmartScreen
  first-run note.
- `md-instructions/Briefing.md`: architecture and complete product behavior.
- `md-instructions/Changelog.md`: append v0.1.0 changes.
- `md-instructions/Decisions.md`: append ADRs for pure PowerShell/no Python,
  classic HKCU menu, stable LocalAppData runtime, hashed cache retention,
  targeted refresh/no Explorer restart, single-selection v1, and the narrow
  `files\ICO-FIles` project exception.
- `md-instructions/Handoff.md`: phase checkpoints, tests, open issues, and
  cross-device sync log.
- `config.toml`: accurate name, version, Windows-only status, launcher, source
  icon directory, installed runtime root template, and verification entry
  point.

Do not hardcode the example `C:\Users\ematthew\...` location in runtime code or
end-user instructions. Use repository-relative and environment-variable forms.

## Verification strategy

This is a pure PowerShell project, so do not create Python solely to satisfy the
generic pytest preference. Provide one self-contained verification command:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify.ps1
```

Prefer built-in PowerShell/.NET testing with no online module installation. If
Pester is already scaffolded and can be used without making end users install
it, it may be retained, but verification must remain runnable on a fresh
Windows 10/11 user account without network access.

Automated tests must cover:

- filename-to-label normalization;
- empty/invalid label rejection;
- duplicate-label collision handling;
- valid, malformed, unreadable, and zero-byte ICO classification;
- deterministic SHA-256 cache naming and reuse;
- manifest serialization/deserialization and corrupt-manifest handling;
- registry plan generation in a disposable test subtree or dry-run mode;
- registry command quoting/argument boundaries;
- desktop.ini apply while preserving unrelated content;
- reset while preserving unrelated content;
- idempotent apply/reset/setup/repair/uninstall logic where testable;
- safe path guards for registry and filesystem cleanup;
- single-selection rejection;
- spaces and Unicode in paths;
- PowerShell 5.1 syntax compatibility.

Tests must never restart Explorer, globally clear icon cache, modify real user
folders, or install the live production menu. Use temp folders and a disposable
HKCU test subtree. Clean up only exact temp/test-owned targets.

The verify gate must also check:

- required root/project files exist;
- forbidden extra committed root items are absent;
- all committed ICO files validate;
- PowerShell scripts parse successfully;
- no hardcoded `C:\Users\ematthew` path exists in shipped runtime files;
- no HKLM writes, Explorer termination/restart, Python/.venv setup, or network
  download code exists;
- documentation and v0.1.0 changelog are updated;
- `git diff --check` is clean.

## Implementation phases

### Phase 0 — Reconcile and baseline

1. Read `AI-WORKSPACE.md`, agent instructions, all permanent
   `md-instructions` files, this plan, the current tree, licence, configuration,
   launcher template, and every existing script before editing.
2. Run `git status`, `git log`, `git remote -v`, and inspect ignored/untracked
   files. Preserve user work.
3. Confirm the remote is
   `https://github.com/elmatthe/Portable-Folder-Icons` (HTTPS, no embedded
   credentials).
4. If the local repository has no commits, create a clearly identified
   scaffold baseline commit on `main` from the existing user-approved scaffold,
   push it, then create
   `feature/v0.1.0-portable-folder-icons`. If a baseline commit already exists,
   create the feature branch from the correct current baseline. Do not merge
   implementation into `main`.
5. Record the starting state in `Handoff.md`.

Checkpoint: cleanly identified baseline and active working branch.

### Phase 1 — Core pure functions and tests

Implement/test label normalization, ICO validation, hashing, cache planning,
manifest schema, safe path guards, and desktop.ini transformations without
live registry or Explorer side effects.

Checkpoint: verification passes; update Handoff; commit and push the phase.

### Phase 2 — Stable installer and icon rescan

Implement the batch launcher and PowerShell installation/update flow, staged
runtime copy, icon results table, stable cache, manifest write, failure
handling, and idempotent reruns.

Checkpoint: verification passes; update Handoff; commit and push the phase.

### Phase 3 — Context menu integration

Implement the current-user classic cascading menu, safe command arguments,
single-selection model, icon entries, Reset, Repair, and Uninstall. Test registry
generation under a disposable subtree before live registration.

Checkpoint: verification passes; update Handoff; commit and push the phase.

### Phase 4 — Apply, Reset, and targeted refresh

Implement safe desktop.ini changes, reset behavior, shell notification,
targeted Explorer refresh, and clear user-facing errors.

Checkpoint: verification passes; update Handoff; commit and push the phase.

### Phase 5 — Repair, Uninstall, documentation, and hardening

Finish repository-independent repair, confirmed uninstall with default cache
preservation, purge warning, docs/config/ADRs/changelog, safe failure recovery,
and the complete verify gate.

Checkpoint: verification passes; update Handoff; commit and push the phase.

### Phase 6 — Bug hunt and manual-test handoff

Systematically inspect every shipped script for quoting, registry scope,
hardcoded paths, destructive cleanup, attribute damage, stale-menu behavior,
encoding, PowerShell 5.1 compatibility, and non-admin usability. Fix critical
issues with regression tests. Flag minor/suggestion items before expanding
scope.

Prepare `files\test-logs\v0.1.0_pre-release.md` as an ignored manual QA
checklist, but do not falsely mark user-only checks complete.

Checkpoint: final verification passes; Handoff and sync log match the commits;
working branch is pushed. Stop for user testing and explicit approval. Do not
merge to `main`.

## Required manual acceptance tests

Codex should automate what it can, then give the user a concise checklist for
the remaining Windows Explorer tests:

1. Fresh non-admin setup from a path containing spaces.
2. Setup terminal reports Python is unnecessary and shows all ten valid ICOs.
3. Folder Icons appears under Show more options for one selected normal folder.
4. Every menu icon has the expected filename-derived label.
5. Apply an icon to a writable test folder; it appears without closing/reopening
   Explorer.
6. Other open Explorer windows stay open at their existing locations.
7. Apply a different icon to the same folder.
8. Reset the folder while preserving unrelated folder customization.
9. Add a new valid ICO, rerun setup, and see the new menu choice.
10. Add an invalid `.ico`, rerun setup, and see a clear rejected-table reason
    while valid icons still work.
11. Rename/replace a source ICO and rerun setup; an already-customized folder
    keeps its previous appearance.
12. Move the repository, then confirm the installed menu and existing folder
    icons still work before rerunning setup.
13. Rerun setup from the moved location and confirm repair/rescan succeeds.
14. Repair with the repository unavailable.
15. Uninstall, confirm the menu disappears, and confirm existing customized
    folders retain their icons because the hash cache remains.
16. Reinstall and confirm idempotent recovery.
17. Test a folder name containing spaces and Unicode.
18. Confirm no UAC/admin prompt, Explorer restart, Python installation,
    persistent PowerShell policy change, or network access occurs.

## Future enhancement — explicitly not v0.1.0

Support applying one chosen icon to multiple simultaneously selected folders.
Before implementing it later, design argument passing that cannot truncate,
reorder, or execute selected paths; define partial-failure behavior; add a
confirmation for large selections; and extend tests for mixed writable/
unwritable targets. Do not leave dormant multi-select registry behavior in
v0.1.0.

## Definition of done

The working branch is ready for user testing only when:

- every requested v0.1.0 feature is implemented;
- all verification checks pass on Windows PowerShell 5.1;
- no unresolved critical issue remains;
- setup works without admin/Python/network;
- the installed runtime is independent of the repository;
- old applied icons survive source rename/replacement and normal uninstall;
- Explorer is never restarted;
- permanent docs and config are current;
- phase commits and the feature branch are pushed;
- `Handoff.md` accurately lists the live state and manual tests remaining.

The plan is not complete, and the feature branch must not be merged to `main`,
until the user performs the manual Explorer acceptance tests and explicitly
approves the end-of-plan merge.
