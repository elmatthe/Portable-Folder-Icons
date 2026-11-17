# Manual and opt-in gates

Behaviour no automated check can observe: what Explorer actually draws and how it invokes static verbs.
These are user-run, on the Windows machine with the current installation, using only disposable folders
under `files/dev-work/verification-gate/outputs/manual/` (create it; it is ignored). Record each result,
the date, display resolution and scaling in `outputs/manual/<date>-results.md`, then summarize it in
`md-instructions/Handoff.md`. Do not restart Explorer, clear the icon cache, or test on important folders.
While a manual gate is pending, `outputs/manual/` carries a `RETAIN.md`, so routine housekeeping keeps the recorded
results; agents remove disposable test folders inside it once their results are recorded in Handoff.

Automation already establishes persisted `desktop.ini` state, attributes and fresh-process Shell
resolution (`c-0003`). It does not establish painted icons, menu scrolling, or how many processes Explorer
starts for a static verb.

## M01 — Menu reachability (coverage `PFI-M01`)

Result on 2026-11-16 before Phase 0B: **FAIL** (only Choose Folder Icon with 15 icons; Reset, Repair and Uninstall
missing). Retest after Phase 0B on 2026-11-16: **PASS** (user-reported; all checks below; Blue applied from the
chooser, Teal from the overflow entry; no duplicate or stale entries). The user accepted the behaviour, not the
two-entry layout as the final design. Retest after Phase 0B (ADR 015 layout; the Shell-built menu is proven by `c-0009`):

1. Double-click `Setup_and_Run-Portable-Folder-Icons.bat` and let it finish (current-user, no elevation).
2. Right-click a disposable folder; on Windows 11 choose **Show more options**.
3. Open **Folder Icons**. Expected order: **Reset to Default**, **Repair Portable Folder Icons**, **Uninstall Portable
   Folder Icons**, a separator, **Choose Folder Icon**. Only look; do not run Repair or Uninstall here (M03/M04).
4. Open **Choose Folder Icon**: the first 12 icons alphabetically (ignoring case). With the 21 icons installed on
   2026-11-16: ai, Black, Blue, code, CSPW, excel, GitHub, Gray, Green, markdown, Orange, Pink.
5. Find the separate top-level entry **Folder Icons (Purple–Yellow)**, normally directly below Folder Icons (record where
   it appears): Purple, python, react, Red, root, Teal, vscode, work, Yellow. Every installed icon appears exactly once
   across the two entries, reachable by mouse without scrolling.
6. Apply one icon from the overflow entry (for example Teal) and confirm that exact icon is applied; then apply one
   from Choose Folder Icon (for example Blue) and use Reset to Default on the same disposable folder.
7. Confirm there is no duplicate Folder Icons entry, no leftover overflow entry and no other unexpected Folder Icons
   item. Record the display resolution and scaling.

## M02 — Reset rendering (coverage `PFI-M02`)

1. Apply Blue to a disposable folder; open its parent in a new Explorer window and confirm Blue shows.
2. Keep that window open (warm view). Reset to Default. Record what the open window shows at once, after 10 s,
   after F5, and after navigating away and back.
3. Open a NEW Explorer window on the same parent and record what it shows (fresh view).
4. Repeat with a folder whose desktop.ini also has `[ViewState]` content, and with two folders selected at once.

Record each of the four layers separately: persisted state (automation), fresh-process Shell resolution
(automation), fresh view (this step 3), warm view (this step 2).

## M03 — Repair from the menu (coverage `PFI-M03`)

Status: **PASS** (user retest after Phase 0A.1, 2026-11-17). This is Phase 0A / Phase 0A.1 Repair manual acceptance
only. It is not an automated gate result: the full gate stays BLOCKED by `c-0002` (BLOCKED_BY_ENDPOINT_SECURITY), and
`c-0004` is NOT RUN.

Retest (user, 2026-11-17, Phase 0A.1 at `070e9be`, Developer Mode off; screenshots of both results supplied by the
user; record in `outputs/manual/2026-11-17-results.md`): **PASS**.
- Setup completed successfully: 21 ICO files discovered, accepted and reused.
- One folder and five folders each gave exactly one "Repair completed" dialog: runtime and selection broker valid,
  cached icons verified 21 of 21, Explorer menu recreated with 21 icons, Developer Mode off.
- No error dialog, and no PowerShell, Windows Terminal or command-prompt window. Both dialogs appeared in front of
  Explorer, and the user reported no Explorer problem.
- Not expressly confirmed in this retest (recorded, not failed): a fresh Apply afterwards (step 4), the optional
  declined Uninstall (step 5), and the optional process count (step 3).

First run (user, 2026-11-17, Phase 0A at `3170d8f`, Developer Mode off): **provisional PASS for Repair's function,
FAIL for window visibility.**
- Setup succeeded with 21 accepted icons.
- One folder: one correct result, 21 of 21.
- Five folders: one correct result, no error dialog.
- The Phase 0B menus still worked.
- **A large Windows PowerShell terminal window appeared behind the result dialog.**
- Cause (Phase 0A.1; ADR 022): on this PC Windows Terminal is the default terminal. The verb's `powershell.exe
  -WindowStyle Hidden` console is handed to Windows Terminal before PowerShell can hide it. Windows Terminal then only
  minimizes its window, which stays open while the dialog is shown.
- Phase 0A.1 starts normal-mode Repair and Uninstall through the installed `wscript.exe` launcher instead. Automation
  (`c-0010`) watched the desktop during those launches and saw no console or terminal window.

Automation (`c-0010`) proves the process behaviour, both directly and through the launcher:
- Four overlapping Repair processes run one Repair and show one dialog.
- The failure dialogs are visible.
- No console or terminal window appears.

It cannot observe how many processes Explorer really starts, or what a real Explorer launch paints, including whether
the dialog comes to the front. Do not corrupt the live installation to test failures; `c-0010` covers damaged copies.

1. Double-click `Setup_and_Run-Portable-Folder-Icons.bat` and let it finish, so the installed runtime and the
   registered Repair command are the Phase 0A.1 ones. Note whether Developer Mode is on or off (`config.toml`).
2. One folder: right-click one disposable folder, **Show more options**, **Folder Icons**, **Repair Portable Folder
   Icons**. Record:
   - whether any PowerShell or Windows Terminal window appears, even briefly or minimized on the taskbar (expected in
     normal mode: none);
   - whether the result dialog appears in front of Explorer, or only as a taskbar button;
   - the number of dialogs (expected: exactly one, titled Portable Folder Icons, Information icon);
   - the exact dialog text. Expected, with N your installed icon count:

     ```text
     Repair completed.

     Checked:
     - Runtime files and selection broker: valid
     - Cached icons verified: N of N
     - Explorer menu: recreated with N icon(s)
     - Developer Mode: off

     Repair does not import new icons. To add or remove icons, double-click Setup_and_Run-Portable-Folder-Icons.bat.
     ```

     (`- Developer Mode: on` when it is on.)
3. Five folders: select five disposable folders together and choose Repair once. Record:
   - the number of result dialogs (expected: one; more than one means coalescing did not hold for Explorer's launch
     timing — record how many and their text);
   - any error dialog, especially "Another Portable Folder Icons Repair or Uninstall is still running";
   - any PowerShell or Windows Terminal window (expected: none);
   - optionally, in Task Manager, how many `wscript.exe` and `powershell.exe` processes appear briefly (one each per
     folder would confirm that Explorer starts one process per selected item).
4. Afterwards: the Folder Icons menu is still complete (Reset, Repair, Uninstall, Choose Folder Icon, overflow entry),
   one icon applies normally, and Explorer showed no hang, restart, flicker of the whole desktop or missing menu.
5. Optional, Uninstall without uninstalling: choose **Uninstall Portable Folder Icons** on one folder and answer **No**.
   Expected: one confirmation prompt, no PowerShell or terminal window, nothing removed (the menu stays).
6. Record date, Windows build, display scaling, Developer Mode state and the results in
   `outputs/manual/<date>-results.md`, then summarize in Handoff. Pass needs: one dialog with the expected text in
   both steps, shown where you can see it, no error dialog, no PowerShell or terminal window in normal mode, and no
   Explorer problem. In Developer Mode the verb keeps its direct `powershell.exe -WindowStyle Hidden` command, so a
   terminal window there is recorded, not failed.

## M04 — Uninstall prompt with several folders (coverage `PFI-M04`, observe only)

With three disposable folders selected, choose **Uninstall Portable Folder Icons** and count the confirmation
dialogs. Answer **No** to every prompt. Nothing is uninstalled.

## M05 — single Folder Icons entry with the icon picker (proposed; not runnable)

Proposed for ADR 019 option C, which is **not approved or implemented**. The draft checklist is in the active plan,
section "Option C design recommendation". It becomes a runnable gate here only after the user approves option C and
the picker layout is implemented.

## P1 and P1-W — native popup and mouse wheel (feasibility probes, not acceptance gates; ADR 019)

These probes run in a PowerShell window, never in Explorer. They register nothing and run nothing that is chosen. Their
scripts are local, ignored experiment files under `outputs/experiment-single-menu/` on the original PC (RETAIN.md
there), so a fresh checkout does not have them.

**P1 result (user, 2026-11-17; `Test-SingleMenuFeasibility.ps1 -Interactive`, 120, 45, and 120 in columns of 30).**
- PASS: full inventory in one submenu, all 120 icons reachable with the scroll arrows, keyboard Up/Down, and selections
  logged.
- **FAIL: the mouse wheel does not scroll the popup.**
- Not proven: Explorer, Home/End and access keys, other resolutions and scaling.

**P1-W: BLOCKED_BY_ENDPOINT_SECURITY (2026-11-17). Question: does real wheel input reach a thread-local menu hook, and
does wheel-to-navigation feel acceptable?**
- **Incident.** WatchGuard Endpoint Security 360 deleted its probe script `Test-MenuWheelFeasibility.ps1` at about
  08:29: "Malware or potentially unwanted program (PUP)", action Deleted, local quarantine record `7b16cb86-…`.
- **Status.** The script no longer exists. Do not recreate, restore, rename or modify it, do not request exclusions,
  and do not run alternative hook implementations. The probe resumes only if the security owner reviews and authorizes
  an exact implementation.
- **History only.** The steps below describe what P1-W would have checked. They are kept for that review, not for
  running.

1. Run `powershell.exe -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File files\dev-work\verification-gate\outputs\experiment-single-menu\Test-MenuWheelFeasibility.ps1 -Run Interactive -Mode Observe -Count 120`.
   Right-click the small window, open **Folder Icons (wheel experiment)**, rest the pointer on the icon list, roll the
   wheel down about five notches, then press Esc twice. Expected: the list does **not** scroll (the P1 FAIL), and the
   printed line shows `wheelSeen` greater than 0. A value of 0 means real wheel input never reaches the hook. Close the
   window.
2. Run the same command with `-Mode Navigate`. Roll the wheel down and up over the icon list.
   - Expected: the selection moves 3 items per notch and the list scrolls with it.
   - At the bottom it stops on Icon 120 without jumping back to the top, and wheel up returns to Reset to Default.
   - Moving the mouse afterwards re-highlights the item under the pointer.

   Click one icon. The printed `chosen=` names it, and nothing is applied.
3. Repeat step 2 with `-Count 45`, and with `-Count 120 -ColumnSize 30`.
4. Report, for each step, whether the wheel scrolled, any jump or wrong selection, and whether it felt acceptable. The
   log is `outputs/experiment-single-menu/results/wheel-interactive.log`.

A PASS proves only the isolated popup. Explorer would still need option B plus a hook inside Explorer (ADR 019 update).

## Opt-in automated checks

| Check | Enable with | Uses |
|---|---|---|
| `c-0002` C# harness, x64/x86 | `PFI_GATE_NATIVE_HARNESS=allow` after an authorized security review (see `GATE.md`) | Unsigned test executables built once per input set and reused from `cache/native-harness/` |
| `c-0004` installed COM dispatch | `PFI_GATE_INSTALLED_COM=allow` plus the harness opt-in | The live installation's registration and broker; fresh fixture folders only |

A build whose last launch was blocked is not launched again unless `PFI_GATE_NATIVE_RECLASSIFIED=<its sha256>` is
also set, after the security owner reclassified exactly that file.

Example, for one deliberate run only:

```powershell
$env:PFI_GATE_NATIVE_HARNESS = 'allow'
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File files\dev-work\verification-gate\verify.ps1 --mode focused --select c-0002
Remove-Item Env:PFI_GATE_NATIVE_HARNESS
```
