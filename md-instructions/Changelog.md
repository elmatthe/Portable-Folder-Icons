# Portable Folder Icons — Changelog

## v0.1.1 — Unreleased

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
