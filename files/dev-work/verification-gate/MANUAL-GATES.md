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

## M01 — Chooser reachability (coverage `PFI-M01`)

1. Right-click a disposable folder, open **Folder Icons > Choose Folder Icon**.
2. Note the display resolution and scaling. Count the rows visible without scrolling.
3. Try to reach the last icon with: the mouse wheel; the bottom scroll arrow; the keyboard (Up/Down, End).
4. Confirm **Reset to Default**, **Repair** and **Uninstall** stay reachable in the parent menu.
5. Apply the last (bottom-most) icon and confirm that exact icon is applied (dispatch).

Expected now: 21 rows. Record whether the list overflows on this display and which methods can reach every row.

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
