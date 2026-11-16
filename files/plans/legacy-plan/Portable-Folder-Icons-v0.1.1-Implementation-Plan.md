# Portable Folder Icons v0.1.1 — Focused Implementation Plan

## Authority and gates

This temporary drop records the user-approved 2026-08-25 v0.1.1 directive.
Read the applicable agent guidance, all four permanent documents, the complete
runtime/test suite, configuration, launchers, verification gate, Git state,
and actual ICO inventory before editing. Preserve all user work. Do not reset,
clean, discard, overwrite, or delete uncommitted assets.

v0.1.0 must be formally reconciled, verified, tagged, and released before this
work begins. Implement only on `feature/v0.1.1`, created from the exact verified
post-v0.1.0 `main`. Commit, verify, update Handoff, and push at phase
checkpoints. Never merge or release v0.1.1 before the final user manual gate
and explicit approval.

Public GitHub issues are intentionally not used. Open state, research, bugs,
and deferred work belong in `md-instructions`.

## Locked product decisions

- Keep v0.1.1 focused. Admin Mode and the Windows 11 modern first-level menu
  are research only.
- Multi-folder Apply and Reset continue sequentially after individual failures
  and provide one aggregate result. Add no project-defined selection cap.
- Preserve every selected path without truncation, reordering, or evaluation
  as PowerShell source. Cover spaces, Unicode, ampersands, apostrophes,
  parentheses, percent signs, exclamation points, and other shell-sensitive
  characters.
- Automatic refresh performs the existing immediate targeted refresh and, when
  configured, exactly one bounded delayed targeted retry. No loops, polling,
  watcher, resident process, service, or scheduled task.
- Developer Mode never changes functional outcomes. It adds visible terminal
  diagnostics and bounded persistent logs under
  `%LOCALAPPDATA%\Portable-Folder-Icons\logs`. Normal all-success Apply/Reset
  remain silent; failures are never hidden.
- Track successful folder customizations beneath stable installed state.
  Successful Reset removes the matching record. Tolerate duplicate operations
  and folders that are moved, renamed, deleted, or temporarily unavailable.
- Ordinary uninstall preserves icon content needed by customized folders.
  `REMOVE COMPLETELY` is available from both repository setup and the installed
  uninstall action; it offers to reset tracked folders and removes cache only
  when doing so will not knowingly break tracked customizations.
- Repository configuration changes take effect only after rerunning
  `Setup_and_Run-Portable-Folder-Icons.bat`.

## Phase 1 — Scalable context menu

Research whether a static `ExtendedSubCommandsKey` cascade can scroll only an
icon region while pinning sibling utilities. Do not add a COM extension solely
for appearance. If unsupported, use a short parent menu containing one nested
dynamic, alphabetical icon chooser followed by Reset, Repair, and Uninstall.
Cover zero, one, ten, current, 30, and 50 icons; one Apply verb per accepted
icon; utility placement; exact ownership cleanup; Repair; and Uninstall.

## Phase 2 — Safe multi-folder Apply and Reset

Research actual Explorer static-verb multi-selection invocation before choosing
transport. Process each target independently and sequentially, continue after
failure, never roll back unrelated successes, and present one useful aggregate
failure summary. Keep all-success normal mode silent. Refresh only affected
folders/views and deduplicate parent work only when correctness is preserved.
Never restart Explorer.

## Phase 3 — Installed configuration and one refresh retry

Keep `config.toml` authoritative and stage strict parsed settings during setup.
Perform immediate targeted refresh, then at most one configured bounded delay
and one additional targeted attempt. Document invalid-value behavior and the
required setup rerun. Do not claim this clears Explorer's process-wide cache.

## Phase 4 — Developer diagnostics and bounded logs

Developer Mode retains visible progress and adds detailed per-target,
refresh-attempt, Repair, and Uninstall logging. Logs must contain no secrets or
unnecessary repository paths, represent Unicode/special paths safely, rotate
with a simple bound, and never become required for success.

## Phase 5 — Tracked customizations

After successful Apply, atomically record canonical identity/path and enough
tool-owned state for safe future cleanup. Do not record failed Apply. Successful
Reset removes the record. Handle repeat Apply/Reset, partial multi-target
failure, moved/renamed/deleted/unavailable folders, and corruption without a
watcher or continuous monitoring.

## Phase 6 — Safe complete removal

Ordinary uninstall keeps required cached ICOs. Complete removal loads tracking,
explains the operation, offers tracked-folder Reset, processes what is safely
available, reports unresolved targets, preserves unrelated `desktop.ini`
content, removes only tool-owned state, and deletes cache only when unresolved
tracked customizations will not be broken. Repeated uninstall stays safe. There
is no delete-anyway escape hatch.

## Phases 7–8 — Research only

Document whether elevation materially helps icon caching, protected targets,
or machine-wide installation enough to justify UAC/HKLM complexity and loss of
current-user portability. Add no production HKLM writes.

Document current Microsoft requirements for Windows 11 first-level menu
integration: `IExplorerCommand`, native COM, package identity/MSIX or sparse
package, signing/deployment/security, per-user feasibility, and maintenance.
Add no compiled prototype or dependency.

## Phases 9–10 — Documentation, bug hunt, and final gate

Set version 0.1.1 on the working branch. Keep Briefing descriptive, Changelog
append-only with v0.1.1 Unreleased, Decisions append-only with superseding ADRs,
and Handoff current. Systematically review every shipped script for PowerShell
5.1, quoting/transport, large/mixed selection, registry/filesystem ownership,
tracking corruption and moved targets, rollback, logging/retention, strict
config, refresh retry, zero/50+ icon menus, repository-independent Repair,
console suppression, hardcoded paths, HKLM/elevation, Explorer restart/cache
deletion, network access, and background execution. Every critical fix gets a
regression test.

The authoritative gate is:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify.ps1
```

Windows PowerShell 5.1 is mandatory. The gate must parse every shipped script,
run all deterministic tests, validate every committed ICO and exact directory
case, enforce safe registry/filesystem scopes, reject HKLM/Explorer restart/
global cache deletion/Python/network/watchers/services/tasks, align version and
docs, and pass `git diff --check`.

Before public merge, obtain explicit redistribution confirmation for every new
ICO that will be committed. Do not delete unapproved local icons.

After automation passes, stop with the required Windows manual checklist. Do
not merge, tag, or release v0.1.1 until the user records manual results,
resolves asset rights, and explicitly approves the final result. Then delete
this temporary drop before the approved merge/release workflow.
