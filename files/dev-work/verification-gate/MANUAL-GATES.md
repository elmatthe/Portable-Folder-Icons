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

1. With one folder selected, choose **Repair Portable Folder Icons**. Record whether a console flashes and the
   exact result dialog text.
2. With five disposable folders selected, choose Repair once. Record how many result dialogs or error dialogs
   appear (one per folder would confirm that Explorer starts one process per selected item).
3. Do not corrupt the live installation to test failures; automation covers damaged copies.

## M04 — Uninstall prompt with several folders (coverage `PFI-M04`, observe only)

With three disposable folders selected, choose **Uninstall Portable Folder Icons** and count the confirmation
dialogs. Answer **No** to every prompt. Nothing is uninstalled.

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
