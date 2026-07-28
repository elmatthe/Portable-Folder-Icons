# Portable Folder Icons — Changelog

## v0.1.0 — 2026-07-28

### Added

- Established the local scaffold baseline and v0.1.0 implementation branch.
- Added ten user-supplied, redistribution-approved folder ICO assets.
- Added pure PowerShell core functions and deterministic tests for labels, ICO
  validation, hashing/cache plans, manifests, cleanup guards, selection
  validation, and loss-minimizing `desktop.ini` transforms.
- Added the Windows PowerShell 5.1 setup launcher and staged LocalAppData
  runtime installer with validated icon rescan, atomic manifest writes,
  content-hash cache reuse, and readable results/totals.
- Added a current-user classic **Folder Icons** cascade with alphabetic
  hash-keyed icon verbs, Reset, Repair, and Uninstall commands, plus
  single-selection registration and fixed-script argument boundaries.
- Added integrity-checked Apply and loss-minimizing Reset actions with
  UTF-16LE `desktop.ini` writes, narrow attribute changes, recovery backups,
  protected-target checks, Shell change notification, and parent-window-only
  Explorer refresh.
- Added repository-independent Repair, confirmed Uninstall with default
  hash-cache preservation and separately warned purge, post-exit self-cleanup,
  full end-user documentation, architecture ADRs, and comprehensive
  PowerShell verification/security gates.

### Changed

- Converted the generic scaffold metadata and permanent documentation into a
  Windows-only pure-PowerShell project.
- Hardened staged updates to restore the prior runtime, manifest, and menu when
  activation or registration fails.

### Fixed

- Prevented batch metacharacters in checkout paths from being reinterpreted
  through dynamic `echo` output.
- Removed now-empty `.ShellClassInfo` sections correctly when another INI
  section follows, and reject duplicate shell sections rather than partially
  editing ambiguous data.
- Made hash-filename cache conflicts fail setup without replacing the active
  manifest/menu.
- Added whole-operation Apply/Reset rollback and cleanup of newly created
  partial `desktop.ini` files after a write/attribute failure.
