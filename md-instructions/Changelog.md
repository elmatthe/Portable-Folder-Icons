# Portable Folder Icons — Changelog

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
