# Portable Folder Icons — Changelog

## v0.1.1 — Unreleased

### Phase 0A.1: windowless Repair and Uninstall — 2026-11-17 (`feature/v0.2.0`; version metadata still 0.1.1; manual M03 retest passed 2026-11-17)

- **Repair and Uninstall no longer open a PowerShell window.** On Windows 11,
  where Windows Terminal is the default terminal, choosing Repair (or
  Uninstall) opened a large Windows PowerShell terminal window that stayed
  behind the result dialog until it was closed. With Developer Mode off, both
  commands now start through the same windowless launcher that Apply and Reset
  already use. The result, confirmation and error dialogs are unchanged.
  Rerun `Setup_and_Run-Portable-Folder-Icons.bat` once so the menu uses the new
  command.
- **A missing runtime file is reported even earlier.** If the installed
  dispatcher script is missing, or PowerShell stops without reporting a result,
  the launcher shows one error dialog that names the problem and the setup
  launcher, instead of failing silently.
- Developer Mode keeps its previous direct PowerShell command, so a terminal
  window can still appear there.

### Phase 0A: Repair reliability — 2026-11-17 (`feature/v0.2.0`; version metadata still 0.1.1; manual M03 passed after Phase 0A.1)

- **Repair and Uninstall always explain a failure.** If an installed runtime
  file is missing or cannot be loaded, one error dialog names the file, says
  nothing was changed and tells you to double-click
  `Setup_and_Run-Portable-Folder-Icons.bat`. This holds with Developer Mode on
  or off. Before, the hidden command failed silently. Every other Repair failure
  (damaged settings, manifest or selection broker, or a menu that could not be
  recreated) also names the problem and the setup launcher.
- **A damaged cached icon no longer stops Repair.** Repair checks every cached
  icon, recreates the menu with the verified ones, and lists each missing or
  damaged icon as "not repaired and left out of the menu". It never claims to
  have repaired a damaged icon and never downloads, generates or imports one.
  It says Setup restores them from the icon files in your Portable Folder Icons
  folder.
- **Repair reports what it actually did.** The result lists the runtime and
  broker check, "Cached icons verified: X of Y", whether the menu was
  recreated, and the Developer Mode state.
- **Overlapping Repair and Uninstall requests no longer race.** A short,
  per-user lock (no service or background process) lets one Repair or Uninstall
  run at a time. Overlapping Repair requests from one multi-folder selection
  share one result dialog. A request that waits more than 60 seconds stops
  with an explanation and changes nothing. A lock left behind by an interrupted
  operation is taken over and reported.
- **Interaction with Uninstall.** Repair after Uninstall reports that the
  product is being or has been uninstalled and changes nothing. A second
  confirmed Uninstall says the earlier one already removed it. Uninstall's
  prompts, its cached-icon choice and what it removes are unchanged.
- Explorer behaviour with a real multi-folder selection was confirmed by manual
  check M03 on 2026-11-17 after Phase 0A.1: one result dialog for one folder
  and for five folders, shown in front of Explorer, with no terminal window.

### Phase 0B: accessible folder icon menus — 2026-11-16 (`feature/v0.2.0`; version metadata still 0.1.1)

- **Folder Icons** lists Reset to Default, Repair Portable Folder Icons and
  Uninstall Portable Folder Icons first, then **Choose Folder Icon** with the
  first 12 icons alphabetically. With more than 12 icons installed these
  commands had disappeared, because the Windows Shell showed at most 16 entries
  per top-level static menu entry and silently dropped the rest.
- Icons beyond the first 12 appear in additional top-level entries labelled by
  alphabetical range, for example **Folder Icons (Purple–Yellow)**, at most 16
  icons each. Setup and Repair add or remove these entries as the icon
  collection changes; Uninstall removes them. No icon is hidden: setup stops
  with an explanation if more than 1,596 icons are accepted.
- Manual Explorer acceptance (M01) passed on Windows 11 on 2026-11-16. This
  two-entry layout is the working fallback; a single-entry menu remains the
  preferred design and is under investigation.

### Phase 2 automated checkpoint — 2026-10-01

- Aligned broker initialization with the existing registered Reset key
  `Utility_0100_Reset`; request/dispatcher action remains `Reset`. Registration,
  request transport, and functional outcomes remain identical in both modes.
- Added registration-derived Apply/Reset initialization and invalid-identity
  coverage. Fixed native `IPropertyBag` VARIANT sizing (24 bytes x64, 16 x86),
  rebuilt both brokers, and refreshed source/artifact hashes.
- Classified `.ai/` and root `REPO-STRUCTURE.md` as ignored developer artifacts.
  Verification permits these exact local items, requires them to stay untracked,
  validates both broker artifacts, and includes C# in its security text scan.
- Focused x64/x86 harnesses each pass 350 assertions; the authoritative gate
  passes 371 PowerShell and 350 C# assertions with all 19 ICOs valid.
- Installed x64 COM Apply, Reset, and repeat Reset pass on two repository-owned
  fixtures; requests are consumed, broker processes exit, registered icon hashes
  match, and unrelated INI fields survive. Manual Explorer acceptance remains;
  no commit, release operation, Phase 3 work, or new-asset publication occurred.

### Development state — 2026-10-01

- Re-orientation confirms `88007c5` adds only the Phase 2 transport research
  gate to Handoff; Phase 1 is committed in `d6b27b9`.
- Preserved uncommitted Phase 2 work includes the x64/x86 .NET Framework COM
  selection broker, GUID/JSON request transport, ordered sequential Apply/Reset
  with aggregate outcomes, broker validation/staging, and COM lifecycle cleanup.
  These changes are not yet a completed or published checkpoint.
- Restored the locally deleted tracked `.command` Windows-only notice from
  HEAD. Preserved all 19 intentional ICOs; no new assets were committed.
- Exact HEAD verification passes 292 assertions. Worktree tests pass 371
  PowerShell and 256 separate C# harness assertions, with all 19 ICOs valid;
  the overall gate fails only the existing workspace root allowlist. A Reset
  verb identity mismatch remains outside the current synthetic test coverage.

### Added

- Added a scalable **Choose Folder Icon** child cascade so the dynamic icon
  collection can grow without displacing Reset, Repair, or Uninstall from the
  short parent menu.
- Added deterministic menu-plan coverage for zero, one, ten, the current local
  inventory, 30, and 50 icons, including ordering and exact ownership cleanup.

## v0.1.0 — 2026-08-25

### Added

- Added ten redistribution-approved folder colors and deterministic custom ICO
  discovery, validation, label generation, collision reporting, and rescan.
- Added a Windows PowerShell 5.1 setup launcher and staged, self-contained
  current-user runtime under `%LOCALAPPDATA%\Portable-Folder-Icons`.
- Added a classic **Folder Icons** cascading menu with Apply, Reset, Repair,
  and confirmed Uninstall actions.
- Added loss-minimizing `desktop.ini` updates, folder-scoped generated icon
  resources, SHA-256 cache integrity checks, protected-target guards, and
  targeted Shell refresh handling.
- Added strict `[settings] developer_mode` configuration. Apply and Reset are
  silent by default; opt-in Developer Mode shows progress and completion or
  warning dialogs. Errors remain visible in both modes.
- Added repository-independent Repair, safe default cache preservation during
  Uninstall, comprehensive PowerShell regression tests, and a Windows
  PowerShell 5.1 verification gate.
- Added a public release README with sanitized Explorer screenshots and a
  generated ten-color PNG gallery.

### Changed

- Setup now stages and atomically activates installed settings with the runtime
  and manifest. Rerunning setup applies configuration changes; Repair preserves
  the installed value; rollback restores the previous installed state.
- Apply retains every generated resource used by a folder until Reset removes
  only that folder's resources. Repair reports generated-resource counts
  without unsafe pruning.
- Documentation now accurately states the accepted Explorer behavior: an
  already-open view may retain the previous color until F5, navigation away
  and back, or a new Explorer view; Reset normally updates immediately.

### Fixed

- Eliminated the brief PowerShell-console flash in normal mode by routing Apply
  and Reset through an installed windowless Windows Script Host launcher.
  Developer Mode continues to invoke PowerShell visibly, and target paths are
  transported to the dispatcher as UTF-16 hex to preserve Unicode and
  shell-sensitive characters.
- Corrected batch-to-PowerShell repository-root quoting so checkout paths with
  spaces or Unicode do not acquire an illegal trailing quote.
- Repaired the classic cascade by using a valid `ExtendedSubCommandsKey`
  reference and narrowly removing only recognized legacy `Color:` verbs.
- Preserved unrelated `desktop.ini` content and attributes through Apply and
  Reset, including rollback after partial failures.
- Replaced path-only Shell invalidation with canonical PIDL notifications,
  deterministic PIDL cleanup, and targeted matching of parent Explorer views.
- Prevented generated-resource deletion during Apply from leaving folders on a
  permanently missing/default icon.

### Known limitations

- An already-open Explorer view may retain the previous folder color until
  refreshed. Press F5, navigate away and back, or open a new Explorer
  window/view to display the current color. Reset normally updates immediately.
- The v0.1.0 menu supports one selected folder at a time. Multi-folder
  selection is planned for a future release.
