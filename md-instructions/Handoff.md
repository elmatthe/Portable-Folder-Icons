# Portable Folder Icons — Handoff

## Snapshot — 2026-11-17 (Phase 0A.1 windowless maintenance launch) — Claude Code (current)

- **Machine and branch:**
  - The original Windows 11 PC: 25H2 build 26200, Windows PowerShell 5.1.
  - Default terminal: Windows Terminal 1.25.3131.0 ("Let Windows decide").
  - Branch `feature/v0.2.0`.
- **Start SHA:** `3170d8f2467bd0a112786ac18e17d7c23140c4bd` (Phase 0A, already on `origin`). **End SHA:** one narrow
  Phase 0A.1 commit on top; read it with `git log -1` and compare with `git ls-remote origin feature/v0.2.0`. No merge,
  tag, release, `main` change or version bump.
- **User M03 first run (2026-11-17, Developer Mode off):**
  - Setup succeeded with 21 icons.
  - One folder: the correct 21 of 21 result.
  - Five folders: the correct result, no error.
  - The Phase 0B menus still worked.
  - **A large Windows PowerShell terminal window appeared behind the Repair result dialog.**
  - Classification: Repair's function is **provisionally successful**; the launcher visibility is a defect, now
    remediated in automation, and **needs a manual retest**.
- **Root cause (ADR 022, isolated probes):**
  - The verb ran `powershell.exe -WindowStyle Hidden` directly, in both modes.
  - Windows handed that console to Windows Terminal (a new window, 1129 x 635, about 1.1 s after launch) before
    PowerShell could hide it.
  - Windows Terminal then only minimized the window, which stayed for the whole process lifetime, including the dialog.
  - The same command started hidden at creation (SW_HIDE, as the VBS launcher does) produced no window.
  - Uninstall had the same shape; its cleanup helper was already hidden at creation.
- **Remediation (Phase 0A.1):**
  - `PortableFolderIcons.Integration.ps1`: normal mode registers Repair and Uninstall as `"<SystemRoot>\System32\wscript.exe"
    "<runtime>\Invoke-PortableFolderIcons.Hidden.vbs" -Action <Action>`. Developer Mode keeps the direct command.
  - `Invoke-PortableFolderIcons.Hidden.vbs`:
    - Accepts exactly `-Action Repair|Uninstall`, runs the dispatcher with window style 0, waits, and returns its
      exit code.
    - Shows one guided Error dialog for a missing dispatcher, a PowerShell start failure, or an exit code outside 0..3.
    - Test seam as in ADR 021.
  - **Unchanged:** broker binaries and source, CLSID, verb keys and command identities, Apply/Reset/selection
    dispatch, registry ownership, Setup's double-click flow, Uninstall's prompts and removal, and the Phase 0B
    two-entry menu (still the working fallback).
- **Not implemented, not authorized:** the single top-level Folder Icons menu.
  - ADR 019 stays pending the user's final picker-architecture approval.
  - ADR 020 and the root complete uninstaller stay deferred to Phase 7.
- **Last verification:**
  - Standalone `c-0010` on the final source: 126 passed, 0 failed (was 84); the run folder was removed.
  - **Full gate `20261117T162252Z-a40c50`** (2026-11-17, 578 s, on `3170d8f` plus the uncommitted Phase 0A.1 tree;
    inputs `c66c4230ac5ca891`, unchanged during the run):
    - Overall **BLOCKED**, not PASS; no FAIL.
    - PASS: path-budget, platform-scope, structure, docs, `c-0001` (580 passed, 0 failed, 1 blocked: harness launch
      owned by `c-0002`), `c-0003` (97 passed, 14 findings), `c-0005`, `c-0006`, `c-0007` (145), `c-0008` (41),
      `c-0009` (111) and `c-0010` (126, 0 failed).
    - `c-0002` BLOCKED_BY_ENDPOINT_SECURITY: withheld, with cached x64 `0a71577b…` and x86 `4f589ac4…` not launched.
    - `c-0004` NOT RUN (opt-in).
    - Coverage: 15 of 16 required items; PFI-017 satisfied; PFI-006 is blocked only through `c-0002`.
    - Agent review: no Critical, High or Medium findings. Three Low items: the unparsable-dispatcher residual,
      pre-existing `%VAR%` expansion by `WshShell.Run`, and the observer's 100 ms polling.
    - The run folder was removed after this record. The only later edits before the commit are this record and the
      housekeeping it describes.
- **Manual gates:** M03 retest **PENDING** (Setup first; then one folder, five folders, optional declined Uninstall;
  checklist in `MANUAL-GATES.md`). M02 and M04 remain pending.
- **Security:**
  - No new executable, hook, DLL or service.
  - The deleted W1 script was not recreated or run.
  - The gate now also starts inbox `wscript.exe`, only on the launcher of disposable install copies; no block was
    observed.
- **Exact next action:** stop for user review.
  - The user reruns `Setup_and_Run-Portable-Folder-Icons.bat`, then the M03 retest.
  - Recommended next work, only after the user approves ADR 019: design the one-entry Folder Icons menu with option C
    (Reset to Default, Repair, Choose Folder Icon… opening an out-of-process picker). It needs a broker rebuild and an
    endpoint-security plan.
- **Retained evidence (unchanged, each with a RETAIN.md):** `outputs/experiment-single-menu/`, `outputs/manual/`,
  `outputs/retained-phase0-preedit/`, `files/backups/*`, `cache/native-harness/`.

## Snapshot — 2026-11-17 (Phase 0A Repair reliability) — Claude Code (superseded by the snapshot above)

- **Machine and branch:** the original Windows 11 PC (build 26200, Windows PowerShell 5.1), branch `feature/v0.2.0`.
- **Start SHA:** `0459c9e457fa866b6bf51b4f6a76963193e3715b` (`docs: record P1 wheel results, W1 security block and menu
  recommendation`, parent `496b508`). The user-authorized publication pushed `feature/v0.2.0` to `origin` at
  `0459c9e` before this assignment, and the remote SHA was verified. `origin/main` is unchanged at `6cb6bae`.
- **End SHA:** this snapshot is written just before the one narrow Phase 0A commit on top of `0459c9e`, labelled
  pending M03. Read the new SHA with `git log -1` and compare it with `git ls-remote origin feature/v0.2.0`. No merge,
  tag, release, `main` change or version bump.
- **Scope delivered (Redesign Phase 0A only; ADR 021; plan "Phase 0A outcome"):**
  - Runtime: `scripts/Windows/Invoke-PortableFolderIcons.ps1` and `PortableFolderIcons.Maintenance.ps1`.
  - Tests: new gate check `c-0010` (`tests/Test-PfiMaintenanceReliability.ps1`), updated `c-0003` D3 section and
    `files/tests/Invoke-Tests.ps1`.
  - Gate registration: `checks.tsv`, `coverage.tsv` (PFI-007 updated; PFI-015, PFI-016 added), `GATE.md` and
    `MANUAL-GATES.md` (M03 checklist).
  - Not changed: the broker, its contract, the registry shape, Apply/Reset, notification, resources, setup, and
    Uninstall's prompts, ownership, removal policy and cache behaviour.
- **D3 status:**
  - **D3-A (missing or unloadable module): fixed.** One visible Error dialog names the file, says nothing changed and
    names `Setup_and_Run-Portable-Folder-Icons.bat`. This holds in both modes, for Repair and Uninstall; exit 1.
  - **D3-B (missing or corrupt cached icons): fixed with partial recovery.**
    - Every damaged icon is diagnosed and listed as not repaired.
    - The menu is recreated for the verified icons, healthy files are untouched, and nothing is imported.
    - Exit 3, with a Warning dialog.
  - **D3-C (concurrency): fixed for Repair and Uninstall.**
    - One `Local\` per-user, per-install mutex with a 60 s bounded wait; abandoned-lock takeover; release in `finally`.
    - Coalescing gives one dialog for overlapping Repairs.
    - Repair after Uninstall refuses.
  - **D3-D (accurate reporting): fixed.** Every Repair failure names the setup launcher.
  - **Unresolved gates (Open Issue 26):** Setup is not coordinated with the lock, and a missing dispatcher script still
    shows nothing (registry-shape boundary). The real Explorer process and dialog count is M03.
- **X3:** both edited runtime scripts are ASCII-only. The uninstall test-root regex uses `\xC3\xBC`, which matches
  exactly as before. `PortableFolderIcons.Actions.ps1` still has two non-ASCII lines (Phase 9).
- **Last verification:**
  - **Focused gate `20261117T152017Z-fce794`:** `c-0001` 575 passed, 0 failed, 1 blocked (harness launch withheld,
    owned by `c-0002`); `c-0003` 97 passed, 0 failed (14 findings, D3 now only two UNVERIFIED); `c-0010` 84 passed, 0
    failed. Focused mode reports overall BLOCKED by design.
  - **Full gate `20261117T152716Z-f0faff`** (2026-11-17, on `0459c9e` plus the uncommitted Phase 0A tree):
    - Overall **BLOCKED**, not PASS; no FAIL.
    - PASS: path-budget, platform-scope, structure, docs, `c-0001`, `c-0003`, `c-0005`, `c-0006`, `c-0007` (145),
      `c-0008` (41), `c-0009` (111) and `c-0010` (84, 0 failed).
    - `c-0002` BLOCKED_BY_ENDPOINT_SECURITY: withheld, cached builds x64 `0a71577b…` and x86 `4f589ac4…` not launched.
    - `c-0004` NOT RUN (opt-in).
    - Coverage: 14 of 15 required items satisfied; PFI-006 is blocked only through `c-0002`.
    - Agent review: no Critical, High or Low findings; the two remaining items are the UNVERIFIED D3 findings in Open
      Issue 26 and M03.
    - The run folder was removed after this record.
- **Manual gates:** M03 **PENDING** (checklist in `MANUAL-GATES.md`: rerun Setup first, then one folder, five folders,
  dialog count, exact text, console flash, Explorer problems). M02 and M04 remain separate and pending.
- **Security restrictions (unchanged):** W1 is BLOCKED_BY_ENDPOINT_SECURITY (Open Issue 25) and must not be executed.
  No new native executable was launched; the gate only starts inbox `powershell.exe` and reuses the classified harness
  cache without launching it.
- **Exact next action:** stop for user review. The user runs M03. ADR 019 (menu architecture) stays pending and ADR 020
  (complete uninstaller) stays deferred to Phase 7. Do not start Phase 1 or later work, a picker, a menu replacement or
  the complete uninstaller.
- **Retained evidence, each with a RETAIN.md:** `outputs/experiment-single-menu/` (W1 incident), `outputs/manual/`
  (M02–M04), `outputs/retained-phase0-preedit/`, `files/backups/*`, `cache/native-harness/`.

## Snapshot — 2026-11-17 (P1 results, wheel experiment, GitHub publication) — Claude Code (superseded by the snapshot above)

- **Machine and branch:** the original Windows 11 PC (build 26200.9725, Windows PowerShell 5.1), branch
  `feature/v0.2.0`. This snapshot is written just before the user-authorized documentation checkpoint commit on top of
  `496b508` (parent `ddbe65f`), so read the new SHA with `git log -1`.
- **Publication:** the user authorized publishing this branch with a normal push, `git push -u origin feature/v0.2.0`.
  The push carries `ddbe65f`, `496b508` and this checkpoint in their existing ancestry. Before it, remote
  `feature/v0.2.0` did not exist, `origin/feature/v0.1.1` was at `88007c5` and `origin/main` at `6cb6bae`. Check the
  result with `git ls-remote origin`. No merge, release, tag or `main` change; `feature/v0.1.1` is not pushed separately.
- **Pre-publication audit (2026-11-17), unpublished commits `ddbe65f`, `496b508` plus this checkpoint:**
  - **ICOs:** exactly the ten colour ICOs are tracked. No personal ICO, `files/extra-ICO-files-for-use/`, backup, gate
    output or cache appears in any ref's history.
  - **Secrets:** the secret-pattern scan found no hits.
  - **Private details:** the home path and machine name are pre-existing in public `origin/main` (Open Issue 18), and the
    unpublished commits add none.
  - **Broker:** x64 `88a113f1…`, x86 `134832fd…` and source `4dc9ec37…` match `SelectionBroker.build.json` and are
    unchanged since `ddbe65f`.
  - **Working tree:** no tracked file outside `md-instructions/` and `MANUAL-GATES.md` changed.
- **P1 (user, 2026-11-17, isolated popup, not Explorer):**
  - **PASS:** the full inventory sits in one native submenu, the static 16-cap does not apply, all 120 icons are
    reachable with the on-screen scroll arrows, keyboard Up/Down works, and the selections Icon 013/040/035/120 were
    logged.
  - **FAIL:** the mouse wheel does not scroll it.
  - **Not proven:** Explorer, Home/End and access keys, columns at other resolutions and scaling, broker dispatch from a
    dynamic handler, WatchGuard acceptance of a new extension.
  - Not a complete PASS.
- **W1 (Claude, isolated, synthetic input):**
  - Wheel messages reach the menu's modal loop (thread-local `WH_MSGFILTER`, `MSGF_MENU`), and the default loop ignores
    them.
  - Consuming them and posting Up/Down key messages scrolls the menu by moving the selection, with clamping and no wrap.
  - No documented API scrolls a popup menu. In Explorer this would need option B's in-process DLL plus a hook on
    Explorer's UI thread.
  - Measured on 1920×1080: 45 icons fit, 120 icons need arrows (47 of 123 rows visible), 120 icons in 4 columns of 30
    fit.
- **Security incident: W1 is BLOCKED_BY_ENDPOINT_SECURITY (Open Issue 25).**
  - **Detection:** WatchGuard Endpoint Security 360 deleted `Test-MenuWheelFeasibility.ps1` as "Malware or potentially
    unwanted program (PUP)" at about 08:29 (local quarantine record `7b16cb86-…`, 08:29:36). The console incident ID is
    not available locally.
  - **Handling:** nothing was recreated or worked around. No experiment process or hook remains, and Explorer, the
    registry and production were untouched.
  - **Cause:** design and trigger analysis (evidence vs speculation) are in the plan section "P1 user results and
    mouse-wheel experiment W1".
- **Recommendation (user decision; nothing implemented):**
  - C: Folder Icons ▸ Reset to Default, Repair Portable Folder Icons, Choose Folder Icon…, which opens an out-of-process
    picker with the complete list (wheel, keyboard, type-to-find).
  - D if quick native access to 12 icons matters.
  - A (Phase 0B) stays the fallback.
  - Not B with a wheel hook: it needs code and a hook inside Explorer, and W1 shows the technique draws an endpoint
    detection.
  - A native menu with arrows but no wheel is a fallback only.
- **Final menu (reconciled; ADR 019/020):** Reset to Default, Repair Portable Folder Icons, Choose Folder Icon. No
  Uninstall in the menu. Complete removal only through a root `Uninstall-Portable-Folder-Icons.bat`, deferred until
  ownership tracking and safe restoration are reliable (Phase 7).
- **Last verification:** focused gate `20261117T143621Z-f303a2` (2026-11-17, Windows PowerShell 5.1) on HEAD `496b508`
  plus this checkpoint's staged documentation, result PASS.
  - **`c-0005`:** exactly the ten tracked colour ICOs, and no personal ICO staged.
  - **`c-0006`:** project verifier exit 0 with 561 passed, 0 failed and 1 harness launch withheld (owned by `c-0002`).
  - **Also:** `git diff --check` was clean.
  - **Not re-run:** the full gate. The last full gate is `20261117T132259Z-427c89`, BLOCKED only by the withheld
    `c-0002`, and only documentation has changed since.
  - The only later edit before the commit is this line. The run folder was removed after this record.
- **Decisions for the user and security owner:**
  1. The menu architecture: C, D, B (in-process plus security review) or keep A.
  2. Close the W1 incident in the WatchGuard console, and say whether any hook experiment may ever be authorized
     (exact implementation).
  3. Classify the harness builds x64 `0a71577b…` and x86 `4f589ac4…` (unchanged blocker).
  4. Confirm `outputs/retained-phase0-preedit/`.
  5. Manual gates M02–M04.
- **Exact next action:** stop for user review. Phase 0A (Repair) remains the next functional phase and is not started.
  No Explorer extension, production menu change or uninstaller work.
- **Retained evidence, each with a RETAIN.md:**
  - `outputs/experiment-single-menu/`: the P1 script, the W1 log and two captures, kept for the incident and decision.
  - `outputs/manual/`: M02–M04.
  - `outputs/retained-phase0-preedit/`.
  - `files/backups/*`.
  - `cache/native-harness/`.

## Snapshot — 2026-11-17 (later) — Claude Code — single-menu feasibility and uninstaller requirement (superseded by the snapshot above)

- **Branch/HEAD:** `feature/v0.2.0` at `496b50808498ade7086ce6479e2a623609ba1629`
  (`feat: restore accessible folder icon menus (Phase 0B)`, parent `ddbe65f`). This is the one commit the user
  authorized, made after the full gate below. Local only: no push, merge, tag, release or `main` change.
- **Uncommitted, needs the user's review before any commit:** ADR 019 and ADR 020 in `md-instructions/Decisions.md`,
  the plan (final-UX invariant, branch row, the section "Final menu UX requirement and single-menu feasibility", the
  Phase 7 "Dedicated complete uninstaller" amendment, a Phase 8 note) and this Handoff. Personal ICOs remain untracked
  and untouched.
- **Final UX requirement (user, 2026-11-17; ADR 019/020):**
  - One top-level **Folder Icons** entry with Reset to Default, Repair and Choose Folder Icon, holding one complete
    icon list that the mouse wheel and the keyboard can scroll. A native submenu is strongly preferred.
  - No Uninstall in the menu. Complete removal only through a root `Uninstall-Portable-Folder-Icons.bat` (Phase 7,
    reconciled).
  - Phase 0B's two-entry layout is the working fallback, not the final design.
- **Feasibility result (plan section, ADR 019):**
  - Static registration cannot give one complete list: the 16-entry cap was re-measured.
  - Experiment E1 (isolated `SHCreateDefaultContextMenu` with an in-process callback, not Explorer) kept all items of
    one dynamically inserted submenu from 0 to 300 icons, with column breaks intact. The cap is specific to static
    cascades.
  - A single native submenu therefore needs a new **in-process Explorer extension**: IContextMenu or IExplorerCommand,
    both documented as in-process only. That conflicts with ADR 002, ADR 005 and the plan invariants. Microsoft does
    not support managed in-process extensions, no native toolchain is installed here, and a new DLL inside Explorer
    needs WatchGuard classification or signing.
  - Wheel scrolling of tall native popup menus is unverified, and developer forums report that it does not work.
  - The broker is plausibly reusable unchanged.
  - Nothing was registered, installed or invoked.
  - Deviation: E1's first run (no registry keys) made DefCM load the machine's installed context-menu handlers into the
    test PowerShell process, read-only `QueryContextMenu` only. The run was corrected and `c-0009` is unaffected.
- **Uninstaller (ADR 020, plan Phase 7 amendment):** requirement recorded, not implemented. No PC-wide scan, no real
  folder touched, production installation untouched.
- **Decisions requested from the user:**
  1. Optionally run probe P1 (command in `outputs/experiment-single-menu/RETAIN.md`) and report the wheel, scroll-arrow
     and keyboard results.
  2. Approve or decline a bounded menu-architecture proof that needs an in-process exception. If approved, also choose
     native C++ (toolchain install) or managed C# (unsupported), arrange WatchGuard classification or signing, and
     accept a test DLL that Explorer may keep loaded until sign-out.
  3. Otherwise choose C (picker) or D (hybrid), each needing a broker rebuild, or keep A.
  4. Authorize, or not, a commit of this session's documentation.
- **Last verification:** unchanged since the commit. Full gate `20261117T132259Z-427c89` on the pre-commit tree (see
  the previous snapshot): BLOCKED only by the withheld `c-0002`, no FAIL. After the commit, only documentation and
  ignored experiment files changed. The focused documentation check result is in the work log entry for 2026-11-17
  (later).
- **Exact next action:** stop for user review. Do not implement the menu architecture, the uninstaller or Phase 0A
  until the user decides. Phase 0A (Repair) remains the next functional phase.
- **Retained evidence:**
  - `outputs/experiment-single-menu/` (probe P1 pending; RETAIN.md)
  - `outputs/manual/` (M02–M04 pending)
  - `outputs/retained-phase0-preedit/` (awaiting the user's confirmation)
  - `files/backups/*`
  - `cache/native-harness/`

  Gate runs `20261116T192101Z-bc73ec` and `20261117T132259Z-427c89` were removed after being recorded. No test registry
  keys are left.

## Snapshot — 2026-11-17 — Claude Code — Phase 0B checkpoint after manual M01 PASS (superseded by the snapshot above)

- **Branch/HEAD:** `feature/v0.2.0` (created 2026-11-16 from `ddbe65f`, the Phase 0 checkpoint; local `feature/v0.1.1`
  is also `ddbe65f`, one ahead of `origin` at `88007c5`). This snapshot is written just before the one user-authorized
  local Phase 0B commit on top of `ddbe65f` (a commit cannot contain its own SHA; read it with `git log -1`). No push,
  merge, tag, release or remote-ref change (`git ls-remote` only).
- **Phase 0B (ADR 015 and its implementation follow-up; plan "Phase 0B outcome"):** product change only in
  `scripts/Windows/PortableFolderIcons.Integration.ps1`. One budget constant (16). **Folder Icons** lists Reset,
  Repair, Uninstall, a separator, then **Choose Folder Icon** with the first 12 icons; further icons go to top-level
  entries **Folder Icons (First–Last)** of at most 16 (`Directory\shell\PortableFolderIcons.More.NN` →
  `PortableFolderIcons.ContextMenu.IconChoices.MoreNN`), reconciled by exact name on setup/Repair and removed by
  Uninstall. Apply/Reset identities, broker, binaries, installer flow and versions (0.1.1) unchanged.
- **Manual tests:** **M01 PASS (user, 2026-11-16)** after rerunning setup: utilities visible, chooser and all nine
  icons of **Folder Icons (Purple–Yellow)** reachable, Blue and Teal applied, no duplicate or stale entries (M01 was FAIL
  before Phase 0B). The live installation was verified byte-identical to this tree on 2026-11-17 (runtime and broker;
  read only). **The user does not accept the two-entry layout as the final design**: the preferred design is one
  top-level Folder Icons entry with one complete, scrollable icon list. Phase 0B is the working fallback. M02–M04
  pending.
- **Claude portability (ADR 018):** confirmed — a fresh session on 2026-11-17 loaded the root `CLAUDE.md` and, through
  it, `AGENTS.md` at startup.
- **Last verification:** full gate `20261117T132259Z-427c89` (2026-11-17, Windows PowerShell 5.1, 386 s) on the
  pre-commit tree, inputs `8feaafbab9ef461c`, `changed_during_run` false, `git diff --check` clean. Exit 2 BLOCKED
  only because `c-0002` is withheld (BLOCKED_BY_ENDPOINT_SECURITY, cache hits x64 `0a71577b…`, x86 `4f589ac4…`, not
  launched) and coverage PFI-006 waits for it (12/13); `c-0004` NOT RUN (no opt-in). PASS: path-budget, structure,
  docs, `c-0001` (561 passed, 0 failed, 1 blocked), `c-0003` (87 passed, 21 findings), `c-0005`, `c-0006`, `c-0007`
  (145), `c-0008` (41), `c-0009` (111, 0 test keys left). The only later edit before the commit is this line. The run
  folder was removed after this record.
- **Still open, not fixed by restoring visibility:** D2 Reset rendering (M02), ANSI `desktop.ini` corruption (14),
  Reset ReadOnly ownership and third-party icon removal (15); D3 Repair defects (11) → Phase 0A; D4 purge → Phase 7;
  X3 BOM-less scripts with non-ASCII literals.
- **Blocker (unchanged):** security owner decision on harness builds x64 `0a71577b…`, x86 `4f589ac4…` (cache hits;
  no new build; never launched).
- **Exact next action:** after this commit, the user-requested bounded feasibility investigation of a single native
  Explorer submenu (no architecture change), then stop for user review. Phase 0A (Repair) remains the next functional
  phase and is not started.
- **Committed paths (never personal ICOs or `files/extra-ICO-files-for-use/`):** `CLAUDE.md`,
  `scripts/Windows/PortableFolderIcons.Integration.ps1`, `scripts/verify.ps1`, `files/tests/Invoke-Tests.ps1`,
  `files/dev-work/verification-gate/{checks.tsv,coverage.tsv,GATE.md,MANUAL-GATES.md}`,
  `files/dev-work/verification-gate/tests/{Invoke-Phase0Diagnostics.ps1,Test-PfiStaticCascadeMenu.ps1}`,
  `md-instructions/{Briefing,Changelog,Decisions,Handoff,Portable-Folder-Icons-v0.2.0-Implementation-Plan}.md`.
- **Retained evidence:** `outputs/manual/` (M02–M04 pending), `outputs/retained-phase0-preedit/` (awaiting the user's
  confirmation), `files/backups/*`, `cache/native-harness/`. Gate run folders are removed once recorded here.

## Snapshot — 2026-11-16 — Claude Code — authorized Phase 0 checkpoint (superseded by the snapshot above)

- **Branch:** `feature/v0.1.1`. This snapshot is written just before the one user-authorized local checkpoint commit
  on top of `88007c5` (the commit cannot contain its own SHA; read it with `git log -1`). No push, merge, tag, release
  or branch creation. Production installation and HKCU registration read only.
- **Checkpoint content:** the recovered v0.1.1 Phase 2 implementation (COM selection broker source, build manifest,
  x64/x86 binaries, payload reader, batch Apply/Reset), tests, the Phase 0 verification gate (`c-0001`…`c-0008`),
  root `AGENTS.md`, permanent docs, the active v0.2.0 plan and the archived v0.1.1 plan: 18 modified, 28 added,
  1 moved. Excluded: all personal and extra ICOs, logs, outputs, snapshots, the harness cache, machine-local files.
  It carries the **October** Phase 2 manual Explorer PASS only; **M01 is FAIL** (2026-11-16) pending Phase 0B, and the
  native harness remains **BLOCKED_BY_ENDPOINT_SECURITY**. A recovery/development checkpoint, not a release.
- **This session:** every verification entrypoint now withholds compiled-harness launches unless explicitly
  authorized (`-AllowNativeHarness` or `PFI_GATE_NATIVE_HARNESS=allow`; ADR 014 follow-up). Permanent
  development-artifact housekeeping rule added to root `AGENTS.md` (ADR 017) with the gate helper
  `helpers/Remove-GateOutputs.ps1` and safeguard check `c-0008`.
- **Last verification:** `files\dev-work\verification-gate\verify.ps1 --mode full`, run `20261116T180132Z-dcf16e`
  (pre-commit tree; Windows only; no opt-ins): **BLOCKED**, no FAIL. PASS c-0001 (370, harness withheld by default,
  0 launches), c-0003 (83), c-0005, c-0006 (0 failures; LICENSE, AGENTS.md, eol=lf, root layout, housekeeping docs),
  c-0007 (145), c-0008 (41); c-0002 BLOCKED_BY_ENDPOINT_SECURITY (withheld; cache hits); c-0004 NOT RUN. Coverage
  11/12 required (PFI-006 waits for the security decision).
- **Post-checkpoint housekeeping (done after commit `ddbe65f` was verified; this note is uncommitted):** removed 15
  gate output folders (all 13 runs, `phase0-20261116/`, `phase0-final-20261116/`; 69.2 MB via
  `helpers/Remove-GateOutputs.ps1 -Apply`) and 29 items from `files/test-logs/` and `files/temp/` (5.4 MB, including
  the superseded harness builds `35482483…`/`b2eaad08…` and August research builds). **Retained, each with a
  `RETAIN.md`:** `outputs/manual/` (pending manual gates M01 retest, M02–M04); `outputs/retained-phase0-preedit/`
  (218 KB: the 10 snapshot files with no other copy, i.e. pre-Phase-0 versions of 8 project files plus the old
  `.claude/CLAUDE.md` and `.codex/CODEX.md`; remove when the user confirms they are not needed);
  `files/backups/phase2-installed-*` (October install backup; not reproducible from Git); `files/backups/20260728-*`
  (your prototype registry keys and an original `desktop.ini`). Also kept: `outputs/verify-state.json` (runner status
  index), `files/SetFolderColor.log` (pre-project log of your own tool), `cache/native-harness/` (WatchGuard
  classification). Clean-checkout checks of `ddbe65f` (git archive, and a `core.autocrlf=true` clone): setup exit 0,
  10 icons, broker `88a113f1…`.
- **Blockers:** (1) security owner decision on the cached harness builds x64 `0a71577b…` and x86 `4f589ac4…`
  (WatchGuard enabled; never launched); (2) M01 FAIL until Phase 0B.
- **Exact next action:** Phase 0B (static-menu correction per the plan), on explicit user instruction.

## Snapshot — 2026-11-16 (evening) — Claude Code — Phase 0 final reconciliation (superseded)

Local evidence paths cited in this and older sections (`files/dev-work/verification-gate/outputs/phase0-*`,
run folders, `files/test-logs/*`, `files/temp/*`) were removed in the post-checkpoint housekeeping; their results are
recorded in this file, the plan and `GATE.md`, and the code is in Git.

- **Branch/HEAD:** `feature/v0.1.1` @ `88007c5` (unchanged). No commit, stage, push, branch, fetch, stash, reset or
  restore. Production installation and HKCU registration read only (installed runtime = working tree).
- **Status:** Phase 0 checkpoint-ready for user review. LICENSE restored (no Git diff; B-001/B-002 retired). Harness
  built once per input set and reused (`files/dev-work/verification-gate/cache/native-harness/`), launch outcomes
  classified, `c-0004` stderr defect fixed, regression check `c-0007` added. Broker `.cs` pinned to LF in
  `.gitattributes` (a fresh `core.autocrlf=true` clone otherwise made setup reject the broker). Active plan moved to
  `md-instructions/Portable-Folder-Icons-v0.2.0-Implementation-Plan.md`; Phase 0B design recorded there (ADR 015).
- **Last verification:** `files\dev-work\verification-gate\verify.ps1 --mode full`, run `20261116T171928Z-53a5e6`,
  Windows only, no opt-ins: **BLOCKED** (no FAIL). PASS c-0001 (370 + 1 withheld), c-0003 (83), c-0005, c-0006 (0
  failures), c-0007 (131); c-0002 BLOCKED_BY_ENDPOINT_SECURITY (withheld; cached x64 `0a71577b…`, x86 `4f589ac4…`,
  never launched); c-0004 NOT RUN. `agent-review.md` in that run.
- **Checkpoint manifest (proposed, not staged):** 18 modified, 25 added, 1 moved (v0.1.1 plan to
  `files/plans/legacy-plan/`); excludes all personal/extra ICOs, logs, snapshots, cache, outputs. Exact list:
  ignored `files/dev-work/verification-gate/outputs/phase0-final-20261116/checkpoint-manifest.tsv`; a tree rebuilt from
  it alone installs (10 icons, `-SkipRegistry`), passes `scripts/verify.ps1` (0 failures) and rebuilds the broker from
  source (`EVIDENCE.md` there).
- **Blockers:** (1) security owner decision on the two cached harness builds (WatchGuard enabled; nothing launched);
  (2) M01 FAIL until Phase 0B.
- **Exact next action:** user review, then (if authorized) the baseline checkpoint commit from that manifest, then
  implement Phase 0B per the plan. Not started.

## Snapshot — 2026-11-16 — Claude Code — Phase 0 baseline recovery (superseded by the snapshot above)

- **Machine:** this Windows 11 workspace (Windows PowerShell 5.1.26100.9711). **Branch/HEAD:** `feature/v0.1.1` @ `88007c5`;
  local `main`/`feature/v0.1.1` equal `origin` (`git ls-remote`, read-only); no `feature/v0.2.0` anywhere.
  No commit, push, branch, fetch, stash, reset or restore was performed.
- **Status:** Phase 0 complete at the review checkpoint. The uncommitted Phase 2 broker/batch implementation is
  present, is the most complete implementation, and is byte-identical to the installed runtime and installed
  x64 broker (not to HEAD). The October manual Explorer PASS (user-reported) applies to that configuration; it
  was not re-run. Pre-edit snapshot: ignored `files/dev-work/verification-gate/outputs/phase0-20261116/snapshot/`
  (78 files with SHA-256 inventory, binary-safe `git/worktree-vs-HEAD.patch`, recovery steps in its README).
- **Active plan (then at, now moved to `md-instructions/`):** `files/plans/Portable-Folder-Icons-v0.2.0-Implementation-Plan.md` (amended; see its
  "Phase 0 outcome", "Defect register", "Branch, version and checkpoint policy" and "Plan reconciliation").
- **Last verification:** gate `files\dev-work\verification-gate\verify.ps1 --mode full`, run
  `20261116T154150Z-355cda` (inputs unchanged during run; `agent-review.md` in its folder), Windows only.
  Result **FAIL** (not PASS): suite 370 passed + 1 withheld; C# harness
  `BLOCKED_BY_ENDPOINT_SECURITY`; Phase 0 diagnostics 83/83; public inventory PASS; `scripts/verify.ps1` FAILs
  only on BASELINE B-001/B-002 (`LICENSE` renamed to `LICENSE.LICENSE` in the working tree, identical text).
- **Blockers for the user:** (1) WatchGuard Endpoint Security blocked the compiled test harness
  `SelectionBrokerHarness.x64.exe` (see Open Issue 9 and `files/dev-work/verification-gate/GATE.md` for the
  security-review evidence); (2) the `LICENSE` rename (user's change; not touched).
- **Manual tests:** **M01 FAIL** (user, 2026-11-16 after rerunning setup; `outputs/manual/2026-11-16-results.md`):
  the chooser shows only `ai`–`react`, and Reset/Repair/Uninstall are missing (D1, D5). M02–M04 pending
  (`files/dev-work/verification-gate/MANUAL-GATES.md`).
- **D1/D5 cause (established, isolated reproduction):** the Shell's static-menu builder includes at most 16
  entries per top-level static cascade, counted depth-first across nested submenus in key order. Registry is
  correct and unchanged. Probe: `files/dev-work/verification-gate/tests/Test-PfiStaticCascadeMenu.ps1`, evidence
  `outputs/phase0-20261116/diagnostics/menu-probe-3/`.
- **WatchGuard (afternoon):** the classified harness `35482483…` was never re-run. The opt-in `c-0002` run rebuilt
  it as `b2eaad08…`, which was blocked again. The cause on the project side is a rebuild on every run: the
  non-deterministic compiler changes only the timestamp and MVID. `c-0002` stays BLOCKED_BY_ENDPOINT_SECURITY.
- **Exact next action:** user review. Recommended next task (not started): plan "Redesign Phase 0B — Menu entry
  budget", after the checkpoint commit authorized per the plan's checkpoint policy; Phase 0A (Repair) follows.

### Phase 0 findings (detail in the plan's Defect register and gate check `c-0003`)

- **Chooser (D1):** discovery → manifest → cache → registration → ordering → dispatch identity all correct
  (3/21/45/120 synthetic icons; live install 21 verbs = 21 accepted, no stale entries). All icons sit in one
  unbounded cascade; classic menus scroll only by arrows/keyboard. Overflow at 21 icons not reproduced on this
  display (estimate ~43 rows). Actual overflow: manual M01.
- **Reset (D2):** persisted state and fresh-process Shell resolution return to the never-customized default in
  every standard case. Not reproduced at those layers; rendering needs M02. Found: ANSI `desktop.ini` non-ASCII
  text is corrupted; Reset does not restore original folder ReadOnly ownership; Reset removes third-party icons.
- **Repair (D3):** confirmed source defects: no "rerun Setup_and_Run" guidance in any failure; one bad cached icon
  blocks all re-registration; missing runtime module fails invisibly (hidden console, before try/catch);
  concurrent re-registration races (reproduced in isolated registry roots). Static `Player` verbs may start one
  Repair per selected folder (M03).
- **Uninstall (D4):** removes runtime/state/manifest/settings/registration, preserves cache and applied
  resources; optional purge prompt is the legacy warned purge.
- **Inputs:** setup reads only `files/ICO-Files`; `files/extra-ICO-files-for-use/` is not read. 11 personal ICOs
  are untracked copies in `files/ICO-Files`; gate check `c-0005` fails if any is staged.
- **Test counts vs October:** PowerShell 371 = 371. C# 358 vs 350: +8 from two more registered icons
  (`Folder_GitHub.ico`, `vscode.ico`; 4 assertions per contract), not a test change.

### Superseded October state (kept for history)

The "Exact next action" below (obtain Phase 2 manual results) is superseded: the user reported the Phase 2
manual Explorer acceptance as PASSED in October.

## Current Focus (2026-10-01, historical)

v0.1.0 is formally complete. Local `main`, `origin/main`, annotated tag
`v0.1.0`, and the GitHub release all identify verified release commit
`6cb6bae`. The exact commit passed 265 deterministic assertions and all release
gates under Windows PowerShell 5.1.

Phase 2 automated checkpoint on 2026-10-01. Branch: `feature/v0.1.1`; HEAD and the local
`origin/feature/v0.1.1` reference are `88007c5`. No fetch, commit, push, merge,
tag, or release was performed. The active v0.1.1
implementation plan remains in place.

### Reconstructed committed state

- `d6b27b9` (`feat: baseline v0.1.1 scalable icon chooser`) starts from
  released `6cb6bae`. Its eleven-file change advances version metadata to
  0.1.1, adds the active plan and ADR 011, separates alphabetical Apply verbs
  into the dynamic **Choose Folder Icon** child cascade, retains Reset,
  Repair, and Uninstall in the short parent, extends exact registry ownership
  and cleanup, and adds zero/one/ten/current/30/50 inventory coverage.
- The entire exclusive range `d6b27b9..88007c5` contains just `88007c5`
  (`docs: record multi-selection architecture gate`). It changes only this
  Handoff: 33 insertions and one deletion. It records the transport research,
  rejection of command-line/timed-queue aggregation, and the COM architecture
  approval gate. It adds no runtime code, tests, binaries, or assets.
- Thus HEAD contains completed Phase 1 and Phase 2 research only. HEAD still
  uses single-selection static commands. SelectionHandler, SelectionBroker,
  the payload reader, and the broker harness are absent from HEAD and from
  this commit range. Their presence locally must not be described as committed.

### Preserved local Phase 2 implementation

The worktree contains nine pre-existing modified runtime/test files plus
untracked `PortableFolderIcons.Selection.ps1`, `SelectionBrokerHarness.cs`, and
`scripts/Windows/SelectionHandler/` (C# source, developer build script, x64/x86
EXEs, and build manifest). The user's Phase 2 continuation directive authorizes
the narrow Reset contract fix, verifier reconciliation, and automated runtime
exercise. That work is now completed locally, with no staging or commit.
Earlier implementation provenance is still absent from history; the full Phase 2
checkpoint remains uncommitted pending manual Explorer acceptance.

The local architecture is a compiled .NET Framework COM **local server**, not
an in-process Explorer DLL. The classic static cascade remains. Apply and
Reset use `MultiSelectModel=Player` and `DelegateExecute` with shared CLSID
`{10DE6C30-6CD5-4B62-BCFA-18DD3687C531}` registered beneath the exact owned
HKCU `Software\Classes\CLSID` key with `LocalServer32`/`ServerExecutable`.
Repair and Uninstall retain installed PowerShell commands.

`SelectionCommand` implements `IInitializeCommand` (verb name plus
`PfiAction`/`PfiIconHash`), `IObjectWithSelection` (`IShellItemArray`), and
`IExecuteCommand`. It enumerates filesystem paths in Shell array order,
preserving occurrences without sorting, deduplication, or a project selection
cap. It writes one GUID-named UTF-8 JSON request atomically under installed
`state\requests`, then launches one dispatcher using only the token and
payload SHA-256. There is no per-item launch aggregation or timed queue.
Normal mode uses the windowless WSH bridge; Developer Mode starts visible
PowerShell. The COM server requests exit after dispatch; this exit is now
confirmed by the installed COM smoke test, while Explorer-originated invocation
and UI still need manual validation.

The PowerShell payload reader checks token/path scope, reparse status, hash,
schema, exact fields, action/icon identity, timestamp (15-minute age bound),
and non-empty paths. The dispatcher removes the request in `finally` and runs
Apply/Reset sequentially through `Invoke-PfiBatchAction`, recording each
success, failure, rejection, and refresh warning without rolling back unrelated
successes. Normal all-success stays silent; otherwise one scrollable aggregate
result is shown. Each operation retains the existing targeted refresh; there
is no new delayed retry or parent deduplication. Opportunistic stale-request
cleanup is limited to recognized request names older than one day.

Setup stages the OS-appropriate broker as installed
`runtime\SelectionHandler\PortableFolderIcons.SelectionBroker.exe` and its
build manifest. Validation checks source/artifact SHA-256, PE machine type,
and assembly identity/version `0.1.1.0`; hashes do not establish signing or
publication approval. Repair validates the broker and recreates registration;
Uninstall guards COM ownership and removes request state with the runtime,
preserving cached icons by default. Setup also has new activation flags for
filesystem rollback. The automated checkpoint passes locally; manual acceptance
and the Git checkpoint remain pending.

### Canonical Reset identity and current verification

The mismatch occurred because registration supplied `Utility_0100_Reset` while
the broker validated the unrelated name `PortableFolderIcons.Reset`. Microsoft
defines `IInitializeCommand`'s name as the registry verb key's name. Kept the
existing ordered utility key as the canonical contract: PowerShell
`PfiResetVerbName` and C# `ResetCommandName` both mean `Utility_0100_Reset`.
`PfiAction`, JSON request action, and dispatcher action remain `Reset`; no
payload schema change or legacy alias is needed. Both modes use this identical
contract. Apply identities remain `PortableFolderIcons.Apply.NNNN` plus their
registered icon hash.

The C# harness reads registration-derived names/properties, invokes actual
`Initialize`/`IPropertyBag` reads, and checks the production validator. It covers
every registered Apply and Reset, the obsolete Reset name, Reset with an icon
hash, action/name confusion, malformed Apply hash, and the prior >100 ordered
occurrence seam. The full suite derives contracts from actual isolated HKCU
registration; the focused runner derives them from the generated registry plan
and executes both x64 and x86 processes. Native initialization review also
corrected the fixed 16-byte VARIANT buffer to the native 24-byte x64 / 16-byte
x86 union layout, with a size assertion in both processes. Both EXEs and the
build manifest were rebuilt; source and binary identity checks pass.

Focused tests ran first, followed by the authoritative Windows PowerShell 5.1
command:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify.ps1
```

- Worktree: **371 PowerShell assertions passed, zero failed**. The C# harness
  separately reports **350 assertions passed**, including ordered enumeration
  of 126 synthetic occurrences and all 20 registered Apply/Reset contracts.
  Focused x64 and x86 runs each pass the same **350** assertions.
  All **19 local ICOs** validate, all ten shipped PowerShell scripts parse,
  both broker artifacts validate, and `git diff --check` passes.
- Overall worktree gate: **PASS, exit 0**. The stale root contract omitted the
  workspace's `.ai/` guidance and the map generated by the already-ignored
  `Map-Repo-Structure.bat`. Added exact ignore rules for `.ai/` and root
  `/REPO-STRUCTURE.md`; verifier recognizes only these explicit developer
  artifacts and requires them to remain ignored and untracked. Unexpected
  root items still fail. Neither artifact was moved or modified. Required-file
  coverage includes the broker/payload/tests, both artifact identities are
  checked, and nested C# source is included in the production security scan.
- An isolated `git archive` of `88007c5`, containing only committed files and
  ten committed ICOs, passes the gate: **292 assertions, zero failed;
  RESULT: PASS, exit 0** (prior re-orientation evidence). Verification uses Windows PowerShell
  `5.1.26100.9278`. The archive gate's Git whitespace check uses the enclosing
  repository; its runtime, tests, docs, and ICOs come from the exact HEAD tree.
- Installed setup: **PASS**, discovered/accepted/reused 19, copied/rejected 0;
  normal mode (`developer_mode=false`) remains installed. Backed up the prior
  runtime, manifest, settings, and four exact owned registry roots under
  ignored `files/backups/phase2-installed-7f4b4b1cada64dc2902ef009ad6b95ca/`.
  The corrected x64 runtime and menu remain installed for manual acceptance.
- Actual installed x64 COM exercise: **PASS**, six filesystem outcomes from
  Apply, Reset, and repeat Reset on two fresh repository-owned folders,
  including Unicode and `% ! & ( )`/apostrophe characters. The client reads
  installed verb names/action/hash/DelegateExecute, uses `CoCreateInstance`,
  supplies a real Shell-created `IShellItemArray`, and calls the remote
  `Initialize`, `SetSelection`, and `Execute`. It does not bypass the broker
  or inject a handcrafted request. Registered icon SHA-256 and preserved
  unrelated INI fields/sections are checked. Requests are consumed and the
  COM broker exits after each invocation. No non-fixture folder was targeted.
  This does not establish Explorer menu behavior or x86 local-server activation.

Evidence is preserved locally under ignored
`files/test-logs/reorientation-2026-10-01/` (`verify-worktree.log`,
`verify-HEAD.log`, `verify-final.log` after the documentation update, exact
HEAD archive, and preservation hash snapshots).
New evidence is under ignored `files/test-logs/phase2-checkpoint/`
(`focused.log`, `verify.log`, final `verify-final.log`, `install.log`, `installed-smoke.log`, and
preservation snapshots). Reproducible developer runners are
`files/tests/Invoke-SelectionBrokerTests.ps1` (both architectures) and
`files/tests/Invoke-InstalledSelectionBrokerTests.ps1` (opt-in, existing normal
installation, fresh repository fixtures). Automation does not prove Explorer
menu overflow appearance, concurrent Explorer invocations, rendered icons,
normal console suppression, or Developer Mode UI.

### Launcher and intentional inventory

`Setup_and_Run-Portable-Folder-Icons.command` was missing only in the worktree;
HEAD and the index still track its Windows-only macOS notice. The verification
gate explicitly requires it. Restored only that file using
`git restore --source=HEAD --worktree -- Setup_and_Run-Portable-Folder-Icons.command`;
it now has no Git diff. No macOS functionality was introduced.

`files/ICO-Files` intentionally contains **19** immediate ICOs: the ten
tracked original colours (`Black`, `Blue`, `Gray`, `Green`, `Orange`, `Pink`,
`Purple`, `Red`, `Teal`, `Yellow`) plus nine untracked development/test icons:
`Folder_ai.ico`, `Folder_code.ico`, `Folder_CSPW.ico`, `Folder_excel.ico`,
`Folder_markdown.ico`, `Folder_python.ico`, `Folder_react.ico`,
`Folder_root.ico`, and `Folder_work.ico`. All validate and are preserved.
Do not move, restore, delete, or reconcile this inventory. No rights assumption
was made for any added asset, and none was staged or committed. The existing
untracked PNG source, `.ai/`, and generated `REPO-STRUCTURE.md` are also preserved.

### Active-plan status and exact next action

| Phase/gate | Committed state at `88007c5` | Current local state / remaining work |
|---|---|---|
| Prerequisite / Phase 0 | v0.1.0 release reconciliation recorded; v0.1.1 branch/version established | Complete historically; no new release operations performed |
| 1: scalable context menu | Implemented and committed in `d6b27b9`; exact HEAD automation passes | Complete implementation; final Windows visual/overflow acceptance remains |
| 2: safe multi-folder Apply/Reset | Research recorded; stopped at COM architecture gate; no implementation committed | Automated checkpoint PASS; canonical Reset, registration-derived tests, both ABI builds, installed x64 dispatch and cleanup verified. Manual Explorer acceptance and Git checkpoint remain |
| 3: installed configuration + one retry | Existing strict Developer Mode settings only | Not started: configurable bounded delay and exactly one optional targeted retry |
| 4: diagnostics + bounded logs | Existing Developer Mode terminal/result UI only | Not started: detailed persistent per-target/attempt/maintenance logs and rotation |
| 5: tracked customizations | No customization registry | Not started: atomic tracking, successful Reset removal, moved/unavailable/corrupt-state handling; request JSON is transport, not tracking |
| 6: safe complete removal | Ordinary cache-preserving uninstall and legacy warned purge | Not started: tracked-folder reset and safe `REMOVE COMPLETELY` from setup and installed action; legacy purge does not satisfy this phase |
| 7: Admin Mode research | No v0.1.1 research deliverable | Pending research only; no production elevation/HKLM changes |
| 8: Windows 11 first-level menu research | No v0.1.1 research deliverable | Pending research only; classic-menu selection broker does not implement `IExplorerCommand` or packaged modern-menu integration |
| 9: documentation | Version/plan/ADR 011 and Phase 1 notes present | Partially maintained; this re-orientation records current facts, future phase docs still pending |
| 10: bug hunt / final gate | No final v0.1.1 acceptance | Pending broad review, expanded verifier coverage, green worktree gate, Windows manual checklist, asset rights and explicit final approval |

**Exact next action:** obtain the user's Phase 2 manual Explorer results using
the checklist below. Resolve any observed failure within Phase 2, rerun the
gate after fixes, and update this Handoff. Do not commit while this manual gate
remains. Source/binary/asset staging authorization must be explicit when a
checkpoint is authorized; the nine additional ICOs remain local and untracked.
Do not start Phase 3, merge, tag, release, or delete the plan.

### Phase 2 manual Explorer acceptance checklist

Use disposable folders under `files/test-files/phase2-manual/`, never important
folders. Current setup is already installed in normal mode with all 19 icons.

1. Select one, then multiple writable folders (include spaces, Unicode,
   ampersands, apostrophes, parentheses, `%`, and `!`). In Explorer's classic
   **Folder Icons** menu, confirm the nested chooser and Reset/Repair/Uninstall
   remain accessible. Apply Blue, Red, Reset, then Black; check every folder's
   current INI/resource and that unrelated INI content survives. Normal
   all-success must show no console flash or completion dialog.
2. Select more than 100 folders (for example 125). Apply and Reset through the
   actual menu; ensure every selected folder is processed, the menu stays
   available, and no path is dropped. Check small selections as controls.
3. Select valid folders plus one disposable folder with malformed `desktop.ini`
   (`[broken` is sufficient). Apply and Reset must each show one useful,
   scrollable aggregate failure result, continue with valid targets, and retain
   their successes. Restore only the disposable fixture before retrying.
4. Trigger two separate selections close together with distinct icon choices.
   Confirm each invocation affects only its own selection and its aggregate
   result does not mix targets. Repeat Apply and Reset to check idempotence.
5. Set repository `[settings] developer_mode=true`, rerun setup, and repeat
   successful and mixed-failure cases. Diagnostics/terminal/results may be
   visible, but target outcomes and continuation must match normal mode.
   Restore `false` and rerun setup; normal all-success must be silent again.
6. Use installed Repair and retest Apply/Reset; confirm it preserves settings
   and recreates both selection registrations without importing repository
   icons. If testing Uninstall, choose cache preservation, confirm the menu,
   COM registration, runtime, and requests are removed while customized icons
   remain usable; rerun repository setup afterward. Do not purge the cache.
7. Observe Explorer windows/tabs during the tests: no Explorer restart/global
   cache deletion or changes to unrelated views. Check rendering in a fresh
   view; a warm existing view can retain the previous icon until F5/navigation
   or a new view, the already accepted limitation. Record actual visual results.

No known failing automated Phase 2 check remains. Explorer UI/large selections/
independent invocations and x86 installed activation remain unproven by the
current x64 installed smoke test. Later final compatibility/manual gates and
asset rights are still required before public release.

Remaining final manual checks include large/mixed selections (including >100),
one aggregate outcome and continuation after failures, independent invocations,
normal/developer console behavior, zero/19/50+ icon overflow with utilities
accessible, repository-independent Repair, rollback, Uninstall, and the existing
rendered-icon limitation. Later-phase retry/logging/tracking/removal checks must
also pass when implemented. Confirm redistribution rights for every added ICO
intended for publication and obtain explicit final approval before deleting the
plan or merging/tagging/releasing v0.1.1. This session stops at the Phase 2
manual Explorer gate.

The accepted Explorer limitation is: an already-open Explorer view may retain
the previous folder color until refreshed. Press F5, navigate away and back,
or open a new Explorer window/view to display the current color. Reset normally
updates immediately. Do not reopen the refresh-system design for v0.1.0.

Apply and Reset run silently by default. Setting
`[settings] developer_mode = true` in `config.toml` before rerunning setup
restores their progress terminal and completion/warning dialog. Errors remain
visible in both modes. Setup persists the strict Boolean in installed
`settings.json`; Repair reuses it, rollback preserves it, and Uninstall removes
it. The final windowless-launch correction and Developer Mode behavior were
included in the manually approved merge.

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

The v0.1.0 rendered-icon and Developer Mode behavior have user acceptance.

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
| 1 | Critical | Apply / generated resources | Apply deleted the superseded ICO while Explorer was still resolving it. The icon then resolved to nothing, Explorer cached "no customization", and the folder showed the plain default icon permanently. Every resource a folder has used is now retained until Reset reclaims them. | Fixed / manually accepted | Claude |
| 1a | Known limitation | Explorer icon cache | With a warm cache, an already-open Explorer view keeps painting the previous custom icon after Apply. No supported non-invasive mechanism was found that changes this; see "Explorer icon cache" above for the measured evidence. Opening a new window on the folder shows the current icon. | Documented, not solvable under current constraints | Claude |
| 1b | Major | Explorer refresh reporting | `RefreshSucceeded` was computed only from the notification count, so a run that matched a view and reloaded none of them still reported success. It now requires every matched view to have been reloaded, and reports `ViewReloadPerformed` separately. | Fixed | Claude |
| 1c | Major | Explorer refresh navigation | If the outbound leg of the away-and-back reload failed or timed out, the view was left stranded at the temporary parent. The return leg is now in a `finally` block. | Fixed | Claude |
| 2 | Critical | Registry integration | The parent stored `ExtendedSubCommandsKey` as a child key instead of a REG_SZ reference, so Explorer treated **Folder Icons** as a plain executable verb; setup also left ten recognized prototype `FolderColor_*` verbs in place. | Fixed / manual retest passed | User |
| 3 | Critical | `Setup_and_Run-Portable-Folder-Icons.bat` | Passing the trailing-backslash checkout root as `"%~dp0"` caused native PowerShell argument parsing to retain a closing quote in the value sent to `GetFullPath`. | Fixed / manual retest passed | User |
| 4 | Minor | Explorer UI | The same-location parent-view reload is intentionally stronger and may reset that view's selection or scroll position. Actual icon rendering remains a user-only visual assertion. | Mitigated / manual QA | Codex |
| 5 | Feature in progress | Selection | Multi-folder Apply/Reset has a local COM broker and aggregate batch implementation, absent from HEAD. | Automation passes; manual Explorer acceptance and checkpoint pending | User / Codex |
| 6 | Major | Integration / SelectionBroker | Registered Reset name disagreed with the broker validator. | Fixed locally: canonical `Utility_0100_Reset`; registration-derived regression and installed COM Reset pass | Codex |
| 7 | Verification gate | scripts/verify.ps1 | Root allowlist omitted intentional developer guidance/map; security scan omitted nested C#. | Fixed locally: exact ignored/untracked developer artifacts, nested C# security scan, both-artifact identity checks; gate PASS | Codex |
| 8 | Major | SelectionBroker native initialization | Fixed 16-byte VARIANT did not represent the native x64 property-bag buffer size. | Fixed locally: native union layout; x64/x86 ABI regression and installed x64 COM initialization pass | Codex |
| 9 | Blocker (environment) | Verification / endpoint security | 2026-11-16: WatchGuard Endpoint Security ("Untrusted program blocked", publisher None) blocked `files/test-logs/selection-focused-01d92367b8af45ae9ef29398ed41c34a/SelectionBrokerHarness.x64.exe` (SHA-256 `35482483f917106c82d485a0e360aa1846407adcbec162f52b19dd1103fd4bf5`). It compiled successfully; only execution was denied. Launch attempts, all before the user's stop instruction: (a) `Invoke-SelectionBrokerTests.ps1` via powershell.exe; (b) direct retry from pwsh.exe; (c) a byte-identical copy in the ignored Phase 0 evidence folder from pwsh.exe (a diagnostic; it is a relocation and must not be repeated). x86 never started. The in-suite harness had run (358 passed) about 3 minutes earlier. Installed and repository broker EXEs started normally (exit 64 by design). Classified BLOCKED_BY_ENDPOINT_SECURITY; not evidence of regression. | Open: needs an authorized security decision; gate withholds launches by default | User / Claude |
| 10 | Baseline | Working tree | `LICENSE` deleted and `LICENSE.LICENSE` untracked with identical text (CRLF only); `scripts/verify.ps1` fails two checks (gate BASELINE B-001/B-002). | Fixed 2026-11-16: renamed back to `LICENSE` (= `HEAD:LICENSE`, no diff); rows retired; run `20261116T165247Z-85283c` | Claude |
| 11 | Major | Repair (D3) | Failures give no Setup_and_Run guidance; one bad cached icon blocks all re-registration; missing module fails invisibly; concurrent re-registration races (isolated reproduction). | Open: plan Phase 0A (recommended next) | Claude |
| 12 | Critical | Chooser (D1) and missing utilities (D5) | M01 FAIL: only 16 entries render per top-level static cascade (Choose Folder Icon + 15 icons); icons 16–21 and Reset/Repair/Uninstall are dropped. Registry correct. | Fixed 2026-11-16 (Phase 0B): utilities first, 12-icon chooser, alphabetical-range overflow entries; Shell-built menu PASS (`c-0009`); **M01 PASS** (user). Final single-entry layout still preferred (design open) | User / Claude |
| 16 | Blocker (environment) | Verification / WatchGuard | Harness rebuilt per run → new hash each time → each build needs classification (`b2eaad08…` blocked after `35482483…` was approved). | Project side fixed 2026-11-16 (ADR 014): build-once cache; x64 `0a71577b…`, x86 `4f589ac4…` stable and never launched. `35482483…` is input-equivalent to the x64 build (timestamp/MVID only) but not adopted. Open: security owner decision | Claude |
| 17 | Major (packaging) | `.gitattributes` | Broker `.cs` had only `text=auto`; a fresh clone with `core.autocrlf=true` writes CRLF, so setup's source-hash check rejects the broker. Never shipped (broker not yet committed). | Fixed 2026-11-16: `*.cs text eol=lf`; regression check in `scripts/verify.ps1`; reproduced and verified with a throwaway index | Claude |
| 18 | Minor (privacy, pre-existing) | `md-instructions/Handoff.md`, `files/tests/Invoke-Tests.ps1` | Tracked since July: machine name in old sync-log headings, one absolute user path in an old log line and one in a launcher test. Not added by current work. | Open: tidy in a later docs/tests task; history keeps them | Claude |
| 19 | Minor (verification) | `scripts/verify.ps1` direct runs | Without `-SkipNativeHarness`, the direct verifier still launched the cached in-suite harness (historical default). | Fixed 2026-11-16: launches need `-AllowNativeHarness` or `PFI_GATE_NATIVE_HARNESS=allow`; `c-0007` truth table and the `c-0001`/`c-0006` unauthorized-launch guard | Claude |
| 20 | Minor (tooling) | `.claude/CLAUDE.md` (gitignored workspace template) | Its `@AGENTS.md` and `@AI-WORKSPACE.md` imports resolve relative to `.claude/` (Claude Code docs), where neither file exists; only its fallback sentence points to the root files. A local pointer to the housekeeping rule was added. | Fixed 2026-11-16 (ADR 018): tracked root `CLAUDE.md` imports `@AGENTS.md`; verifier check. Local file untouched. Confirmed 2026-11-17: a fresh session loaded `CLAUDE.md` and `AGENTS.md` at startup | Claude |
| 21 | Minor (docs) | `md-instructions/Feature-Map.md` | `AGENTS.md` and `CLAUDE.md` notes require registering features in `md-instructions/Feature-Map.md`, which has never existed in this repository; the gate's `coverage.tsv` is the enforced register (Phase 0B registered `PFI-002`/`PFI-014` there before coding). | Open: create the map from the workspace structure in a docs task | Claude |
| 22 | Minor (docs) | `README.md`, `files/readme-assets/folder-icons-submenu.png` | The README screenshot shows the pre-Phase-0B submenu order, and the README does not yet mention overflow entries for more than 12 personal icons (the ten shipped colours all fit the chooser, so the usage text stays true). | Open: Phase 9 docs, with a new user-made screenshot | Claude |
| 23 | Major (UX) | Explorer menu | User requirement 2026-11-17: one top-level Folder Icons entry with one complete, wheel- and keyboard-scrollable icon list (native submenu preferred). Static registration cannot do it (16-entry cap); a native single submenu needs an in-process Explorer extension (ADR 019). P1 (user): the native popup does not scroll with the wheel; arrows and keyboard work. W1: the wheel works only through a menu hook, which in Explorer means in-process code plus a hook. | Open: user decision. Claude recommends C (picker launched from Choose Folder Icon…), or D; A (Phase 0B) stays the fallback | User / Claude |
| 25 | Security incident | `outputs/experiment-single-menu/Test-MenuWheelFeasibility.ps1` (ignored experiment) | 2026-11-17 about 08:29: WatchGuard Endpoint Security 360 deleted the W1 wheel-experiment script, detection "Malware or potentially unwanted program (PUP)", action Deleted (local quarantine record `7b16cb86-a9e5-4b25-ad38-861fa7b478c2`, 08:29:36). The script used `Add-Type`, a thread-local `WH_MSGFILTER` hook, posted key and wheel messages, and a screen capture of its own menu. The trigger is unconfirmed. No process or hook remains, and Explorer and production were untouched. | BLOCKED_BY_ENDPOINT_SECURITY. Do not recreate or continue. Open: security owner reviews the console incident; any future hook experiment needs their authorization of an exact implementation | User / Claude |
| 24 | Major (feature) | Complete removal | User requirement 2026-11-17: root `Uninstall-Portable-Folder-Icons.bat` as the only complete-uninstall entry point; Uninstall leaves the Explorer menu (ADR 020). | Open: plan Phase 7 (reconciled); register in the Feature Map (Open Issue 21) before coding | User |
| 26 | Minor (reliability) | `Install-PortableFolderIcons.ps1`; static Repair/Uninstall verbs | Phase 0A gates left open (ADR 021). (a) Setup registers the menu without taking the per-user maintenance lock, so Setup running at the same moment as an Explorer Repair is not serialized. (b) If the installed dispatcher script itself is missing, the static `powershell.exe -WindowStyle Hidden -File <dispatcher>` command has no product code to show a dialog. **2026-11-17 (Phase 0A.1, ADR 022): (b) fixed for normal mode**, where the launcher shows a guided dialog. Still silent: Developer Mode's unchanged direct command, and a dispatcher that exists but cannot be parsed (it exits 1, the same as a reported failure). | Open: (a) a later phase that touches setup; (b) residual with the final menu architecture (ADR 019) | Claude |
| 13 | Major | Reset (D2) | Not reproduced at persisted-state or fresh-process Shell layers; rendering unverified. | Open: manual M02, then plan Phase 2 | User |
| 14 | Major | Actions INI read | ANSI `desktop.ini` non-ASCII text corrupted by Apply/Reset (read as UTF-8, rewritten UTF-16LE). | Open: plan Phase 2 | Claude |
| 15 | Minor | Reset attributes | Reset does not restore pre-existing folder ReadOnly; removes third-party icon fields. | Open: plan Phase 6 | Claude |

---

## Work Log (newest first)

- 2026-11-17 (Phase 0A.1) — Windowless maintenance launch (ADR 022), from start SHA `3170d8f`.
  - **Diagnosis:** read-only check of `HKCU\Console\%%Startup`, plus three disposable probes under the ignored
    `files/temp/` (removed after recording). They used only inbox PowerShell, UI Automation reads and a UI Automation
    close of their own test dialog. The results are in ADR 022.
  - **Fix:** normal-mode Repair/Uninstall command construction; the launcher's maintenance branch with a guided error
    dialog and test seam.
  - **Tests:**
    - `c-0001`: exact normal and Developer Mode command strings, with spaces, `&`, `()`, `%`, `!` and non-ASCII in the
      install path; launcher-path validation.
    - `c-0010`: the real `wscript.exe` launcher cases w1–w10, with a UI Automation window observer.
    - `c-0003`: the D3 missing-dispatcher finding reworded.
    - PFI-017 registered in `coverage.tsv` before the code.
  - RED was shown before the fix: the launcher returned 64 for `-Action Repair`, and the plan still built the
    `-WindowStyle Hidden` command.
- 2026-11-17 (Phase 0A) — Implemented Redesign Phase 0A, Repair reliability (ADR 021), from start SHA `0459c9e`.
  - **Runtime:**
    - Guarded module loading in the dispatcher, with one visible dialog naming the failed file.
    - Partial Repair with per-icon diagnosis and a filtered in-memory manifest.
    - A per-user `Local\` maintenance mutex with bounded wait, abandoned-lock takeover and coalescing.
    - Accurate result and failure messages that always name the setup launcher.
    - A test-only dialog seam, ignored for the production root.
  - **Tests:** new `c-0010` (84 assertions). `c-0003` D3 FINDINGs became assertions, and its race now holds the lock.
    The suite replaced "Repair throws on a corrupt cache" with partial-recovery, formatter and lock-name tests;
    `Test-PfiInstalledRuntime` still throws.
  - **Fixed during development:**
    - The lock trace was written after `ReleaseMutex`, so another process could log its acquisition first. It is now
      traced while still owned (`lock-releasing`).
    - The abandoned-lock test assumed a crashed holder leaves a stale lock. A named kernel mutex disappears with its
      last handle, so abandonment is seen only by a request that is already waiting. Both cases are now tested.
  - **Feature register:** `coverage.tsv` (Open Issue 21: `Feature-Map.md` still does not exist).
  - **Full gate:** `20261117T152716Z-f0faff`, BLOCKED (`c-0002` withheld, `c-0004` opt-in); every executed check
    passed. Detail is in the snapshot.
  - **Housekeeping:**
    - Removed with the gate helper: focused run `20261117T152017Z-fce794` and full run `20261117T152716Z-f0faff`, after
      recording them here.
    - Removed by explicit path: the disposable dev runs `files/temp/p0a-dev1`, `files/temp/p0a-dev2`.
    - Kept, each with a RETAIN.md: `experiment-single-menu/`, `manual/`, `retained-phase0-preedit/`, and
      `cache/native-harness/`. — Claude

- 2026-11-17 (P1, W1, publication) — Recorded the user's P1 results.
  - **Research:** read the Microsoft Learn pages on `WM_MOUSEWHEEL`, hooks, `MessageProc`, `SetWindowsHookEx`,
    `TrackPopupMenuEx`, `MENUINFO`, About Menus, `GetMenuItemRect`, `MN_GETHMENU`, `EndMenu` and window classes.
  - **W1:** ran the isolated wheel experiment (results and the security incident: plan section "P1 user results and
    mouse-wheel experiment W1", ADR 019 update, Open Issue 25). Stopped all W1 execution when WatchGuard deleted the
    script. Read-only checks showed no lingering process and found the local quarantine record.
  - **Documentation:** reconciled the final menu (option D now reads Reset, Repair, Choose Folder Icon with 12 icons and
    "More icons…"). Recorded P1/P1-W in `MANUAL-GATES.md`.
  - **Pre-publication audit:** see the snapshot.
  - **Housekeeping:** removed the E1 outputs, the empty fixture folder and 24 redundant captures, and kept the P1 script,
    the W1 log and two captures (RETAIN.md updated).
  - **Scope kept:** no architecture, Phase 0A, uninstaller, Explorer or registry work. — Claude

- 2026-11-17 (later) — Committed Phase 0B as `496b508` after the full gate (user-authorized; local only). Did the
  bounded single-menu feasibility investigation:
  - read the Microsoft Learn documentation on static and dynamic menus, in-process guidance, MENUINFO, MENUITEMINFO
    and About Menus;
  - ran isolated experiment E1 (all items of a dynamic submenu were kept, 0–300; first run deviated, see the snapshot);
  - did read-only checks: no native toolchain, `EnforceShellExtensionSecurity` not set, the broker `ValidateCommand`
    contract.

  Recorded ADR 019 (single-entry UX, decision pending) and ADR 020 (root complete uninstaller), plus the plan sections
  and the Phase 7 reconciliation. Housekeeping: removed two recorded gate runs (3.9 MB) and retained the experiment
  folder for probe P1. No architecture, uninstaller or Phase 0A work. `ctx7` CLI rejected its API key, so
  documentation came from the Context7 MCP server and Microsoft Learn directly.

  Documentation check after the edits: focused gate `20261117T134310Z-bf084e` (`c-0006` project verifier) PASS in 99 s
  on HEAD `496b508` plus these uncommitted docs. `git diff --check` was clean. The run folder was removed after this
  record. — Claude

- 2026-11-17 — Recorded the user's M01 PASS (Phase 0B), verified the live installation is byte-identical to the
  working tree, added the Changelog entry, ran the full gate and made the authorized local Phase 0B commit. The user
  prefers a single top-level menu; Phase 0B is the fallback. — Claude

- 2026-11-16 (night) — Phase 0B. Created `feature/v0.2.0` from `ddbe65f`. Registered the change in `coverage.tsv`
  (`PFI-002`, new `PFI-014`) and `checks.tsv` (new required `c-0009`) first; wrote the suite's layout, determinism,
  boundary-label, live expansion/shrinkage/lookalike tests and the Shell-builder check `c-0009` (converted from the
  Phase 0 probe) and watched both fail on the old layout (suite 90 failures; Shell menu "15 of 21"). Implemented the
  budgeted layout in `PortableFolderIcons.Integration.ps1`; updated `c-0003` D1 for the new layout and fixed its race
  cleanup, which leaked an overflow store per run (two leaked GUID test keys removed). Added the tracked root
  `CLAUDE.md` (ADR 018) with a verifier check (RED first). No production install, broker or version change. — Claude

- 2026-11-16 (checkpoint session) — Made every verification entrypoint withhold compiled-harness launches by default
  (`Test-PfiNativeLaunchAuthorized`; gate now calls the verifier and suite with no native flag and fails on an
  unauthorized launch). Added the permanent housekeeping rule to root `AGENTS.md` (de-templated), the gate helper
  `Remove-GateOutputs.ps1` with check `c-0008` (41 assertions, RED first), `AGENTS.md` to the verifier's root contract
  and a check that the rule stays documented. Prepared the authorized checkpoint commit. — Claude

- 2026-11-16 (evening) — Phase 0 final reconciliation. Restored `LICENSE`. Added the harness build cache, process
  outcome classification and launch guard (`files/tests/NativeHarness.Common.ps1`), rewired the suite, both runners and
  the `c-0002`/`c-0004` wrappers, added `c-0007` (131 assertions; RED first on the unmodified `c-0004` wrapper) and gate
  exit 5 (CRASH). Fixed the broker `.cs` line-ending packaging defect. Moved the active plan to `md-instructions/`,
  recorded the approved Phase 0B static-menu design and ADRs 014–016. Prepared and exercised the checkpoint manifest.
  Full gate BLOCKED (no FAIL). No product runtime or installation change. — Claude

- 2026-11-16 (afternoon) — Phase 0 addendum. Recorded M01 FAIL and new defect D5. Reproduced both in isolation with
  the Shell's own static-menu builder: a 16-entry budget per top-level static cascade, applied depth-first; grouping
  does not help, extra top-level cascades do. Validated a candidate budgeted layout (E6/E7). Investigated the
  repeat WatchGuard block read-only: per-run rebuild changes only timestamp and MVID. Corrected a misclassified
  `c-0002` run and fixed that wrapper's stderr capture. Plan Phase 0B rewritten; no product code changed. — Claude

- 2026-11-16 — Phase 0 baseline recovery, diagnostics and verification gate. Verified refs read-only;
  snapshotted every modified/untracked file with hashes; confirmed installed runtime = working tree. Ran the
  baseline `scripts/verify.ps1` (371 PS + 358 C# passed; FAIL only on the LICENSE rename). Focused x64 harness
  blocked by WatchGuard (Open Issue 9). Established the workspace-template verification gate under
  `files/dev-work/verification-gate/` (checks c-0001…c-0006, coverage, known-baseline, GATE.md, MANUAL-GATES.md),
  added `-SkipNativeHarness` and BLOCKED results to the suite and verifier, and ignored gate outputs. Added
  D1–D4 diagnostics (83 assertions, 21 findings). Amended the v0.2.0 plan and appended ADR 013. — Claude

- 2026-10-01 — Finished the narrow Phase 2 automated checkpoint: canonical
  Reset identity, actual registration-derived initialization coverage, native
  VARIANT layout correction, rebuilt x64/x86 artifacts/hashes, and exact
  developer-artifact verifier/ignore reconciliation. Focused x64/x86 harnesses
  each pass 350 assertions; full gate passes 371 PowerShell plus 350 C# and
  all 19 ICOs. Backed up and updated the actual tool-owned installation;
  native COM Apply/Reset/repeat Reset passes six fixture outcomes with request
  cleanup and broker exit. No commit or Phase 3 work; manual Explorer gate
  remains. — Codex

- 2026-10-01 — Reconstructed both feature commits and the complete
  `d6b27b9..88007c5` diff. Distinguished committed Phase 1/research from
  uncommitted Phase 2 broker/runtime work; confirmed Reset identity mismatch
  without changing implementation. Restored only the tracked `.command`
  launcher from HEAD. Exact HEAD archive passes 292 assertions; preserved
  worktree passes 371 PowerShell plus 256 C# harness assertions and validates
  all 19 intentional ICOs, but fails the root allowlist for `.ai/` and
  `REPO-STRUCTURE.md`. Updated permanent docs; no assets or implementation
  files staged/committed and no phase advanced. — Codex

- 2026-08-25 — Phase 2 transport research gate. Microsoft documents `%1` as
  the static command path placeholder, caps legacy Player verbs at 100 items,
  and identifies `IObjectWithSelection`/`IShellItemArray` or `IDropTarget`/
  `IDataObject` as the supported lossless multi-selection transports. Rejected
  an undocumented `%*` command line and a timing-based multi-process queue:
  neither can guarantee no truncation/reordering plus one aggregate result.
  A compiled current-user COM integration is therefore the narrow supported
  route, but is a material architecture expansion requiring user approval.
  Implementation stopped at this gate. — Codex

- 2026-08-25 — Phase 1 scalable-menu implementation. Replaced the unbounded
  one-popup layout with a short parent whose **Choose Folder Icon** child owns
  every dynamic alphabetical Apply verb while Reset, Repair, and Uninstall
  remain parent siblings. Added a separately owned HKCU icon-choice store,
  exact registration/removal guards, and deterministic zero/one/ten/current/
  30/50 inventory tests. No COM extension was added. — Codex

- 2026-08-25 — Formally published v0.1.0 from verified commit `6cb6bae`:
  pushed `main`, created/pushed annotated tag `v0.1.0`, and published GitHub
  release `Portable Folder Icons v0.1.0`. Verified local main, origin main,
  local tag, remote tag, and release target. Created `feature/v0.1.1` from the
  exact release SHA, inventoried ten tracked and seven untracked ICOs, preserved
  all local assets, and advanced project version state to 0.1.1. — Codex

- 2026-08-25 — Reconciled the formal v0.1.0 release state. Confirmed local and
  origin `main` at merge commit `1362fe1`, confirmed the historical feature
  branch tree is identical, confirmed GitHub had no tags or releases, and ran
  the complete Windows PowerShell 5.1 gate in a clean detached checkout of the
  exact merge: 265 assertions passed, all ten release ICOs validated, and every
  structural/security check passed. Corrected stale release documentation and
  retired the fulfilled v0.1.0 temporary implementation drop. Formal tag and
  GitHub release publication remain next. — Codex

- 2026-07-29 — Corrected the normal-mode console flash found during manual
  acceptance. Added and staged `Invoke-PortableFolderIcons.Hidden.vbs`, changed
  only normal Apply/Reset registry commands to use `wscript.exe`, added strict
  UTF-16-hex target decoding to the dispatcher, required the launcher during
  Repair validation, and expanded command, lifecycle, special-character, and
  windowless-launch regression coverage. Updated README, Briefing, Changelog,
  Decisions, and Handoff. Developer Mode remains unmerged pending visual
  confirmation that normal mode produces no terminal at all.

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

### 2026-11-17 — Current Windows workspace — Phase 0A.1 windowless maintenance launch (Claude Code)

- Started at `3170d8f`, which was already on `origin/feature/v0.2.0`. Made one Phase 0A.1 commit on top and pushed it
  normally; read the SHA with `git log -1`. No merge, tag, release, `main` change or version bump.
- Committed:
  - Runtime: `scripts/Windows/PortableFolderIcons.Integration.ps1`,
    `scripts/Windows/Invoke-PortableFolderIcons.Hidden.vbs`.
  - Tests: `files/tests/Invoke-Tests.ps1`, gate `tests/Test-PfiMaintenanceReliability.ps1`,
    `tests/Invoke-Phase0Diagnostics.ps1`.
  - Gate registers: `checks.tsv`, `coverage.tsv`, `GATE.md`, `MANUAL-GATES.md`.
  - Docs: Briefing, Changelog, Decisions, Handoff and the plan.
- Left untracked and untouched: the personal ICOs in `files/ICO-Files/` and `files/extra-ICO-files-for-use/`.

### 2026-11-17 — Current Windows workspace — Phase 0A Repair reliability (Claude Code)

- Started at `0459c9e`, which was already on `origin/feature/v0.2.0`. Made one Phase 0A commit (pending M03) on top and
  pushed it normally; read the SHA with `git log -1`. No merge, tag, release, `main` change or version bump.
- Committed: `scripts/Windows/Invoke-PortableFolderIcons.ps1`, `scripts/Windows/PortableFolderIcons.Maintenance.ps1`,
  `files/tests/Invoke-Tests.ps1`, gate `checks.tsv`, `coverage.tsv`, `GATE.md`, `MANUAL-GATES.md`,
  `tests/Invoke-Phase0Diagnostics.ps1`, `tests/Test-PfiMaintenanceReliability.ps1`, and Changelog, Decisions, Handoff
  and the plan.
- Left untracked and untouched: the personal ICOs in `files/ICO-Files/` and `files/extra-ICO-files-for-use/`.

### 2026-11-17 — Current Windows workspace — Phase 0B commit and single-menu feasibility (Claude Code)

- One local commit on `feature/v0.2.0`: `496b508` (user-authorized). Not pushed; no branch, tag or merge.
- Committed: `CLAUDE.md`, `scripts/Windows/PortableFolderIcons.Integration.ps1`, `scripts/verify.ps1`,
  `files/tests/Invoke-Tests.ps1`, gate `checks.tsv`, `coverage.tsv`, `GATE.md`, `MANUAL-GATES.md`,
  `tests/Invoke-Phase0Diagnostics.ps1`, `tests/Test-PfiStaticCascadeMenu.ps1`, and Briefing, Changelog, Decisions,
  Handoff and the plan.
- Uncommitted afterwards: Decisions (ADR 019/020), the plan and Handoff. Ignored:
  `outputs/experiment-single-menu/`.
- Preserved: personal ICOs untracked and unstaged; installation and production registry untouched (read only).

### 2026-11-16 — Current Windows workspace — authorized Phase 0 checkpoint (Claude Code)

- One local commit on `feature/v0.1.1` (user-authorized); not pushed; no branch, tag or merge.
- Added: `AGENTS.md` (from the workspace template), `files/dev-work/verification-gate/helpers/Remove-GateOutputs.ps1`,
  `tests/Test-GateOutputHousekeeping.ps1`. Changed: `scripts/verify.ps1`, `files/tests/Invoke-Tests.ps1`,
  `NativeHarness.Common.ps1`, gate `checks.tsv`, `coverage.tsv`, `GATE.md`, `MANUAL-GATES.md`,
  `tests/Invoke-ProjectVerifyCheck.ps1`, `tests/Test-NativeHarnessInfrastructure.ps1`, the plan, Decisions, Handoff.
  Local only (gitignored): a housekeeping pointer in `.claude/CLAUDE.md`; `outputs/manual/RETAIN.md`.
- Preserved: all personal ICOs (hash-verified), installation and registry untouched.

### 2026-11-16 (evening) — Current Windows workspace — Phase 0 final reconciliation (Claude Code)

- Branch/SHA unchanged: `feature/v0.1.1` / `88007c5`; nothing staged or committed.
- Changed: `.gitattributes`, `scripts/verify.ps1`, `files/tests/Invoke-Tests.ps1`, `Invoke-SelectionBrokerTests.ps1`,
  `Invoke-InstalledSelectionBrokerTests.ps1`, gate `verify.ps1`, `checks.tsv`, `coverage.tsv`, `known-baseline.tsv`,
  `GATE.md`, `MANUAL-GATES.md`, `tests/Invoke-NativeHarnessCheck.ps1`, `tests/Invoke-InstalledComCheck.ps1`, the plan,
  Decisions, Handoff. Added: `files/tests/NativeHarness.Common.ps1`, `tests/Test-NativeHarnessInfrastructure.ps1`.
  Moved: plan to `md-instructions/`; `LICENSE.LICENSE` → `LICENSE`.
- Preserved: all personal ICOs and every other pre-existing change (pre-edit hashes in
  `outputs/phase0-final-20261116/`); installation and registry untouched.

### 2026-11-16 — Current Windows workspace — Phase 0 (Claude Code)

- Branch/SHA unchanged: `feature/v0.1.1` / `88007c5`; no Git ref/index mutation; nothing staged.
- Changed (local, uncommitted): `.gitignore` (gate outputs/cache ignored), `scripts/verify.ps1` and
  `files/tests/Invoke-Tests.ps1` (`-SkipNativeHarness`, BLOCKED results), `md-instructions/Handoff.md`,
  `md-instructions/Decisions.md` (ADR 013), `files/plans/Portable-Folder-Icons-v0.2.0-Implementation-Plan.md`.
- Added (untracked): `files/dev-work/verification-gate/` (runner, checks, coverage, baseline, docs, tests).
- Preserved: every pre-existing modified/untracked file, all ICOs, installation and HKCU registration
  (read-only exports in the Phase 0 evidence folder).

### 2026-10-01 — Current Windows workspace — Phase 2 automated checkpoint

- Branch/SHA unchanged: `feature/v0.1.1` / `88007c5`; no Git ref/index mutation.
- Changed within Phase 2: broker Reset/VARIANT contract and rebuilt artifacts,
  integration constant, registration-derived harness/full-suite coverage, two
  developer test runners, verifier, exact ignore rules, feature metadata, and
  affected permanent documentation. All other pre-existing work is preserved.
- Installed: corrected x64 runtime/menu, normal mode, all 19 icons reused;
  previous owned runtime/registry state backed up in ignored `files/backups`.
- Verified: full PASS (371 PowerShell + 350 C#), focused x64/x86 350 each,
  installed COM six outcomes, request cleanup/exit, 19 ICOs and whitespace.
- Pending: user manual Explorer checklist above; no commit until it passes.
- Final Git status: 17 modified tracked files and 15 untracked status entries,
  nothing staged or deleted. Full listing: ignored
  `files/test-logs/phase2-checkpoint/git-status.log`. Preservation checks confirm
  all 19 source ICOs, developer guidance/map, and other pre-existing user work
  outside the authorized Phase 2 edits remain unchanged.
- Additional ICOs and PNG remain untracked; developer guidance/map remain
  present, unchanged, and now ignored. No Phase 3, plan deletion, or release.

### 2026-10-01 — Current Windows workspace — re-orientation only

- Branch/SHA: `feature/v0.1.1` / `88007c5`; origin reference matches locally.
- Restored: tracked `.command` launcher only, from HEAD; no remaining diff.
- Changed this session: Handoff, Briefing, Changelog, Decisions, and README
  to distinguish committed state from preserved uncommitted development.
- Preserved: nine runtime/test modifications, broker/payload/harness sources
  and artifacts, all 19 ICOs, source PNG, `.ai/`, and `REPO-STRUCTURE.md`.
- Verification: exact HEAD PASS (292); worktree assertions PASS (371 plus
  256 C#), gate FAIL only on root allowlist; all 19 ICOs validate.
- Next: Phase 2 Reset identity regression/fix and actual Explorer transport
  validation; verifier maintenance and phase checkpoint still required.
- No commit/push/merge/tag/release, phase implementation, or plan deletion.

### 2026-08-25 — Machine: current Windows workspace — Phase 1 and Phase 2 gate

- Committed/pushed: `d6b27b9` on `feature/v0.1.1`, establishing version 0.1.1
  and the scalable nested static chooser with dynamic inventory tests.
- Verified: complete Windows PowerShell 5.1 gate passes with all 17 current
  local ICOs; seven new ICOs remain untracked pending redistribution approval.
- Blocked for user decision: safe unlimited multi-folder transport requires a
  compiled per-user COM selection handler; no compiled component was added.

### 2026-08-25 — Machine: current Windows workspace — v0.1.0 release reconciliation

- Changed: `md-instructions/Briefing.md`, `md-instructions/Changelog.md`, and
  `md-instructions/Handoff.md` to record the completed v0.1.0 merge, manual
  acceptance, release date, and clean exact-commit verification.
- Deleted: the fulfilled temporary
  `md-instructions/Portable-Folder-Icons-v0.1.0-Implementation-Plan.md`.
- Preserved locally and untracked: seven added ICO files, `files/PNGs`, and
  `md-instructions/need-to-do-this`; none are part of v0.1.0.

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
