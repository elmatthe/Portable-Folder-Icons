# Portable Folder Icons — Handoff

## Current Focus

Release preparation is complete on `feature/v0.1.0-portable-folder-icons`,
which remains unmerged. The user manually accepted setup, the classic cascade,
sequential Apply behavior, and Reset for v0.1.0.

The accepted Explorer limitation is: an already-open Explorer view may retain
the previous folder color until refreshed. Press F5, navigate away and back,
or open a new Explorer window/view to display the current color. Reset normally
updates immediately. Do not reopen the refresh-system design for v0.1.0.

Apply and Reset now run silently by default. Setting
`[settings] developer_mode = true` in `config.toml` before rerunning setup
restores their progress terminal and completion/warning dialog. Errors remain
visible in both modes. Setup persists the strict Boolean in installed
`settings.json`; Repair reuses it, rollback preserves it, and Uninstall removes
it. This new Developer Mode behavior still requires manual acceptance before
merge.

The fifth investigation into the stale-icon defect measured what Explorer
**actually paints**, by capturing the live window with `PrintWindow` and
classifying the folder item's pixels, rather than inferring success from
notifications and Shell queries. That produced a definite diagnosis and closed
two real defects, but it also established a genuine Windows limitation:

- **Fixed.** Apply no longer deletes a generated ICO that Explorer may still be
  resolving. That deletion was the cause of the folder falling back to the
  plain default icon permanently.
- **Fixed.** Refresh no longer reports success when a matched view was not
  reloaded, and a failed reload can no longer strand the view one level up.
- **Not solved, and not solvable under the current constraints.** Explorer
  caches a folder's icon resource process-wide. When that cache is warm, no
  supported non-invasive mechanism was found that makes an already-open view
  repaint a *changed* custom icon promptly. See "Explorer icon cache" below.

The rendered icon behavior has user acceptance. Developer Mode is the only
remaining manual acceptance gate before merge.

---

## Explorer icon cache — measured limitation

Method: capture the Explorer window with `PrintWindow(PW_RENDERFULLCONTENT)`
and classify the pixels in the folder item's icon rectangle. This is the only
evidence in this document that reflects what a user actually sees; everything
else proves internal state.

**What is correct immediately, every time, after Apply:** `desktop.ini`
contents, folder and `desktop.ini` attributes, the generated ICO on disk and
its hash, `SHGFI_ICONLOCATION`, and `SHGFI_SYSICONINDEX` queried from a fresh
process. None of these predict what is painted.

**What is stale:** Explorer's own cached mapping from the folder to its icon
resource, held process-wide.

**Measured findings:**

- Update-class notifications (`SHCNE_UPDATEITEM`, `SHCNE_UPDATEDIR` on either
  the parent or the folder itself, `SHCNE_ATTRIBUTES`, `SHCNE_UPDATEIMAGE`,
  `SHUpdateImage`) never cause Explorer to re-read `desktop.ini`.
- `SHCNE_RMDIR` + `SHCNE_MKDIR` on the folder's PIDL *does* force a full item
  re-resolve — it changed the painted icon within 300 ms in several runs — but
  the re-resolve reads the same stale cache, so it returns the old icon.
- Deleting the superseded ICO made the re-resolve find nothing, which Explorer
  cached as "no customization". The folder then showed the plain default icon
  and did not recover: 8 forced re-resolves over 60 s never restored it. This
  is the state reported from the field. Retaining the resource removes it.
- The following did **not** produce a correct repaint of a changed custom icon
  in an already-open view: delays up to 15 s; a view refresh (the F5
  equivalent); notify-then-identity-change ordered under `SHCNF_FLUSH`; atomic
  `desktop.ini` replacement instead of in-place truncation; and a two-phase
  apply routed through the default icon with a forced re-resolve on each leg.
- **A newly opened Explorer window resolves the current icon correctly.**
  Verified: a stuck pre-existing view painted the default icon while a window
  opened seconds later on the same folder painted the current colour. This is
  the practical workaround, and it only works because resources are now
  retained — previously the ICO was gone, so a fresh view was also correct in
  showing the default.

**Consequence for the product.** Apply reports what it did, not what is on
screen. The completion dialog states that a folder still showing its previous
icon is Explorer serving a cached icon. No code claims rendered pixels were
verified, because nothing in the product inspects them.

**Rejected as out of scope by the stated constraints:** restarting or killing
`explorer.exe`, deleting the global icon cache, and pacing the operation with
fixed delays. Restarting Explorer is the known-reliable way to clear this
cache; it is forbidden here and was not implemented.

---

## Open Issues / Bugs

| # | Severity | File | Description | Status | Found by |
|---|----------|------|-------------|--------|----------|
| 1 | Critical | Apply / generated resources | Apply deleted the superseded ICO while Explorer was still resolving it. The icon then resolved to nothing, Explorer cached "no customization", and the folder showed the plain default icon permanently. Every resource a folder has used is now retained until Reset reclaims them. | Fixed / awaiting user retest | Claude |
| 1a | Known limitation | Explorer icon cache | With a warm cache, an already-open Explorer view keeps painting the previous custom icon after Apply. No supported non-invasive mechanism was found that changes this; see "Explorer icon cache" above for the measured evidence. Opening a new window on the folder shows the current icon. | Documented, not solvable under current constraints | Claude |
| 1b | Major | Explorer refresh reporting | `RefreshSucceeded` was computed only from the notification count, so a run that matched a view and reloaded none of them still reported success. It now requires every matched view to have been reloaded, and reports `ViewReloadPerformed` separately. | Fixed | Claude |
| 1c | Major | Explorer refresh navigation | If the outbound leg of the away-and-back reload failed or timed out, the view was left stranded at the temporary parent. The return leg is now in a `finally` block. | Fixed | Claude |
| 2 | Critical | Registry integration | The parent stored `ExtendedSubCommandsKey` as a child key instead of a REG_SZ reference, so Explorer treated **Folder Icons** as a plain executable verb; setup also left ten recognized prototype `FolderColor_*` verbs in place. | Fixed / manual retest passed | User |
| 3 | Critical | `Setup_and_Run-Portable-Folder-Icons.bat` | Passing the trailing-backslash checkout root as `"%~dp0"` caused native PowerShell argument parsing to retain a closing quote in the value sent to `GetFullPath`. | Fixed / manual retest passed | User |
| 4 | Minor | Explorer UI | The same-location parent-view reload is intentionally stronger and may reset that view's selection or scroll position. Actual icon rendering remains a user-only visual assertion. | Mitigated / manual QA | Codex |
| 5 | Suggestion | Selection | Multi-folder apply needs safe multi-path transport and partial-failure UX. | Deferred beyond v0.1.0 per plan | User / Codex |

---

## Work Log (newest first)

- 2026-07-29 — Public-release preparation. Added strict default-false
  Developer Mode parsing and staged installed settings; normal Apply/Reset
  commands are hidden and omit success dialogs while errors remain visible,
  and Developer Mode retains progress and result UI. Repair preserves the
  installed value, rollback restores it, and Uninstall removes it. Rewrote the
  README and v0.1.0 changelog around the accepted Explorer limitation, added
  ADR 010, updated this briefing/handoff set, generated
  `files/readme-assets/folder-color-gallery.png`, and added sanitized
  `colored-folders-example.png` and `folder-icons-submenu.png`. Updated:
  `.gitignore`, `README.md`, `config.toml`, four permanent instruction documents, six
  shipped PowerShell/runtime files as applicable, `scripts/verify.ps1`, and
  `files/tests/Invoke-Tests.ps1`. Added: three README PNG assets. Deleted: no
  tracked files or directories; the local source screenshot folder was
  deliberately preserved and ignored to prevent accidental publication.
  Developer Mode awaits manual acceptance and the
  feature branch remains unmerged.

- 2026-07-29 — Fifth investigation. Built the missing instrument first: a
  `PrintWindow(PW_RENDERFULLCONTENT)` capture of the live Explorer window plus
  a pixel classifier for the folder item's icon rectangle, with a validity
  guard that fails loudly when the crop stops covering the icon. An earlier
  run had been silently invalidated by a stale crop, so this guard is load
  bearing. With rendered pixels as the evidence, every layer previously cited
  as proof — `desktop.ini`, attributes, ICO hash, `SHGFI_ICONLOCATION`,
  `SHGFI_SYSICONINDEX` from a fresh process — was correct immediately while
  Explorer painted the old icon, which means all four previous repairs
  targeted a layer that was never broken.

  The two-phase transition selected as the way forward was tested and
  **failed**: phase 1 repaints correctly, phase 2 does not, at 0 ms and at
  1500 ms between phases. The system image-list index model it was built on
  was not the real mechanism.

  Isolating the write style from the resource cleanup separated two distinct
  failure signatures: in-place write plus deletion produced the sticky plain
  default icon, whereas the same write with the resource retained produced
  merely the previous colour. That identified premature deletion as the cause
  of the unrecoverable state, confirming the standing hypothesis about
  generated-resource cleanup. A first attempt retained only one generation and
  still regressed, because a live view was observed lagging two applies behind
  and its resource was reclaimed underneath it; all resources for a folder are
  therefore retained until Reset.

  `SHCNE_RMDIR` + `SHCNE_MKDIR` was shown to genuinely force a full item
  re-resolve, unlike every update-class event tried before, but it reads the
  same stale cache and so does not fix a changed custom icon. Delays to 15 s,
  a view refresh, `SHCNF_FLUSH` ordering, atomic `desktop.ini` replacement and
  the two-phase route were all measured and all failed. The limitation is
  documented rather than papered over. A fresh Explorer window was verified to
  paint the current colour while a stuck view painted the default, which is
  the workaround and is only possible now that resources survive.

  Also fixed: `RefreshSucceeded` no longer reports success when a matched view
  was not reloaded, and the away-and-back reload returns the view to the
  original parent even when the outbound leg fails. Suite is 235 passing,
  `verify.ps1` RESULT: PASS including all ten ICOs and the Windows PowerShell
  5.1 gate, exercised against the reinstalled runtime. — Claude

- 2026-07-28 — Manual acceptance after `c17e663` failed: Blue, Red, and
  post-Reset Black remained stale while Reset was immediate. Installed runtime
  hashes matched source. Diagnostic `SHGetFileInfo` calls proved Blue, Red,
  and Black reused system image-list slot 239 while Reset selected standard
  folder slot 3. Changing to a uniquely named ICO alone did not change slot
  239, and Microsoft's targeted `SHUpdateImage` did not replace its old bitmap,
  so neither was shipped alone. Same-URL `Navigate2` was also being optimized
  away. The correction combines a unique per-Apply resource beneath
  `icons\applied` with an actual away-and-back navigation of only the matched
  Shell tab. Both legs wait on that object's canonical filesystem location and
  Busy state, not a sleep. Superseded generated resources are deleted only
  when their filename prefix matches the selected folder's canonical-path
  hash. Apply/Reset commands no longer use a hidden terminal and report four/
  three progress stages before the completion dialog. Tests cover unique
  identity/content, narrow cleanup, rapid sequences, exact tab targeting,
  away/back completion, PIDL cleanup, visible commands, and existing
  regressions. An early installed diagnostic exposed and fixed a trailing-URL
  normalization bug that could leave the tab at Downloads. The corrected
  installed Blue → Red → Reset → Black exercise matched/reloaded exactly one
  view each time, returned to Shared-Resources after every action, preserved
  Explorer PIDs, and stored the expected resource hash after each Apply.
  Programmatic verification does not assert the rendered pixels; user visual
  acceptance remains required. — Codex
- 2026-07-28 — The identity-preserving canonical-PIDL repair also failed
  manual testing: with `Shared-Resources` open, Apply remained stale until
  navigation, while Reset happened to repaint immediately. Installed runtime
  hashes exactly matched repository sources. Inspection proved the correct
  Shell-window entry was selected by decoded `LocationURL`, but the final call
  was only `IWebBrowser2.Refresh()`. Notifications update Shell state; they do
  not compel an existing Windows 11 folder view to discard and re-enumerate
  its displayed child items, and the ordinary browser refresh did not do so in
  this environment. The final step now calls `Navigate2` on only the matched
  Shell-window object with its unchanged current file URL. This rebuilds that
  view at the same location; loss of selection/scroll is accepted, while other
  tabs/windows are untouched. Tests now capture the exact HWND, same-location
  URL, full-view invocation, non-parent exclusion, sequential filesystem
  correctness, and PIDL cleanup. The Windows PowerShell 5.1 gate passes 152
  assertions and all ten ICO validations. Normal setup accepted all ten ICOs.
  With the real `Shared-Resources` Explorer tab open, an installed-runtime
  Blue → Red → Reset → Black sequence on a uniquely named disposable child
  matched and reloaded exactly one Shell view (HWND 459518) after every action;
  current icon resources matched every requested state, and Explorer PIDs and
  all tab locations remained unchanged. The diagnostic child was removed.
  Visual rendered-state acceptance remains with the user. — Codex
- 2026-07-28 — Manual retesting showed reproducible state lag after the first
  refresh repair: Apply/Reset eventually worked, but Explorer rendered the
  preceding or second-preceding icon. A disposable
  Blue → Red → Reset → Black → Green sequence proved that immediately after
  every operation, `desktop.ini`, its UTF-16LE encoding, attributes, referenced
  cached ICO, and SHA-256 all represented the latest request. The remaining
  defect was file identity and invalidation semantics: every atomic update
  replaced existing `desktop.ini` with a new NTFS file ID, while four
  `SHCNF_PATHW` notifications described it as an update. Explorer could process
  those notifications yet retain the prior cached shell item/property image.
  Existing `desktop.ini` is now updated in place after recovery backup and
  attribute handling, preserving identity; creation remains staged. Existing
  desktop.ini/folder/parent targets are converted with
  `SHParseDisplayName` and synchronously notified using `SHCNF_IDLIST`;
  deletion necessarily notifies the former desktop.ini path, followed by the
  same folder and parent PIDL invalidation. Every PIDL is released with
  `CoTaskMemFree` in `finally`. The corrected sequence preserves a stable file
  ID across Blue → Red and Black → Green and reports zero outstanding PIDLs.
  `SHGetSetFolderCustomSettings` was not adopted because its documented
  MAX_PATH boundary and whole-settings write model do not preserve this
  project’s long-path and unrelated-content requirements. Tests cover open-file
  identity preservation, canonical PIDL flags/cleanup, rapid sequences, Reset,
  and final cache hashes. The final Windows PowerShell 5.1 gate passes 149
  assertions and all ten ICO validations. Normal setup accepted all ten icons;
  installed runtime hashes match the repository. An installed-runtime
  Blue → Red → Reset → Black exercise showed current content/hash after every
  step, zero outstanding PIDLs, and unchanged Explorer PIDs and locations.
  Manual rendered-state retesting remains required. — Codex
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

### 2026-07-28 — Machine: G6-PF5DSHVY — versioned resource and full-tab reload repair

- Changed: Apply creates unique folder-scoped ICO resources and narrowly
  removes superseded resources for that selected folder.
- Changed: the matching Explorer tab is navigated out and back with
  canonical-path completion tracking; Apply/Reset progress is visible.
- Changed: tests cover resource identity/content/lifecycle, exact tab
  targeting, sequential actions, and completion ordering.
- Changed: README, Briefing, Decisions, Changelog, and Handoff record the
  failed third retest, evidence, correction, and pending visual acceptance.
- Note: the temporary implementation plan remains intentionally committed;
  do not delete or merge until manual approval.

### 2026-07-28 — Machine: G6-PF5DSHVY — canonical PIDL refresh correction

- Changed: updates preserve existing desktop.ini identity; new files retain
  staged creation and recovery behavior.
- Changed: existing Shell items are resolved with `SHParseDisplayName` and
  synchronously notified using `SHCNF_IDLIST`, with deterministic PIDL cleanup.
- Changed: tests cover open identity, rapid Apply/Reset sequences, PIDL target
  selection, allocation cleanup, and latest cache content.
- Changed: Changelog and Handoff record the failed first retest, evidence,
  corrected cause, and pending visual retest.
- Note: the temporary implementation plan remains intentionally committed;
  do not delete or merge until manual approval.

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
