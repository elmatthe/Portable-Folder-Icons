# Portable Folder Icons — Handoff

## Current Focus

All implementation phases and the bug hunt are complete and verified on
`feature/v0.1.0-portable-folder-icons`. Waiting for user-run Explorer
acceptance tests and explicit merge approval.

---

## Open Issues / Bugs

| # | Severity | File | Description | Status | Found by |
|---|----------|------|-------------|--------|----------|
| 1 | Minor | Explorer UI | Windows may retain a stale folder image until navigating away/back despite targeted notification; documented and pending manual characterization. | Documented / manual QA | Codex |
| 2 | Suggestion | Selection | Multi-folder apply needs safe multi-path transport and partial-failure UX. | Deferred beyond v0.1.0 per plan | User / Codex |

---

## Work Log (newest first)

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
