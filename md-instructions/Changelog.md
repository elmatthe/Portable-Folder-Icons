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

- Stopped Apply from deleting a generated ICO that Explorer may still be
  resolving. Deleting it made the icon resolve to nothing, which Explorer
  cached as "no customization", leaving the folder on the plain default icon
  permanently. Every generated resource a folder has used is now retained
  until Reset removes the customization and reclaims them all; Repair counts
  them and never deletes them, because it cannot prove one is unreferenced.
- Stopped the Explorer refresh from reporting success when it had reloaded
  nothing. `RefreshSucceeded` previously came from the notification count
  alone, so a run that matched an open parent view and failed to reload it
  still reported success. It now requires every matched view to have been
  reloaded, and reports whether a view was reloaded at all.
- Stopped a failed away-and-back reload from stranding the Explorer view one
  level above the folder. The return navigation now runs even when the
  outbound leg fails or times out.
- Replaced the unqualified "Apply completed successfully" dialog with one that
  states what was done and explains that a folder still showing its previous
  icon is Explorer serving a cached icon. Nothing in the product inspects
  rendered pixels, so nothing claims they were verified.

### Known limitations

- With a warm Explorer icon cache, an already-open view can keep painting a
  folder's previous custom icon after Apply. This was measured directly from
  rendered pixels: the filesystem, attributes, generated ICO and Shell
  resolution are all correct immediately, while Explorer serves its cached
  mapping. Update-class Shell notifications, a view refresh, away-and-back
  navigation, atomic `desktop.ini` replacement, forced item re-resolve via
  `SHCNE_RMDIR`/`SHCNE_MKDIR`, a two-phase apply through the default icon, and
  delays up to 15 seconds were each measured and none corrected it. Opening a
  new Explorer window on the folder shows the current icon. Restarting
  Explorer would clear the cache but is excluded by the project constraints.

- Prevented reuse of a stale customized-folder system image-list entry by
  giving each Apply a unique folder-scoped ICO resource identity and fully
  navigating only the matching parent Explorer tab out and back. Navigation
  completion is verified from canonical filesystem paths and the tab's Busy
  state without a fixed delay; Apply/Reset now keep a progress terminal
  visible, and superseded folder-owned generated resources are removed
  narrowly.
- Replaced the ineffective ordinary `IWebBrowser2.Refresh()` call with a
  targeted same-window `Navigate2` reload of each Explorer view displaying the
  changed folder's parent. The stronger reload re-enumerates the displayed
  child items while retaining the Explorer window and folder location;
  selection and scroll position may reset.
- Prevented reproducible one-state-behind Explorer rendering by preserving the
  identity of an existing desktop.ini during updates and replacing path-only
  invalidation for existing Shell items with synchronous canonical-PIDL
  notifications obtained through `SHParseDisplayName`. Deleted desktop.ini
  paths retain the supported path notification, and all allocated PIDLs are
  released deterministically.
- Strengthened Apply and Reset repaint handling by synchronously notifying the
  Shell about desktop.ini creation/update/deletion, folder attributes and item
  changes, and parent-directory changes before refreshing only Explorer views
  displaying that parent. Completion dialogs now follow all refresh attempts
  and distinguish an applied customization from an automatic-refresh warning;
  existing unrelated desktop.ini attributes are preserved.
- Repaired the classic Explorer cascade by replacing the malformed
  `ExtendedSubCommandsKey` child tree with the required REG_SZ reference to a
  separate current-user Classes submenu store. Setup, Repair, and Uninstall
  now remove only exactly recognized legacy `FolderColor_<Color>` prototype
  verbs while preserving unrelated context-menu integrations, and notify the
  Shell of association changes without restarting Explorer.
- Corrected the batch-to-PowerShell repository-root argument boundary so a
  trailing backslash cannot escape the closing quote and append an illegal
  quote character before `GetFullPath`; checkout paths containing spaces and
  Unicode remain intact.
- Corrected the distributable icon-source directory spelling from
  `files\ICO-FIles` to `files\ICO-Files` across Git, runtime code, tests,
  configuration, and documentation.
- Prevented batch metacharacters in checkout paths from being reinterpreted
  through dynamic `echo` output.
- Removed now-empty `.ShellClassInfo` sections correctly when another INI
  section follows, and reject duplicate shell sections rather than partially
  editing ambiguous data.
- Made hash-filename cache conflicts fail setup without replacing the active
  manifest/menu.
- Added whole-operation Apply/Reset rollback and cleanup of newly created
  partial `desktop.ini` files after a write/attribute failure.
