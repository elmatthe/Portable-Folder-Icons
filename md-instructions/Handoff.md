# Portable Folder Icons — Handoff

## Current Focus

All implementation phases and the bug hunt are complete on
`feature/v0.1.0-portable-folder-icons`. Setup and the repaired classic cascade
passed manual testing. The remaining Step 7 delayed Explorer repaint defect is
repaired and verified automatically; waiting for the user to retest Apply,
Apply Different Icon, and Reset before continuing acceptance or considering a
merge.

---

## Open Issues / Bugs

| # | Severity | File | Description | Status | Found by |
|---|----------|------|-------------|--------|----------|
| 1 | Critical | Explorer refresh | Apply notified only the customized folder using asynchronous `SHCNF_FLUSHNOWAIT`, then raced a direct view refresh; it did not notify changed `desktop.ini` or the parent directory. | Fixed / awaiting user Step 7 retest | User |
| 2 | Critical | Registry integration | The parent stored `ExtendedSubCommandsKey` as a child key instead of a REG_SZ reference, so Explorer treated **Folder Icons** as a plain executable verb; setup also left ten recognized prototype `FolderColor_*` verbs in place. | Fixed / manual retest passed | User |
| 3 | Critical | `Setup_and_Run-Portable-Folder-Icons.bat` | Passing the trailing-backslash checkout root as `"%~dp0"` caused native PowerShell argument parsing to retain a closing quote in the value sent to `GetFullPath`. | Fixed / manual retest passed | User |
| 4 | Minor | Explorer UI | Windows may still retain an item image briefly after all supported targeted notifications; zero-latency repaint cannot be guaranteed. | Mitigated / manual QA | Codex |
| 5 | Suggestion | Selection | Multi-folder apply needs safe multi-path transport and partial-failure UX. | Deferred beyond v0.1.0 per plan | User / Codex |

---

## Work Log (newest first)

- 2026-07-28 — The repaired classic cascade passed manual acceptance, but
  applying Blue over an existing yellow customization remained visually stale
  until Explorer was reopened roughly 30 seconds later. The filesystem portion
  was already committed before refresh: Unicode `desktop.ini` writes close
  before atomic replacement, the file is Hidden/System, and the folder is
  ReadOnly. The exact refresh defect was an incomplete, racy sequence:
  `SHCNE_ATTRIBUTES|SHCNE_UPDATEITEM` targeted only the customized folder with
  `SHCNF_PATHW|SHCNF_FLUSHNOWAIT`, immediately followed by parent-view
  `Refresh()`. Notification delivery was not complete, `desktop.ini` and the
  parent were never notified, and the view could repaint from the old cached
  item image. The corrected sequence uses canonical absolute paths and
  synchronous `SHCNF_FLUSH` for desktop.ini Create/Update/Delete, folder
  Attributes, folder UpdateItem, and parent UpdatedDir, then refreshes only
  Explorer views whose decoded filesystem URL equals the parent
  case-insensitively. Apply/Reset return refresh status; their modal result is
  shown only afterward and distinguishes a saved customization from an
  automatic-refresh warning. Existing `desktop.ini` attributes are now
  preserved in addition to unrelated content. Injectable tests cover ordering,
  both Apply paths, Reset, special-character paths, targets, matching, and
  refresh failure. All 132 assertions pass in the final verification
  gate. A disposable real Apply/different-icon/Reset issued four notifications
  per operation and preserved Explorer processes and window locations.
  Manual visual Step 7 retest remains required. — Codex
- 2026-07-28 — Diagnosed the second manual acceptance failure from the exact
  live HKCU state. The parent
  `HKCU\Software\Classes\Directory\shell\PortableFolderIcons` had MUIVerb,
  Icon, and MultiSelectModel but no cascade-signaling value; instead, the
  implementation incorrectly created a literal
  `PortableFolderIcons\ExtendedSubCommandsKey\shell` child tree. Explorer
  therefore exposed the parent as a plain verb with no command handler and
  attempted ordinary activation against the selected folder, producing the
  file-association error. Ten older `FolderColor_<Color>` prototype verbs also
  remained at the Directory shell level. Corrected the parent to a REG_SZ
  `ExtendedSubCommandsKey=PortableFolderIcons.ContextMenu` reference and moved
  all 13 verbs to the separate current-user Classes store
  `HKCU\Software\Classes\PortableFolderIcons.ContextMenu\shell`. Setup, Repair,
  and Uninstall now remove only the ten allowlisted legacy color keys when
  their exact `Color: <Color>`, `SetFolderColor.ps1`, `-folderPath "%1"`, and
  matching `Folder_<Color>.ico,0` markers agree. Isolated HKCU tests prove
  cascade shape, commands/quoting, idempotence, stale-icon removal, uninstall,
  and preservation of unrelated and lookalike keys. The full suite has 101
  passing assertions. Normal setup repaired the live menu without elevation;
  registry inspection confirms ten icon verbs, three utility verbs, no parent
  command, no obsolete cascade child, and no recognized legacy keys. A Shell
  association-change notification was sent without restarting Explorer.
  Manual Explorer retest remains required. — Codex
- 2026-07-28 — Diagnosed the manual Step 1 failure at the native
  batch-to-PowerShell boundary. `%~dp0` ends in `\`; enclosing that value
  directly in quotes caused the closing quote to reach PowerShell as a literal
  U+0022. The malformed installer argument was
  `C:\Users\ematthew\Portable-User-Installs\Portable-Folder-Icons<QUOTE>`.
  Changed the launcher boundary to `"%~dp0."`, which preserves spaces and
  Unicode while allowing `GetFullPath` to canonicalize the harmless final
  component. Regression tests cover the actual checkout, spaces, Unicode, the
  exact malformed value, and launcher argument construction. All 79 assertions
  pass. Full setup succeeded from both the actual checkout and a temporary
  spaces-plus-Unicode checkout; a controlled pre-install failure preserved the
  active runtime and manifest byte-for-byte. Manual Step 1 remains failed until
  the user reruns and accepts it. — Codex
- 2026-07-28 — Recorded the user-corrected case-only icon directory rename as
  `files/ICO-Files` in Git and updated runtime code, tests, config, permanent
  docs, and the retained plan. Full Windows PowerShell 5.1 verification passes
  with 73 assertions, ten ICO validations, and an exact-case directory gate.
  — Codex
- 2026-07-28 — Phase 6 systematic bug hunt completed across every shipped
  batch/PowerShell script. Fixed unsafe batch dynamic-path echoing, adjacent
  empty INI-section cleanup, duplicate shell-section ambiguity, cache-conflict
  activation, and whole-operation Apply/Reset recovery; added regression
  assertions for each. The ignored manual checklist is at
  `files/test-logs/v0.1.0_pre-release.md`. Final gate: 73 assertions plus all
  structural/security/documentation checks pass under Windows PowerShell 5.1.
  No unresolved critical issue; user-only Explorer tests remain. — Codex
- 2026-07-28 — Phase 5 checkpoint passed under Windows PowerShell 5.1. Added
  installed runtime/cache integrity Repair, exact-scope confirmed Uninstall,
  default cache preservation, separately warned purge, post-exit cleanup,
  staged-update rollback, comprehensive README/config/permanent docs, and
  final gates for root layout, forbidden code, metadata, docs, parsing, all
  ICOs, tests, PowerShell version, and `git diff --check`. 69 assertions and
  the complete verify gate pass. — Codex
- 2026-07-28 — Phase 4 checkpoint passed under Windows PowerShell 5.1. Added
  protected/root/filesystem target checks, manifest/hash-resolved Apply,
  cached-icon integrity verification, recoverable UTF-16LE `desktop.ini`
  writes, selective icon-field Reset, narrow attribute operations,
  `SHChangeNotify`, and refresh of only Explorer windows showing the affected
  parent. Temp-folder tests cover unrelated-content preservation, encoding,
  attributes, idempotence, empty-INI deletion, malformed INI recovery, and
  corrupt cache rejection. 60 assertions pass; `git diff --check` is clean.
  — Codex
- 2026-07-28 — Phase 3 checkpoint passed under Windows PowerShell 5.1. Added
  the documented HKCU `ExtendedSubCommandsKey\shell` cascade, alphabetic
  hash-derived icon verbs, separator flag, Reset/Repair/Uninstall commands,
  `MultiSelectModel=Single`, fixed `-File` action commands, strict tool-owned
  registry guards, and setup registration after runtime/manifest validation.
  A complete disposable-root dry-run plan and special-character LocalAppData
  path are covered; 44 assertions pass and `git diff --check` is clean.
  — Codex
- 2026-07-28 — Phase 2 checkpoint passed under Windows PowerShell 5.1. Replaced
  the generic Python launcher with a non-admin inbox-PowerShell launcher and
  added staged runtime installation, immediate ICO rescan, hash-cache
  copy/reuse, manifest validation/write, results table, totals, and installed
  paths. The automated installer ran twice under a path containing spaces and
  Unicode: first run copied all ten ICOs; second run reused all ten and
  preserved the cache. 34 assertions pass and `git diff --check` is clean.
  — Codex
- 2026-07-28 — Phase 1 checkpoint passed under Windows PowerShell 5.1. Added
  side-effect-free core behavior and 30 deterministic assertions covering
  normalization, empty labels, valid/malformed/unreadable/zero-byte ICOs,
  SHA-256 cache copy/reuse, duplicate labels, manifest round trips/corruption,
  filesystem/registry guards, single-selection paths with Unicode, and
  preserving unrelated `desktop.ini` content during apply/reset.
  `git diff --check` is clean. — Codex
- 2026-07-28 — Phase 0 checkpoint passed under Windows PowerShell 5.1:
  permanent files were de-templated, the preliminary pure-PowerShell verify
  gate passed all required-file, parse, ICO, and changelog checks, and
  `git diff --check` was clean. — Codex
- 2026-07-28 — Phase 0 audit complete: read all instructions and source,
  validated all ten ICOs through .NET, confirmed the GitHub remote was empty,
  created/pushed baseline commit `79e0ee1` on `main`, and created the required
  feature branch. Historical backups and logs remain local and ignored because
  they contain machine-specific paths. — Codex

---

## Session Sync Log (newest first)

### 2026-07-28 — Machine: G6-PF5DSHVY — targeted Explorer refresh repair

- Changed: Apply/Reset refresh to notify desktop.ini, the customized folder,
  and its parent synchronously before refreshing only parent Explorer views.
- Changed: action results and dispatcher messaging to distinguish saved
  customization from automatic-refresh failure.
- Changed: tests for operation ordering, special-character paths,
  different-icon apply, Reset, target selection, attributes, and failure.
- Changed: Changelog and Handoff with the manual delay and pending visual
  retest.
- Note: the temporary implementation plan remains intentionally committed;
  do not delete or merge until manual approval.

### 2026-07-28 — Machine: G6-PF5DSHVY — Explorer cascade repair

- Changed: registry integration to use a current-user
  `ExtendedSubCommandsKey` reference and separate project-owned submenu store.
- Changed: setup/Repair/Uninstall to remove only exact recognized prototype
  `FolderColor_<Color>` entries and notify the Shell of association changes.
- Changed: tests for live registry shape, command safety, cleanup scope,
  idempotence, rescan removal, and uninstall.
- Changed: Changelog and Handoff with the live root cause and pending manual
  Explorer retest.
- Local ignored: pre-repair registry export under `files/test-logs/`.
- Note: the temporary implementation plan remains intentionally committed;
  do not delete or merge until manual approval.

### 2026-07-28 — Machine: G6-PF5DSHVY — Step 1 launcher fix

- Changed: batch launcher argument boundary from `"%~dp0"` to `"%~dp0."`.
- Changed: deterministic tests for actual, spaces, Unicode, and malformed
  batch-to-PowerShell repository-root values.
- Changed: Changelog and Handoff with root cause, verification, and pending
  manual retest.
- Note: the temporary implementation plan remains intentionally committed;
  do not delete or merge until manual approval.

### 2026-07-28 — Machine: G6-PF5DSHVY — pushed with folder-name correction

- Renamed: `files/ICO-FIles` to `files/ICO-Files` as a Git-recorded case-only
  directory change (all ten ICOs preserved).
- Changed: runtime installer, tests, verification, config, README, permanent
  docs, and retained implementation plan to use the corrected spelling.

### 2026-07-28 — Machine: G6-PF5DSHVY — pushed with Phase 6 checkpoint

- Changed: batch launcher, installer, core, actions, tests, and verify gate for
  five bug-hunt regression fixes.
- Changed: Briefing, Changelog, and Handoff for final pre-release state.
- Local ignored: `files/test-logs/v0.1.0_pre-release.md` manual QA checklist.
- Note: the temporary implementation plan remains intentionally committed;
  do not delete or merge until manual approval.

### 2026-07-28 — Machine: G6-PF5DSHVY — pushed with Phase 5 checkpoint

- Added: `scripts/Windows/PortableFolderIcons.Maintenance.ps1`.
- Added: `scripts/Windows/Cleanup-PortableFolderIcons.ps1`.
- Deleted: legacy `scripts/SetFolderColor.ps1` (preserved in baseline history).
- Changed: installer/dispatcher, tests, verify gate, README, Briefing,
  Changelog, Decisions, and Handoff for Phase 5.

### 2026-07-28 — Machine: G6-PF5DSHVY — pushed with Phase 4 checkpoint

- Added: `scripts/Windows/PortableFolderIcons.Actions.ps1`.
- Changed: installed dispatcher and installer runtime completeness check.
- Changed: tests, Changelog, Decisions, and Handoff for Phase 4.

### 2026-07-28 — Machine: G6-PF5DSHVY — pushed with Phase 3 checkpoint

- Added: `scripts/Windows/PortableFolderIcons.Integration.ps1`.
- Added: `scripts/Windows/Invoke-PortableFolderIcons.ps1`.
- Changed: installer to stage four runtime scripts and register after
  validation.
- Changed: tests, Changelog, Decisions, and Handoff for Phase 3.

### 2026-07-28 — Machine: G6-PF5DSHVY — pushed with Phase 2 checkpoint

- Added: `scripts/Windows/Install-PortableFolderIcons.ps1`.
- Changed: root batch launcher to pure Windows PowerShell setup.
- Changed: test suite with staged install/rerun/cache-preservation coverage.
- Changed: Changelog and Handoff for the Phase 2 checkpoint.

### 2026-07-28 — Machine: G6-PF5DSHVY — pushed with Phase 1 checkpoint

- Added: `scripts/Windows/PortableFolderIcons.Core.ps1`.
- Added: `files/tests/Invoke-Tests.ps1`.
- Changed: `scripts/verify.ps1` to execute the dependency-free test suite.
- Changed: Changelog and Handoff for the Phase 1 checkpoint.

### 2026-07-28 — Machine: G6-PF5DSHVY — pushed (commit `1aa60d2`)

- Added: `.gitignore` to keep local workspace data, backups, and logs private.
- Added: `.gitattributes`, `LICENSE`, `README.md`, `config.toml`, macOS notice
  launcher, four permanent docs, and `scripts/verify.ps1`.
- Deleted: corresponding scaffold templates plus Python verification and
  requirements templates, because this project is pure PowerShell.
- Changed: project metadata and permanent docs for v0.1.0 Phase 0.
- Note: `main` contains only baseline commit `79e0ee1`; implementation remains
  exclusively on the feature branch.
