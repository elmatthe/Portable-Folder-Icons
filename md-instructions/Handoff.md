# Portable Folder Icons — Handoff

## Current Focus

Phases 0–2 are complete and verified. Phase 3 classic HKCU context-menu
integration is next on `feature/v0.1.0-portable-folder-icons`.

---

## Open Issues / Bugs

| # | Severity | File | Description | Status | Found by |
|---|----------|------|-------------|--------|----------|
| — | — | — | No implementation issues recorded yet. | — | — |

---

## Work Log (newest first)

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
