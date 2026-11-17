# Portable Folder Icons v0.2.0 — Architecture and Performance Redesign

Planning date: 2026-10-06. Status: **active plan** (designated during Phase 0 on 2026-11-16 at the user's direction; it supersedes the archived `files/plans/legacy-plan/Portable-Folder-Icons-v0.1.1-Implementation-Plan.md`). Execute one **Redesign Phase** per instruction and stop. This document grants no Git-write, merge, tag, or release authorization.

Location: `md-instructions/Portable-Folder-Icons-v0.2.0-Implementation-Plan.md`, the only active plan (user decision, 2026-11-16; moved byte-for-byte from `files/plans/`, see "Plan reconciliation"). Superseded plans are archived under `files/plans/legacy-plan/`. Amendments made on 2026-11-16 from Phase 0 evidence are marked **(Phase 0 amendment)**; those from the final Phase 0 reconciliation the same day are marked **(Phase 0 final)**.

## Authority and inspected baseline

Follow explicit current user instructions, this active plan, repository-native instructions, and `AI-WORKSPACE.md`, in that order. Durable product decisions remain in `md-instructions/Decisions.md`; current execution state belongs in `Handoff.md`. Preserve accepted outcomes of the old plan.

Read-only GitHub inspection verified `feature/v0.1.1` at `88007c5d92e4dcf0c5ff1f30c627dc9227cb43cc`, two commits ahead and zero behind `main` at `6cb6baea534f94ddc8cda4b950073dfa371f735d`. **(Phase 0 amendment)** The original text named this branch `feature/v0.2.0`; no `feature/v0.2.0` exists locally or on `origin` (`git ls-remote`, 2026-11-16). See "Branch, version and checkpoint policy". `d6b27b9` implements the scalable chooser; `88007c5` changes only Handoff to record the selection architecture gate. The remote tree contains no SelectionHandler or Phase 2 payload/harness implementation.

The attached local Handoff reports uncommitted Phase 2 C# broker/runtime/test work and a Windows PowerShell 5.1 PASS: 371 PowerShell assertions, 350 C# assertions, both architecture harnesses, installed x64 COM smoke, request cleanup and broker exit. These are historical reported results, not tests rerun by this planning chat. The October 6 structure map lists the broker source/build/artifacts, Selection module, and three additional test files. Their bytes and the Windows checkout's live Git status were unavailable here; Phase 0 must inspect them before implementation. Never rebuild Phase 2 from remote HEAD merely because local additions are absent there.

Two current user overrides are authoritative: **Phase 2 manual Explorer acceptance PASSED**; only ten public colour ICOs ship. The map shows personal icons already separated into `files/extra-ICO-files-for-use/custom`, including GitHub, whereas Handoff still describes 19 immediate source icons and a pending manual gate.

Committed code confirms potential costs, without establishing their measured contribution: `Invoke-PfiApply` reloads manifest/icon integrity per target; `Send-PfiExplorerRefresh` issues synchronous notifications, enumerates Shell windows, and performs away/back navigation with ten-second location/Busy deadlines per leg; `New-PfiAppliedIconResource` copies a GUID resource per Apply; Reset searches folder-prefix resources. Setup stages runtime/manifest/settings with rollback; Repair validates installed state without importing sources. The existing warned purge is not safe complete removal.

## Supersession and global invariants

On activation replace the old plan **in place** at `md-instructions/Portable-Folder-Icons-v0.2.0-Implementation-Plan.md`. Do not leave another active plan. Append superseding ADRs for navigation/GUID decisions and the interactive PowerShell boundary; retain historical ADRs. Remove the old configurable refresh-retry directive: no delayed retry setting or repaint-chasing fallback is required. Update tests that enforce superseded mechanisms while retaining their safety assertions. Permanent docs must stop guaranteeing that F5 or navigation fixes a warm view.

Preserve Windows 10/11, current-user/no-admin installation, offline operation and repository-independent `%LOCALAPPDATA%/Portable-Folder-Icons` runtime. No Explorer restart/kill, global cache deletion/reset, watcher, service, scheduled task, resident helper, production Python, C/assembly, or new runtime language. Shipped PowerShell remains 5.1 compatible. Preserve Repair, conservative ordinary Uninstall, deterministic verification and recoverable updates.

**(Final UX requirement, 2026-11-17; ADR 019/020)**
- **Explorer menu (final design):** one top-level **Folder Icons** entry with Reset to Default, Repair Portable Folder
  Icons and Choose Folder Icon. Choose Folder Icon holds one complete icon list reachable with the mouse wheel and the
  keyboard, preferably as a native submenu rather than a separate window. Uninstall is not part of the final menu.
- **Launchers (final design):** exactly two. `Setup_and_Run-Portable-Folder-Icons.bat` handles setup and repair;
  `Uninstall-Portable-Folder-Icons.bat` handles complete removal (Phase 7).
- **Until then:** the Phase 0B two-entry layout stays the working fallback until a menu-architecture decision, and the
  current Uninstall verb stays until the root uninstaller passes acceptance.
- **Still required:** Reset, Repair, tracking (Phase 6) and complete removal (Phase 7).

Preserve the classic nested chooser, accepted .NET Framework COM local-server broker, `IInitializeCommand`/`IObjectWithSelection`/`IExecuteCommand` selection contract, supplied array order and occurrences, no artificial selection cap, one invocation/request and aggregate result. Preserve Unicode/shell-sensitive paths, useful visible failures, silent normal all-success, and Developer Mode with identical functional outcomes. Sequential target mutations continue after independent failures; unrelated successes are never rolled back.

Preserve unrelated INI sections, fields, comments and attribute bits; malformed INI must fail safely. Avoid filesystem roots, protected paths, unsupported volumes/UNC, and unsafe reparse traversal according to the reconciled existing target policy. Do not expand supported targets incidentally. Cleanup requires exact registry/filesystem ownership, including COM collision checks.

The public inventory is exactly `Folder_Black.ico`, `Folder_Blue.ico`, `Folder_Gray.ico`, `Folder_Green.ico`, `Folder_Orange.ico`, `Folder_Pink.ico`, `Folder_Purple.ico`, `Folder_Red.ico`, `Folder_Teal.ico`, `Folder_Yellow.ico` under exact-case `files/ICO-Files`. Preserve custom/untracked/ignored assets in place. Custom icons are optional local inputs, never package requirements or implicitly staged assets. Setup must still accept arbitrary valid imports, with alphabetical menus and collision/invalid-file reporting; ten shipped icons is not a runtime cap.

## Shared execution and verification contract

Start each phase with machine, branch/HEAD/upstream/status, Handoff and this plan; then read only relevant components below and adjacent contracts. Record phase outcome, verification, measurements, architectural decision and exact next action in Handoff; update Decisions/Changelog when warranted. Preserve unrelated work. Commit/push only under explicit current authorization with reviewed exact paths, never blanket staging. Stop on unexplained branch changes, required failures, or an unresolved material contract.

Developer evidence, fixtures, builds and backups belong under repository `files/`; only actual installed behavior requires LocalAppData. Existing tests use OS temporary folders: reconcile their containment narrowly rather than expanding into a tooling refactor. Real installation/registry exercises are opt-in and back up exact owned state. Deterministic tests use isolated fixtures/registry roots, not users' folders.

Run focused checks during changes. Run the authoritative gate at each completed implementation phase boundary, not repeatedly during iteration:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify.ps1
```

**(Phase 0 amendment)** The repeatable entrypoint is now the verification gate, which runs the command above unchanged as check `c-0006` alongside the suite, the C# harness, Phase 0 diagnostics and the public-inventory check: `powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File files\dev-work\verification-gate\verify.ps1 --mode full` (manual: `files/dev-work/verification-gate/GATE.md`; Explorer checks: `MANUAL-GATES.md`). Add future tests as new gate checks and coverage rows, not a second runner. Endpoint security currently blocks the freshly compiled C# harness; the gate reports that as `BLOCKED_BY_ENDPOINT_SECURITY`, so no phase can claim a full PASS until an authorized security review decides how the harness may run. Any new compiled executable (for example a Phase 4 worker) inherits the same review requirement.

**(Phase 0 final)** The harness is now built once per set of build inputs and reused from the ignored `files/dev-work/verification-gate/cache/native-harness/` (x64 and x86 separately; key = harness source, broker bytes and assembly identity, compiler bytes/version, `csc.rsp`, `mscorlib.dll`, switches and target). A tampered, stale or incompatible build is never reused. Every verification entrypoint, including a direct `scripts/verify.ps1`, builds or reuses it and launches nothing unless the run is explicitly authorized (`-AllowNativeHarness` or `PFI_GATE_NATIVE_HARNESS=allow`), and a build whose last launch was blocked is not launched again until `PFI_GATE_NATIVE_RECLASSIFIED=<sha256>` acknowledges the security owner's reclassification. A cached build is not an approval: only an executed run is a result. Check `c-0007` covers this infrastructure (GATE.md).

**(Phase 0 final)** Development-artifact housekeeping (root `AGENTS.md`, Project-Specific Rules) applies at every phase boundary: record results durably, then clean `files/dev-work/verification-gate/outputs/` with `helpers/Remove-GateOutputs.ps1` and remove other disposable artifacts under `files/`; each phase report states what was cleaned, what was retained and why.

Extend this gate for changed C# source/build identity, architecture and contracts; do not fix expected assertion totals. Research-only Phase 8 needs document/whitespace checks. Report unavailable platform checks honestly. Final acceptance requires Windows 10/11 coverage and x64/x86 build/ABI plus appropriate activation evidence; one x64 smoke is insufficient for every compatibility claim. No silent support removal or unproven ARM64 expansion.

## Intended boundaries and operation contract

Keep JSON token/hash transport initially, including strict schema/action/hash, age, scope, reparse protection, atomic request creation, single-consumer processing, cleanup and independent invocations. Its hash checks integrity, not sender authentication. Preserve Reset registry name `Utility_0100_Reset`, Apply `PortableFolderIcons.Apply.NNNN`, action/property checks and 24-byte x64/16-byte x86 VARIANT layout unless actual source proves the contract changed.

One immutable invocation context owns effective installed settings, manifest, validated requested icon, helper initialization and ordered targets. Validate Apply's selected hash/cache once before writes; Reset must not depend unnecessarily on a healthy active icon manifest. Reject traversal or conflicting manifest identities. Prevent concurrent setup from producing a mixed runtime/settings/resource view using a short owned coordination boundary, not a long global batch lock.

Each target produces an occurrence-indexed result: persistent mutation committed or failed; rollback outcome; notification warning; later tracking outcome. Post-commit notification problems do not pretend the mutation failed or trigger rollback. `SHChangeNotify` returns no success acknowledgement; report calls issued/local errors, never verified repaint. Preserve duplicate occurrences in processing/results; deduplicate only shared validation and notifications.

Independent invocations must not lose concurrent writes. Introduce or retain bounded per-folder coordination through the write/rollback/tracking transaction; hold no second target lock while waiting. Timeout is a target failure with continuation. Fresh processes share no mutable invocation state. Overlapping clicks are serialized at the target, without promising global click order; nonoverlapping batches remain independent.

Preferred measured end state: small SelectionBroker → validated JSON → C# Operation Core/worker → sequential INI/attributes → batch notifications. Use the broker's verified framework/compiler compatibility and built-in libraries; ship validated binaries, not runtime compilation or downloads. PowerShell retains setup/config staging, Repair, Uninstall and developer verification. Maintenance Reset must reuse the authoritative operation implementation once C# is active.

## Redesign Phase 0 — Reorientation and accepted baseline

**Objective / scope:** establish recoverable local truth before redesign. Inspect native `.claude`/`.codex` instructions, relevant `.ai`, permanent docs, configuration, launchers, all actual SelectionHandler/Selection/dispatcher/batch sources, build manifest, installer, maintenance and tests.

**Requirements:** record branch, full HEAD, upstream/ref freshness, recent history, staged and unstaged diffs, untracked files and relevant ignored files; compare local/upstream/main without altering files or refs unless separately authorized. Identify exactly which Phase 2 changes are committed/pushed. Check broker framework, x64/x86 PE/assembly/version/source hashes, installed source/artifact identity, COM registration and request lifecycle. Inspect actual cache/applied inventory and settings separately from repository inputs.

Reconcile pending-manual/19-icon claims with the user's PASS and ten-colour policy. Inventory public/custom icons with hashes and Git classification; preserve mismatches, do not normalize files. Ensure custom assets cannot enter a public checkpoint accidentally; narrow ignore/package/verifier rules may be corrected without moving assets. Keep missing custom directories valid. Inspect whether optional import works today; schedule missing behavior in Phase 3.

**Verification:** run existing focused broker/registration-derived ABI checks, then full gate once. Confirm preserved files by hashes. Create a verified source/artifact/diff backup under `files/backups` when no authorized commit exists; include untracked Phase 2 implementation, exclude secret-bearing configuration from report output. Git checkpoint requires explicit source/binary/path authorization.

**Acceptance / stop:** baseline understood, recovered-from-backup procedure documented, automation green, manual PASS recorded without repeating the old checklist. Stop if local implementation is unavailable or cannot be reconciled safely. No architecture change or release work.

### Phase 0 outcome (2026-11-16) (Phase 0 amendment)

Executed as a separately scoped baseline-recovery assignment. Its local evidence (`files/dev-work/verification-gate/outputs/phase0-20261116/` and the gate run folders) was removed after the checkpoint commit; the results are recorded in this plan, `GATE.md` and Handoff.

- **Recovered, not regressed.** The uncommitted Phase 2 broker/batch implementation is present in the working tree and is the most complete implementation; the installed runtime and installed x64 broker are byte-identical to it (not to HEAD). A hash-verified pre-edit snapshot and a binary-safe worktree patch are preserved.
- **Automation.** PowerShell suite 371/371 (same as October). C# harness 358/358 inside the suite, 8 more than October's 350 because the inventory grew from 19 to 21 icons (4 assertions per registered contract). The focused x64/x86 harness was blocked by endpoint security, not by a test failure. `scripts/verify.ps1` fails only on the working-tree rename `LICENSE` → `LICENSE.LICENSE` (identical text).
- **Not achieved:** "automation green". Blocked by the endpoint-security decision and the LICENSE rename, both outside Phase 0 authority.
- **Inputs.** Setup reads only immediate `files/ICO-Files/*.ico`; `files/extra-ICO-files-for-use/` is not read. The 11 personal icons work today only because copies sit untracked in `files/ICO-Files`. The ten tracked colour ICOs are unchanged.
- **(Phase 0 final) Reconciliation, 2026-11-16.** `LICENSE` restored from the unintended `LICENSE.LICENSE` (normalized content = `HEAD:LICENSE`, no Git diff); BASELINE B-001/B-002 retired. Harness build cache, process-outcome classification (PASS / FAIL / CRASH / BLOCKED_BY_ENDPOINT_SECURITY / BLOCKED / NOT RUN), the `c-0004` wrapper stderr fix and regression check `c-0007` added. This plan moved to `md-instructions/`. Remaining blockers: the endpoint-security decision for the harness, and the M01 FAIL (Phase 0B). Checkpoint readiness and the proposed manifest are recorded in Handoff.

### Branch, version and checkpoint policy (Phase 0 amendment)

| Line | State on 2026-11-16 |
|---|---|
| v0.1.0 | Released: `main`, `origin/main` and tag `v0.1.0` at `6cb6bae`. |
| v0.1.1 committed work | `feature/v0.1.1` (local = origin) at `88007c5`: `d6b27b9` scalable chooser and version metadata 0.1.1; `88007c5` Handoff-only Phase 2 research gate. |
| Historical Phase 2 implementation | Uncommitted on the `feature/v0.1.1` working tree: COM selection broker, JSON payload, batch Apply/Reset, harnesses. Automated PASS 2026-10-01; user manual Explorer PASS in October. Never committed. |
| `feature/v0.2.0` | Does not exist locally or remotely. **(Phase 0B)** Created locally on 2026-11-16 from the Phase 0 checkpoint `ddbe65f` (local `feature/v0.1.1`, one commit ahead of `origin/feature/v0.1.1` at `88007c5`); not pushed. Phase 0B committed on it as `496b508` (2026-11-17, after manual M01 PASS; local only). |

1. **Checkpoint the accepted baseline first.** Before any v0.2.0 implementation edit, and only with explicit authorization naming the paths, commit the accepted Phase 2 working tree on `feature/v0.1.1`: runtime sources, broker source, build manifest and both binaries, tests, verifier, permanent docs, `.gitignore`, and the verification gate (`files/dev-work/verification-gate/` minus ignored `outputs/` and `cache/`). Exclude personal ICOs. **(Phase 0 final)** `LICENSE` is resolved; this active plan is included at `md-instructions/`, and the v0.1.1 plan is recorded as moved to `files/plans/legacy-plan/` (user decision, 2026-11-16). Record that this commit carries the October manual PASS for the then-installed configuration, not a new manual run, and that M01 (2026-11-16) is FAIL until Phase 0B.
2. **Create `feature/v0.2.0` from that checkpoint commit**, never from remote `88007c5`, which lacks the broker.
3. **Advance versions together, once.** In one dedicated commit at the start of the first phase that changes shipped runtime (not in Phase 0, not in a docs-only phase): `config.toml` `version`, `$script:PfiVersion` (manifest `productVersion`), the broker `AssemblyVersion` with a rebuilt build manifest and x64/x86 binaries, the expected `0.1.1.0` in tests/verifier, the setup banner, Changelog `## v0.2.0 — Unreleased`, Briefing, verifier version checks, and the gate's `@version`. The broker rebuild produces new unsigned binaries, so it needs the endpoint-security decision first. **(Phase 0B)** Phase 0B changes shipped runtime (`PortableFolderIcons.Integration.ps1`) but excludes a broker rebuild (its scope and the user's instruction, 2026-11-16), and versions must not advance independently; so it ships under the existing 0.1.1 metadata and the coordinated advance moves to the first phase that is authorized to rebuild the broker (after the endpoint-security decision), or to an explicit user decision.

### Defect register (Phase 0 amendment)

Classifications: SOURCE DEFECT, INSTALLATION/REGISTRATION DEFECT, ENVIRONMENT/DEPENDENCY DEFECT, WINDOWS SHELL/CACHE BEHAVIOR, UNVERIFIED. Evidence: gate check `c-0003` (re-runnable); the raw Phase 0 output folders were removed after the checkpoint.

| ID | Reported behaviour | Phase 0 result | Classification | Owner |
|---|---|---|---|---|
| D1 | Chooser shows only `ai`–`react`; remaining icons unreachable (**(Phase 0B)** implemented 2026-11-16; `c-0009` PASS on the Shell-built menu; M01 PASS 2026-11-16) | **M01 FAIL (user, 2026-11-16).** Discovery, validation, manifest, cache, registration, ordering and dispatch identity are correct (registry: 21 icon verbs, unchanged). **Cause established:** the Shell's static-menu builder (`SHCreateDefaultContextMenu`, fed an isolated copy of the product's own registry plan) includes **at most 16 entries per top-level static cascade, counted depth-first across all nested `ExtendedSubCommandsKey` submenus in key-name order**. Choose Folder Icon (1) + icons 0001–0015 = 16, exactly as in the screenshot; icons 0016–0021 are never added. Not a scrolling problem. Boundary measured: 12 icons show everything, 13 drops Uninstall, 14 drops Repair too, 21 drops all utilities and 6 icons. Nested alphabetical groups share the same budget (3×7 groups showed 2 groups only); a second top-level cascade gets its own 16. No Microsoft documentation found for this limit. | SOURCE DEFECT (design exceeds a WINDOWS SHELL limit; Phase 1's 30/50-icon tests checked the registry plan, never the Shell-built menu). Whether a Windows update since October changed the behaviour: UNVERIFIED | **Phase 0B (recommended next)** |
| D5 | Folder Icons shows only Choose Folder Icon; Reset, Repair and Uninstall missing (**(Phase 0B)** implemented 2026-11-16; utilities first and always present in `c-0009`; M01 PASS 2026-11-16. Visibility only: the D2/D3/D4 defects below are unchanged) | **M01 FAIL (user, 2026-11-16).** Same cause as D1: the utilities' keys (`Utility_0100…0300`) sort after `Choice_0100_Icons`, whose 21 children exhaust the 16-entry budget first. Registered correctly; present in the registry; not rendered. With 19 icons in October the same budget would also hide them; three Windows updates were installed since (KB5127647 23 Oct, KB5127690 30 Oct, KB5134133 13 Nov; build 26200.9725). | SOURCE DEFECT (entry order + budget). Regression vs latent: UNVERIFIED | **Phase 0B (recommended next)** |
| D2 | Reset does not reliably restore the default appearance | Persisted state and fresh-process Shell resolution return to the never-customized default for every standard case (plain, unrelated sections, preserved InfoTip, pre-existing ReadOnly, legacy v0.1.0, batch with duplicates, repeat Reset). Not reproduced at those layers. Separately found: Reset does not restore original folder ReadOnly ownership; ANSI desktop.ini non-ASCII text is corrupted (read as UTF-8, rewritten UTF-16LE); Reset removes any icon fields, including third-party ones. | Rendering: UNVERIFIED (M02, warm vs fresh view). Attribute ownership, ANSI corruption: SOURCE DEFECT | M02 first; Phase 2 (ANSI decoding, Reset rendering acceptance); Phase 6 (attribute ownership) |
| D3 | Repair does not reliably work | Repair is repository-independent and never reports false success on damaged copies, but: every failure message omits that Setup_and_Run is the fix; one missing/corrupt cached icon aborts re-registration for all icons; a missing runtime module fails before the dispatcher's try/catch, and the registered command runs `-WindowStyle Hidden`, so the user sees nothing; concurrent re-registration races in isolated registry roots (errors such as "subkey marked for deletion"), and Repair/Uninstall are static `MultiSelectModel=Player` verbs, so a multi-folder selection may start several Repairs. | SOURCE DEFECT (error reporting, recovery boundary, concurrency reproduced in isolation). One-process-per-selected-item in Explorer: UNVERIFIED (M03) | Phase 0A (after 0B, which first makes Repair visible again) |
| D4 | Ordinary Uninstall vs complete removal | Removes runtime/state/manifest/settings and owned registry; preserves cache and applied resources; customized folders keep working. The optional purge prompt deletes all of `icons/` with only a warning. | Behaviour as designed; purge prompt is the legacy warned purge (SOURCE DEFECT, safety) | Phase 7 |
| X1 | (found) Endpoint security blocks freshly compiled unsigned executables | WatchGuard blocked the focused C# harness (`35482483…`), later classified it trusted, then blocked the next run's harness (`b2eaad08…`). **Cause on the project side established:** the harness is rebuilt on every run, and the inbox compiler gives each build a new PE timestamp and MVID (the only 18 differing bytes), so every run is a new, unclassified program. Installed/repository broker binaries start. | ENVIRONMENT/DEPENDENCY DEFECT + verification design (rebuild per run) | **(Phase 0 final)** Build-once cache implemented (cached builds x64 `0a71577b…`, x86 `4f589ac4…`, never launched). Still open: security owner decision for those builds; Phase 4 decision |
| X2 | (found) Personal ICOs sit untracked in the public `files/ICO-Files` | Gate `c-0005` blocks staging them; custom directory is not imported | SOURCE DEFECT (import boundary) | Phase 3 |
| X3 | (found) BOM-less scripts with non-ASCII literals | Windows PowerShell 5.1 reads them as ANSI; the batch warning text `—` becomes mojibake | SOURCE DEFECT (minor) | Phase 0A if touched, else Phase 9 |

**Recovery boundary (D3).** Repair can rebuild only the HKCU registration (menu verbs and COM server) from the installed manifest, settings, runtime and broker. It validates, but cannot rebuild, runtime scripts, the broker, the manifest, settings and cached icons; those come only from rerunning `Setup_and_Run-Portable-Folder-Icons.bat` from a checkout. When the runtime itself is missing, the Repair verb cannot start; only Setup can help. Nothing requires administrator rights or manual dependency installation.

### Redesign Phase 0A — Maintenance reliability: Repair (Phase 0 amendment)

**Scope:** installed dispatcher maintenance paths (`Invoke-PortableFolderIcons.ps1`), `PortableFolderIcons.Maintenance.ps1`, and tests. No broker, Apply/Reset, notification, resource or registry-shape change.

**Requirements:** every Repair/Uninstall failure, including a missing or unloadable runtime module, produces one visible dialog in both modes; every Repair failure names what is wrong and states that double-clicking `Setup_and_Run-Portable-Folder-Icons.bat` restores the installation; concurrent Repair/Uninstall invocations are serialized by one short named per-user coordination primitive held only for the maintenance operation, and a second concurrent invocation shows no duplicate error; Repair's success dialog reports what it actually validated and recreated.

**Verification:** regression tests (fixture install copies, isolated registry roots) for each damaged scenario's message, the module-load failure path, and concurrent Repair processes producing zero registry errors and a complete final registration; existing suite and gate. Manual: M03 single and multi-folder Repair show exactly one result.

**Acceptance / stop:** Phase 0 `[FINDING]` items for D3 become passing assertions; no other behaviour changes.

### Redesign Phase 0B — Static-menu compatibility: restore utilities, reach every icon (implemented 2026-11-16; automated PASS; manual M01 PASS; working fallback, not the preferred final layout)

**(Phase 0 final)** Design approved by the user on 2026-11-16 as the next implementation phase; **not implemented**. It replaces the earlier "chooser grouping" proposal (probe E4: nested groups share the same budget, so grouping inside one top-level entry cannot work) and the picker-window alternative (out of scope for Phase 0B). Rationale: ADR 015.

**Observed compatibility constraint, not a Windows guarantee.** On this machine (Windows 11 build 26200.9725, probe of 2026-11-16, reproducible with `files/dev-work/verification-gate/tests/Test-PfiStaticCascadeMenu.ps1`; the raw probe output was removed after the checkpoint), the Shell's static-menu builder rendered at most **16 entries per top-level static menu entry**, counted depth-first across all nested `ExtendedSubCommandsKey` submenus in key-name order; later entries were silently dropped. No Microsoft documentation states such a limit. Implement it as one named budget constant, never describe it as documented Windows behaviour, and re-measure it with the Shell-builder check below on every Windows build where acceptance is claimed. Whether it changed with recent Windows updates is UNVERIFIED.

**Scope:** `Get-PfiRegistryPlan` layout and exact registry ownership and cleanup in `PortableFolderIcons.Integration.ps1` (setup, Repair, Uninstall), tests, the Shell-builder gate check, docs. No C# change and no rebuild of the production selection broker unless an independently justified dependency requires it (that would need separate approval and the endpoint-security decision). No Apply/Reset, notification, resource or broker-dispatch change. No picker window.

**Layout:**
1. **One primary Folder Icons submenu.** Its entries, in this order: **Reset to Default**, **Repair**, **Uninstall**, then **Choose Folder Icon** (cascade). Order by key name: rename only the chooser key (for example `Utility_0900_Choose_Icons`); `Utility_0100_Reset`, `Utility_0200_Repair` and `Utility_0300_Uninstall` keep their names (`Utility_0100_Reset` is the broker's canonical `IInitializeCommand` name).
2. **Reserved primary icon allotment.** Choose Folder Icon holds the first icons alphabetically, up to a fixed allotment of the budget minus the four non-icon entries: **12** (3 utilities + 1 chooser + 12 icons = 16). The allotment is reserved, not "filled until the Shell stops rendering", so utilities can never be displaced. With 0 accepted icons the chooser is omitted and the three utilities remain (ADR 011 behaviour). If an implementation review wants extra headroom below the observed 16, lower the single constant; the boundary sizes below then shift with it and must be derived from it.
3. **Overflow entries.** Icons beyond the primary allotment go to additional **top-level** static cascades, each holding at most 16 icons directly (no nested chooser, no utilities), labelled by the alphabetical range of the labels they contain (for example **Folder Icons: Purple – Yellow**), created in alphabetical order so they sort next to the primary entry, each with `MultiSelectModel=Player`, under exactly owned keys (`Directory\shell\PortableFolderIcons.More.NN` and `PortableFolderIcons.ContextMenu.IconChoices.MoreNN`). Probe E6/E7 validated utilities-first ordering and a second top-level cascade with its own budget in isolation.
4. **Every accepted icon stays reachable:** each appears exactly once across the primary chooser and the overflow entries; none is dropped or duplicated.
5. **Command identity and dispatch unchanged:** Apply verb keys (`PortableFolderIcons.Apply.NNNN`), `PfiAction`, `PfiIconHash`, `DelegateExecute`/CLSID and the broker request path stay as they are, so registration-derived broker and harness contracts are unchanged.
6. **Exact ownership across reinstalls:** setup and Repair create exactly the overflow entries the current manifest needs and remove obsolete `More.NN` parents and stores when a later installation has fewer icons; Uninstall removes all of them; keys the tool does not own, including lookalikes, are never touched.
7. **Installer unchanged in kind:** current-user (HKCU) only, no elevation, one click through `Setup_and_Run-Portable-Folder-Icons.bat`.

| Accepted icons | Primary chooser | Overflow entries (icons each) | Top-level entries |
|---|---|---|---|
| 0 | omitted | none | 1 |
| 1 | 1 | none | 1 |
| 12 | 12 | none | 1 |
| 13 | 12 | 1 (1) | 2 |
| 16 | 12 | 1 (4) | 2 |
| 21 | 12 | 1 (9) | 2 |
| 28 | 12 | 1 (16) | 2 |
| 29 | 12 | 2 (16, 1) | 3 |
| 45 | 12 | 3 (16, 16, 1) | 4 |
| 120 | 12 | 7 (16 × 6, 12) | 8 |

**Accepted trade-off:** every further 16 icons adds one top-level entry to the classic ("Show more options") context menu, so very large inventories clutter it (120 icons: 8 top-level entries). Accepted for Phase 0B. A single picker window would scale better, but needs a new broker action, new binaries and the endpoint-security decision; it is not part of Phase 0B and would need its own approval.

**Verification:**
(a) Registry-plan tests at 0, 1, 12, 13, 16, 21, 28, 29, 45 and 120 icons: every accepted icon exactly once; each top-level tree has at most the budget of entries counted depth-first; utilities present and first; chooser present only with at least one icon; overflow labels, order and `MultiSelectModel`; dispatch identity unchanged; shrinking inventories (for example 45 → 13 → 0) remove obsolete `More.NN` and never touch unowned or lookalike keys.
(b) **Rendered menus, not registry contents:** extend `files/dev-work/verification-gate/tests/Test-PfiStaticCascadeMenu.ps1` to build the product's actual plan with the Shell's own builder (`SHCreateDefaultContextMenu`, isolated GUID-named HKCU test keys, unregistered CLSID, nothing launched) at the same sizes and assert that every registered entry appears in the Shell-built menu; add it to the gate as a required check with a coverage row.
(c) Existing suite, `c-0003` diagnostics and the registration-derived harness contracts unchanged; the broker binaries keep their hashes.
(d) Manual M01 in real Explorer on this machine at the installed count: utilities present and first, every icon reachable by mouse without scrolling, and one Apply/Reset from an overflow entry.

**Acceptance / stop:** M01 PASS; Shell-builder check PASS at every listed size; no broker, binary or contract change. Phase 0A follows.

#### Phase 0B outcome (2026-11-16) (Phase 0B)

- **Implemented** on `feature/v0.2.0` as designed above and committed as `496b508` on 2026-11-17 after M01 PASS; specifics are in ADR 015's implementation follow-up. Product change only in `PortableFolderIcons.Integration.ps1`; installer, Repair and Uninstall code unchanged (they call the same registration functions); broker source and binaries unchanged (no rebuild). Versions stay 0.1.1 (see the version-policy amendment above).
- **Choices made inside the design latitude:** overflow labels follow the user's 2026-11-16 example, `Folder Icons (Purple–Yellow)` (en dash, no spaces), instead of the illustrative `Folder Icons: Purple – Yellow` above; a one-icon entry reads `Folder Icons (Name)`; each range end over 40 characters is shortened with an ellipsis. Menu order is case-insensitive invariant culture with an ordinal tie-break (same order as before for every current label). The `CommandFlags` separator moved from Reset (now first) to the chooser. Registration refuses more than 1596 icons (99 overflow entries) instead of dropping any.
- **Verification (Windows 11 build 26200.9725, Windows PowerShell 5.1):** suite 561 passed / 0 failed / 1 withheld harness (was 370); new required gate check `c-0009` (coverage `PFI-014`) 111 passed: budget re-measured at **16 of 40**, negative control detects the dropped entries, and the Shell-built menu exposes utilities first and every icon exactly once at 0, 1, 12, 13, 16, 21, 28, 29, 45, 120 and back down 45, 13, 0, then 29 twice (idempotent); `c-0003` updated for the new layout (test drift, safety assertions kept); full gate result in Handoff **Last verification**.
- **Not resolved by Phase 0B:** restoring visibility does not fix D2 (Reset rendering, ANSI `desktop.ini`, ReadOnly ownership), D3 (Repair, Phase 0A) or D4 (purge, Phase 7). M01 was FAIL before this phase.
- **Manual M01 PASS (user, 2026-11-16)** on the installed Phase 0B tree (verified byte-identical on 2026-11-17): utilities visible, chooser and all nine overflow icons reachable, Blue and Teal applied, no duplicate or stale entries. The user accepted the behaviour but **not** the two-entry layout as the final design; Phase 0B is the committed working fallback while a single-entry design is investigated.

#### Final menu UX requirement and single-menu feasibility (2026-11-17) (ADR 019)

**Requirement (user, 2026-11-17).** Explorer shows one top-level **Folder Icons** entry containing Reset to Default,
Repair Portable Folder Icons and Choose Folder Icon. Choose Folder Icon holds one complete icon list that can be
navigated and scrolled with the mouse wheel and the keyboard. The user strongly prefers a native Windows submenu over a
separate application window, and Uninstall leaves the menu (ADR 020). M01 PASS accepted Phase 0B's behaviour, not its
layout.

**Investigation scope.** Bounded and read-only: no production registry, installation, broker or Explorer change, and
no COM registration or new executable. Two isolated tests ran, the gate check `c-0009` and experiment E1 (an ignored
experiment folder retained for probe P1). Sources are Microsoft Learn pages read on 2026-11-17:
- [Choosing a static or dynamic shortcut menu method](https://learn.microsoft.com/en-us/windows/win32/shell/shortcut-choose-method)
- [Creating static cascading menus](https://learn.microsoft.com/en-us/windows/win32/shell/creating-static-cascading-menus)
- [Creating shortcut menu handlers](https://learn.microsoft.com/en-us/windows/win32/shell/context-menu-handlers)
- [Customizing a shortcut menu using dynamic verbs](https://learn.microsoft.com/en-us/windows/win32/shell/shortcut-menu-using-dynamic-verbs)
- [IExplorerCommand::EnumSubCommands](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nf-shobjidl_core-iexplorercommand-enumsubcommands)
- [Guidance for implementing in-process extensions](https://learn.microsoft.com/en-us/windows/win32/shell/shell-and-managed-code)
- [Add a File Explorer context menu command to a packaged app](https://learn.microsoft.com/en-us/windows/apps/desktop/modernize/integrate-packaged-app-with-file-explorer)
- [MENUINFO](https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-menuinfo)
- [MENUITEMINFO](https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-menuiteminfoa)
- [About Menus](https://learn.microsoft.com/en-us/windows/win32/menurc/about-menus)

**Documented (Microsoft).**
- **Static methods.** Static verbs are strongly encouraged: "resort to COM code-based solutions only when the static
  methods are insufficient." SubCommands requires the HKLM CommandStore, ExtendedSubCommandsKey works from HKCU, and
  `ECF_SEPARATORBEFORE` works only for top-level items. The COM Player selection model has no item limit. No item-count
  limit for cascades is documented.
- **Dynamic menu construction is in-process only.**
  - An IContextMenu handler is an in-process COM DLL (`InProcServer32`) registered under `shellex\ContextMenuHandlers`
    and run on the caller's thread, "usually Windows Explorer"; its `QueryContextMenu` inserts items into the HMENU.
  - IExplorerCommand: "Because this interface supports in-process activation only…".
  - `EnumSubCommands`: "Subcommands which themselves have subcommands are not supported."
  - Out-of-process activation exists only for invocation (DropTarget, `IExecuteCommand`/DelegateExecute, which is how
    the broker runs today).
- **Managed in-process code is unsupported.** "Microsoft recommends against writing managed in-process extensions to
  Windows Explorer … and does not consider them a supported scenario."
- **Windows 11 first-level menu** needs a native DLL exposing IExplorerCommand, registered through an MSIX or sparse
  package (package identity). Until then, classic entries stay under **Show more options**.
- **Menu display.**
  - MENUINFO.cyMax: "When the menu items exceed the space available, scroll bars are automatically used. The default
    (0) is the screen height." This conflicts with "About Menus": "When a menu contains more items than will fit in one
    column, the menu will be truncated."
  - `MFT_MENUBREAK` and `MFT_MENUBARBREAK` start a new column in a submenu or shortcut menu.
  - Standard keyboard interface: Up/Down select the previous or next item, Left/Right move between columns, a letter
    selects by access key, Enter chooses, Esc exits. No Microsoft statement about the mouse wheel in popup menus was
    found, and none documents a 16-item limit.

**Measured (isolated; not Explorer).**
- **Static cascades** (`c-0009`, build 26200.9725): 16 entries per top-level static cascade, re-measured at 16 of 40.
- **Dynamic submenu, experiment E1 (2026-11-17).** A Shell `SHCreateDefaultContextMenu` built with one read-only key
  that has no verbs, plus an in-process `IContextMenuCB` that inserts one popup (Reset, Repair, separator, N icons) on
  `DFM_MERGECONTEXTMENU`. This is the same insertion an IContextMenu handler performs.
  - **Result:** all N + 3 items were kept in order for N = 0, 1, 12, 13, 16, 17, 21, 28, 29, 45, 120 and 300, and a
    column break every 30 icons was preserved (1, 3 and 9 breaks at 45, 120 and 300 icons).
  - **Conclusion:** the 16-entry cap belongs to static-cascade enumeration, not to HMENU submenus, in this builder.
  - **Isolation:** nothing was invoked, written or registered.
  - **Deviation (first E1 run):** with no keys at all, DefCM fell back to the folder's real associations. Installed
    handlers (OneDrive, VS Code, VLC, 7-Zip, Acrobat, endpoint security) and the production Folder Icons verbs were
    loaded into the test PowerShell process for `QueryContextMenu`, read only. The run was corrected. `c-0009` is
    unaffected because it passes its own test key, and its artifacts show only test entries.

**Answers to the feasibility questions.**

| # | Question | Answer | Basis |
|---|---|---|---|
| 1 | 21+ icons in one submenu? | Static: **no** (16-entry cap). Dynamic HMENU: very likely yes. | `c-0009` measured; E1 isolated; Explorer not measured |
| 2 | Every icon reachable by mouse? | Static fallback: yes, across entries. Dynamic: **yes, with the scroll arrows** (P1, 120 icons). | User P1 PASS on an isolated popup; Explorer not measured |
| 3 | Mouse wheel? | **No** in the default user32 menu loop (P1 user FAIL; W1 Observe). Only a thread-local `WH_MSGFILTER` hook that turns wheel notches into Up/Down key messages made it work, in an isolated popup with synthetic input. | P1 and W1 below; real-hardware wheel with the hook pending (P1-W); Explorer not measured |
| 4 | Keyboard? | Up/Down: **yes**, and the menu scrolls to the selection (P1 user; W1 hit-test and capture). First-letter selection cycles through matching items (W1). Home/End: **no effect** (W1, posted keys; not in Microsoft's standard keyboard interface). | P1 user PASS for Up/Down; W1 synthetic for the rest |
| 5 | 45 and 120 icons? | On this 1920×1080 display at 96 DPI: 45 icons fit in one column (48 rows, no arrows). 120 in one column needs the scroll arrows (47 of 123 rows visible). 120 in 4 columns of 30 fits without scrolling (623 px). | W1 measured, isolated popup; other resolutions and scaling not measured |
| 6 | Scroll, truncate, columns, display height? | Scrolls above `cyMax` (default: screen height) per MENUINFO; "truncated" per About Menus; columns only when the handler sets breaks. Display-dependent. | Documented, conflicting |
| 7 | Broker reusable unchanged? | **Plausibly.** It validates only `Apply` + `PortableFolderIcons.Apply.NNNN` + 64-hex `PfiIconHash`, or `Reset` + `Utility_0100_Reset` (`ValidateCommand`). A handler could call `Initialize(name, bag)`, `SetSelection`, `Execute` on the local server. | Source read; unproven |
| 8 | New in-process COM extension required? | **Yes**, for any single complete native submenu. | Documented in-process-only APIs; static cap measured |
| 9 | Deployment, signing, WatchGuard, stability risks | See the list below this table. | Documented and project evidence (X1) |
| 10 | One-click, user scope, Repair, Uninstall? | Likely yes. Locked-DLL handling makes updates and removal more complex. | Hypothesis |

Risks for question 9:
- **New binary.** A new DLL is loaded into explorer.exe and into every process that shows a shell context menu,
  including 32-bit applications' file dialogs, which would need an x86 build. WatchGuard blocked new unsigned
  executables (X1), so each build needs classification or a code-signing decision.
- **Explorer stability.** A crash or hang in `QueryContextMenu` affects Explorer and the taskbar, so menu construction
  must be fast.
- **Language and toolchain.** Native C++ needs a toolchain that is absent here (no `cl`, `clang`, `gcc`, Visual Studio
  or .NET SDK; 2026-11-17) and breaks the "no C/assembly or new runtime language" invariant. Managed C# with the inbox
  compiler is unsupported in-process.
- **Locked DLL.** Explorer keeps the DLL loaded, so updates need side-by-side versioned files.

Notes for question 10:
- **Registration.** Per-user HKCU `InprocServer32` and `shellex` registration needs no elevation, and
  `EnforceShellExtensionSecurity` is not set on this machine (read 2026-11-17).
- **Repair** can re-register the handler.
- **Removal.** A DLL that Explorer still holds cannot be deleted without an Explorer restart, which is forbidden, or
  without elevation, which `MoveFileEx` delay-until-reboot needs. Removal can therefore be reported only as partial
  until the DLL is unloaded.

**Comparison** (A: Phase 0B two-entry static menu; B: single dynamic native submenu; C: one entry opening a compact
scrollable picker; D: hybrid, one static entry with Reset, Repair and Choose Folder Icon holding the first 12 icons and
"More icons…" opening the picker, which fits the 16-entry budget once Uninstall leaves the menu, ADR 020).

| Criterion | A | B | C | D |
|---|---|---|---|---|
| One top-level entry | no (1 + ⌈(n−12)/16⌉) | yes | yes | yes |
| Scrolling | not needed | user32 arrows (doc conflict) or columns | list control | static part none; picker yes |
| Mouse wheel | n/a | **no** natively (P1); only with a hook inside Explorer's UI thread (W1) | yes | picker yes |
| Keyboard | yes | yes (documented) | yes, plus type-to-find | yes |
| Personal ICOs, large inventories | up to 1596, more entries | unlimited in one list (E1: 300) | unlimited, with previews | unlimited |
| Multi-select | yes (broker) | yes if the handler forwards the selection (unproven) | yes (broker) | yes |
| Performance | static, no code at menu build | handler code on every right-click, in Explorer | extra window or process per choice | static plus picker on demand |
| Complexity | low (done) | high: in-process COM DLL, x64/x86, lifecycle | medium: new broker action and UI | medium |
| Install / Repair | unchanged | HKCU registration; locked-DLL updates | broker rebuild once | broker rebuild once |
| WatchGuard / security | no new binary | new DLL inside Explorer; classify or sign | rebuilt broker hash to classify | as C |
| Maintenance | low | high (Windows updates, two bitnesses) | medium | medium |
| Confidence today | high (`c-0009`, M01) | low–medium until an Explorer proof | high technically; not the preferred UX | high technically |

**Assessment.**
- **Native single menu.** Static registration cannot meet the requirement. A native single menu is plausible, since
  Explorer's own builder keeps long dynamic submenus, but only through a new in-process Explorer extension. That needs
  explicit exceptions to ADR 002, ADR 005 and the invariants above.
- **Wheel scrolling** is the weakest point. It must not be promised without the P1 result and an Explorer proof.
  **(Update 2026-11-17: P1 and W1 below.)** The native popup does not scroll with the wheel. Making it scroll needs a
  message hook inside the process and thread that runs the menu, which for Explorer means option B plus a hook.
- **Lowest-risk option:** A carries the least risk overall. Among options that meet the one-entry requirement, C or D
  carry the least risk because no code runs in Explorer.
- **Preference:** the user prefers B, so B should be proven or disproven before choosing C or D.

**Decision gate (user).**
1. **Optional manual probe P1, no approval needed:** **done by the user on 2026-11-17** (results below; the wheel
   FAILED).
   `files/dev-work/verification-gate/outputs/experiment-single-menu/Test-SingleMenuFeasibility.ps1 -Interactive -Count 120`,
   then `-Count 45` and `-Count 120 -ColumnSize 30`. It shows a native user32 popup in a PowerShell window, not Explorer.
   Record whether the wheel scrolls, whether scroll arrows appear, and whether Up/Down, Home/End and letters reach every
   item.
2. **Bounded proof phase, only if the user approves the in-process exception.** A justified, separately approved
   "menu-architecture proof" adds no production integration:
   - **Build:** one test-only context-menu handler named **Folder Icons (proof)**, registered in HKCU under test names
     and loaded by Explorer. Reset, Repair and N fixture icons, optional columns, forwarding to the unchanged broker
     on disposable folders only.
   - **Explorer gate:** manual checks at 21, 45 and 120 icons for mouse, wheel, keyboard, multi-selection, and
     unregistration and DLL-release behaviour.
   - **Prerequisites:** a language choice (native C++ with a toolchain installation, or Microsoft-unsupported managed
     C#); WatchGuard classification or signing of the test DLL; removal steps that accept a DLL Explorer may keep loaded
     until sign-out (no Explorer restart).
   - **Stop:** report, with no change to the production menu.
3. **Otherwise** choose C or D, which needs a broker rebuild and the endpoint-security decision, or keep A.

Phase 0A (Repair) remains the next functional phase whichever way this goes.

#### P1 user results and mouse-wheel experiment W1 (2026-11-17) (ADR 019)

**P1, run by the user on 2026-11-17 on this PC.** `Test-SingleMenuFeasibility.ps1 -Interactive` with `-Count 120`,
`-Count 45` and `-Count 120 -ColumnSize 30`: an isolated popup built by the Shell builder in a PowerShell window, not
Explorer. Basis: the user's screenshots and terminal output.
- **PASS:** one native submenu held the full inventory (the static 16-entry cap does not apply to this dynamically built
  menu); all 120 icons were reachable with the on-screen scroll arrows; keyboard Up/Down worked; the terminal recorded
  the selections Icon 013, Icon 040, Icon 035 and Icon 120.
- **FAIL:** the mouse wheel does not scroll the popup.
- **NOT PROVEN:** real Explorer integration; Home/End and access-key coverage; multi-column accessibility at other
  resolutions and scaling; production broker dispatch from a dynamic handler; WatchGuard acceptance of a new extension.
- P1 is therefore **not a complete PASS**: the wheel requirement is not met.

**Experiment W1, run by Claude on 2026-11-17: BLOCKED_BY_ENDPOINT_SECURITY.** Script:
`outputs/experiment-single-menu/Test-MenuWheelFeasibility.ps1` (ignored), now **deleted by WatchGuard**.

*Security incident.*
- **Detection.** WatchGuard Endpoint Security 360 (WES 360) reported "1 threat deleted" for
  `Test-MenuWheelFeasibility.ps1`: detection "Malware or potentially unwanted program (PUP)", action "Deleted". The user
  reported this from the WatchGuard notification.
- **Local read-only correlation.**
  - The experiment folder lost the file at 08:29:29 (UTC−6, 14:29:29Z).
  - WatchGuard's data folder gained quarantine record `7b16cb86-a9e5-4b25-ad38-861fa7b478c2` (13,894 bytes) and an
    updated quarantine index at 08:29:36.
  - The two automated runs had ended at about 08:25:32.
- **Not available locally:** the signature or rule name and the WatchGuard console incident identifier. The security
  owner can read them in the WatchGuard console.
- **Handling.**
  - Nothing was recreated, restored, renamed, encoded or moved, and no exclusion was requested.
  - No experiment process or hook remains: thread-local hooks end with their process, every run reported the hook
    removed, and no W1 process is running.
  - Explorer, the registry and the production installation were never touched.
  - The experiment stays stopped unless the security owner reviews and authorizes an exact implementation.

*What the script was designed to do* (from this session's source record; the file is gone and was not executed again):
- **Launch:** Windows PowerShell 5.1 with `-STA -ExecutionPolicy Bypass`. It compiled an inline C# block with
  `Add-Type`, which is dynamic compilation through the inbox `csc.exe`.
- **P/Invoke calls into user32:**
  - Hook: `SetWindowsHookExW(WH_MSGFILTER, managed callback, NULL, current thread)`, `CallNextHookEx`,
    `UnhookWindowsHookEx`.
  - Menus: `TrackPopupMenuEx`, `EndMenu`, `MN_GETHMENU`, `MenuItemFromPoint`, `GetMenuItemRect`, `GetMenuItemInfo`.
  - Windows and cursor: `EnumThreadWindows`, `GetClassName`, `GetCursorPos`, `SetForegroundWindow`.
  - Settings: `SystemParametersInfo`, read only.
  - Messages: `MapVirtualKeyW` and `PostMessageW`.
- **Messages it posted, all to its own windows:**
  - `WM_MOUSEWHEEL`;
  - `WM_KEYDOWN`/`WM_KEYUP` for Up, Down, Home, End, Enter and Esc;
  - `WM_CHAR` "I".
- **Hook behaviour:** in Navigate mode the hook consumed wheel messages and posted Up/Down key messages instead.
- **Screen capture:** `Graphics.CopyFromScreen` of its own menu window's rectangle, saved as PNG files (second version
  only).
- **Output:** text logs in the ignored `results/` folder.
- **What it never did:** no network access, registry write, persistence, other process, global hook, `SendInput` or
  Explorer interaction.

*What may have triggered the detection.*
- **Evidence.**
  - WatchGuard acted on the `.ps1` file itself, about four minutes after its second run. That run was the first of the
    version that added screen capture, cursor reads and hit-testing.
  - The earlier version (hook, posted messages and `Add-Type`, no capture) had run once without removal.
  - The P1 script, which uses `Add-Type`, P/Invoke and `TrackPopupMenuEx` but no hook, posted input or capture, is still
    present and unflagged.
  - WatchGuard's category is the generic "Malware or PUP".
- **Speculation, unconfirmed.**
  - The combination is typical of PowerShell keyloggers and spyware: `SetWindowsHookEx`, keyboard-message synthesis
    (`WM_KEYDOWN`, `MapVirtualKey`), screen capture and `Add-Type` launched with `-ExecutionPolicy Bypass`.
  - It is unknown whether the trigger was a static file scan, AMSI script content at run time, behaviour or a cloud
    classification, and which element mattered.
- **Production consequence (inference from the evidence).** A shipped wheel fix built from the same technique,
  including option B with a hook, would risk the same classification on users' machines. That strengthens the case
  against it.

*Experiment design (recorded before the deletion).*
- **Scope:** a plain HMENU (Reset, Repair, a separator, N icons) shown with `TrackPopupMenuEx` by a window of the test's
  own Windows PowerShell 5.1 process. It compiles in memory with `Add-Type`, the same path as P1, so there is no new
  executable. A `WH_MSGFILTER` hook is installed for that thread only (`hMod` NULL, current thread id) while the menu is
  open.
- **Excluded:** Explorer, the Shell builder, registration, global hooks, input injection, menu-window subclassing and
  undocumented messages.
- **Measurement:** documented calls only (`MN_GETHMENU`, `MenuItemFromPoint`, `GetMenuItemInfo` `MFS_HILITE`), plus
  captures of the menu window's own pixels.
- **Cases:** 45 icons, 120 icons, and 120 icons in columns of 30, each in Observe and Navigate mode, driven by posted
  (synthetic) messages.
- **Environment:** 1920×1080 (work area 1920×1032), 96 DPI as seen by the process, 3 wheel lines, wheel routing "mouse
  position".
- **Every run:** the hook was installed and removed, `EndMenu` closed the menu, and the watchdog never fired.

Results:
1. **Delivery.** Every posted `WM_MOUSEWHEEL` reached the hook with `MSGF_MENU`, whether posted to the menu window
   (`#32768`) or to the owner, which is the focus window.
2. **Default menu loop (Observe).** It ignores the wheel. After 46 notches the highlight and the visible rows were
   unchanged, and the capture still showed Reset … Icon 044. This reproduces the P1 FAIL on a plain HMENU.
3. **Translation (Navigate).** The hook consumes each wheel message (documented nonzero `MessageProc` return) and posts
   `SPI_GETWHEELSCROLLLINES` Up/Down key messages per notch. The selection moved and the menu scrolled to it:
   - 17 notches down: Icon 049 selected, rows Icon 004–049 visible.
   - To the end: Icon 120 selected, Icon 075–120 visible, down arrow disabled (capture).
   - Back up: Reset selected.
   - It clamps at both ends and never wraps, accumulates fine deltas (3 × −40 = one notch), works for wheel messages
     addressed to either window, and walks across columns in the 4-column menu.
4. **Keyboard extras.** Posted Home/End had no effect. First-letter `I` moved to the next matching item.
5. **Not established.** Real wheel hardware through the hook needed manual gate P1-W, which is
   BLOCKED_BY_ENDPOINT_SECURITY. `GetMenuItemRect` ignores the scroll offset (it reported rows 0–46 throughout), so only
   hit-tests and captures can measure scrolling.

**Answers to the wheel questions.**

| # | Question | Answer |
|---|---|---|
| 1 | Does `WM_MOUSEWHEEL` reach the modal menu loop? | Yes for posted messages (W1, every one, `MSGF_MENU`). Real hardware wheel: expected, because it is queued to the same thread, but unverified (P1-W is BLOCKED_BY_ENDPOINT_SECURITY). |
| 2 | Can it be handled reliably with documented APIs? | Only partly. Observing and consuming it are documented (`WH_MSGFILTER`, `MSGF_MENU`). No Win32 API scrolls a popup menu or selects an item in one (`HiliteMenuItem` "has no effect on menu items on menus"), so the only working route is posting keyboard messages, which Microsoft does not document as a way to drive a menu. It moves the selection, not the viewport, so any mouse movement re-highlights the item under the cursor. Reliable in W1's isolated, synthetic test, but not a documented contract. |
| 3 | Transferable to Explorer? | The menu behaviour is the same user32 code, so it probably carries over to Explorer's classic menu. The hook does not: `WH_MSGFILTER` "can only monitor messages passed to a menu … created by the application that installed the hook". In Explorer that means code inside explorer.exe on its UI thread, that is option B's in-process handler plus a hook it installs and removes. A hook installed from outside would inject into Explorer, which is prohibited. The Windows 11 first-level menu is not a user32 menu at all. |
| 4 | Thread-hook risks in Explorer? | High. While installed, the hook runs for every message of every menu on Explorer's UI thread, not only ours. IContextMenu has no "menu closed" callback for removing it. A fault, or an unload with the hook still set, takes down Explorer and the taskbar. It needs x64 and x86 builds and WatchGuard classification, and may conflict with other extensions' hooks. Microsoft: hooks "slow down the system … install a hook only when necessary, and remove it as soon as possible." **Measured here: WatchGuard deleted the W1 script that used this technique as "Malware or PUP".** |
| 5 | Is a custom scrollable picker safer? | Yes. A list control in an out-of-process window has documented wheel, keyboard and type-to-find behaviour, with no code in Explorer and no hooks. Cost: a new broker action and rebuild, plus the endpoint-security decision. |
| 6 | Native menu with arrows but no wheel? | Acceptable only as a fallback. As a single list it still needs the in-process handler, so the existing static Phase 0B layout (A) is the better fallback today. |

**Recommendation (for the user's decision; nothing implemented).**
- **Final design: option C.** It maps directly onto the reconciled menu: **Folder Icons** ▸ Reset to Default, Repair
  Portable Folder Icons, **Choose Folder Icon…**, which opens an out-of-process picker holding the complete list with
  wheel, keyboard and type-to-find.
- **D instead,** if one-click native access to the first 12 icons matters more than a single list.
- **Not B with a wheel hook** for production. It stacks a message hook on Explorer's UI thread and undocumented
  posted-key navigation on top of an in-process DLL. B without the wheel misses the requirement.
- **Keep A** until the replacement passes acceptance.

**Manual gate P1-W: BLOCKED_BY_ENDPOINT_SECURITY.** WatchGuard deleted its probe script. It could have settled
whether real wheel input reaches the hook. It may resume only after the security owner reviews and authorizes an exact
implementation, and it matters only if the user still wants to pursue B. The P1 results above stand: wheel FAIL,
on-screen scrolling PASS, keyboard arrows PASS, Icon 120 reachable.

## Redesign Phase 1 — Instrumentation and baseline

**Objective / scope:** attribute latency in broker, request reader, WSH/dispatcher, Core/Actions and installed test harness. Add development-only or Developer-Mode timings with negligible normal-mode overhead.

**Requirements:** use monotonic timing and invocation IDs. Separate broker activation (external harness before COM activation), selection enumeration, JSON/hash/write/read/delete, process startup, script/assembly loading, settings, manifest, icon lookup/SHA, target validation, INI read/parse/write, attributes, resource creation/cleanup, notification/PIDL work, Shell window enumeration, navigation/Busy/location waits and aggregate UI. Report nesting without double-counting; unobserved startup is an explicit residual. Count processes, reads/hashes, notifications, parents and resources as well as time.

Use installed normal-mode fixtures for 1/2/10/50/125+ targets, same-parent and multiple-parent selections, open/closed parent views, Apply and Reset. Run Blue → Red → Black → Green → Reset → another icon for at least ten cycles; compare early/late cycles and increasing historical-resource populations. Separate cold process starts from repeated warm filesystem/cache runs. Prefer five measured repeats per representative case; report median, range and individual slow runs, machine/build/runtime, resource counts and instrumentation overhead. Label synthetic, installed-COM and actual Explorer results separately.

**Verification:** timings must preserve selection, failures and silence. Controlled seams prove attribution/counters; explicit installed benchmark runner never runs in ordinary verification.

**Acceptance / stop:** compact baseline table and stage evidence explain fixed/per-target/per-parent/history-sensitive costs. Establish meaningful improvement/no-regression criteria from observed variation before Phase 2; no guessed millisecond targets. Missing measurements block performance claims.

## Redesign Phase 2 — Minimal notification and shared batch work

**Objective / scope:** simplify Actions refresh and batch dispatch; keep resources and language unchanged.

**Requirements:** remove normal-operation Shell window enumeration, matching, `Navigate2`, Busy/location polling, forced re-resolve tricks and retry machinery. Build invocation context once. After committed mutations, notify each changed folder once for item change and, when applicable, attribute change; describe actual INI create/update/delete where needed. Notify each unique affected parent once at batch completion, including successful targets in partial batches. An unchanged idempotent target needs no invented mutation event. Rollback failure that leaves changed state must be represented in invalidation and results.

Default experiment uses `SHCNF_FLUSHNOWAIT`, compared against `FLUSH` with the same events. Prefer asynchronous delivery if persistent/fresh-resolution gates pass. Neither flag proves repaint. Avoid association-change broadcasts on Apply/Reset; retain narrowly justified registration-change notification in setup/Repair/Uninstall. Use Unicode paths only within documented notification limits; retain PIDLs where necessary, free them deterministically, and never truncate long paths. Notification deduplication must not deduplicate target occurrences.

**Verification:** notification-plan/count tests, partial failure, duplicate targets, helper failures and allocation cleanup. Rerun baseline cases against installed runtime; confirm correct INI/resources/attributes and fresh Shell resolution. Record warm-view visuals separately; confirm windows/tabs/history/selection are no longer navigated by the tool.

**(Phase 0 amendment) Reset and INI preservation:** carry D2 into this phase. Use the M02 manual result as the before-state; acceptance repeats M02 on the new notification model for Apply and Reset and records fresh-view and warm-view rendering separately. Read existing `desktop.ini` the way Windows does (BOM when present, otherwise the ANSI code page) so ANSI non-ASCII content survives; the `ansi-nonascii` case in `c-0003` becomes a passing regression assertion. No delayed retry, forced navigation or Explorer restart is reintroduced to chase warm-view rendering.

**Acceptance / stop:** zero Explorer enumeration/navigation/polling, one shared context, parent-deduplicated work and explained measured improvement without persistence regressions. Supersede ADR 009 navigation obligations and old retry directive. Leave GUID resource model for Phase 3.

## Redesign Phase 3 — Immutable resources and import boundary

**Objective / scope:** Actions resource helpers, manifest/cache handling, setup import and lifecycle tests.

**Requirements:** experiment with absolute `icons/<full-content-sha256>.ico,0` references. Verify cache leaf, content identity and ownership; never overwrite different content at an existing hash name. Repeated same-icon Apply should reuse state and avoid needless writes when INI/attributes are already correct. Retain old hashes after source replacement/rename/rescan and ordinary uninstall. If direct references fail a persistent or fresh-resolution requirement, record evidence and use a deterministic folder-identity/content-hash resource; warm-view lag alone is not failure.

Stop generating fresh GUID copies after the winning experiment. Remove historical-resource enumeration/deletion from interactive Reset; do not purge `icons/applied`, even for Reset, merely because filename prefixes appear owned. Moved/copied folders or cached mappings can still depend on them. Historical reclamation belongs only to proven-safe maintenance; size alone does not establish safety.

Ensure setup's public source and optional local `files/extra-ICO-files-for-use/custom` import preserve arbitrary valid ICO support. Use one inventory/collision policy across configured sources, no recursion unless already supported; absence of custom inputs is valid. Public package/verifier inventory remains exactly ten. Repair never rescans repository sources.

**Verification:** first Apply, repeat Apply, colour sequence, Reset/repeat Reset, legacy generated references, unrelated INI, cache corruption, source changes, custom import, label collisions, rollback, Repair and uninstall/reinstall. Compare fresh-process resolution and a newly opened view; preserve old resources by hash. Benchmark Reset with growing legacy population.

**Acceptance / stop:** documented winning resource model, no click-driven unbounded growth, no interactive history scan, verified migration compatibility. Retain ambiguity rather than deleting resources.

## Redesign Phase 4 — Conditional compiled interactive core

**Objective / scope:** remeasure Phase 3, then migrate only if PowerShell startup/loading remains material against Phase 1 criteria. New Operation Core/worker filenames are implementation choices under `scripts/Windows`; existing broker stays small.

**Requirements:** record migrate-or-skip decision and dominant stages. If migrating, move request validation, invocation context, target/INI logic, SHA, attributes, transactions/results and notifications into reusable C#. Use a separate worker first, one worker per batch, ordinary compilation and installed framework compatibility. Keep JSON and broker lifetime initially unchanged.

Port behavior through fixture-based differential tests, not a broad rewrite. Preserve UTF-16LE INI output, unrelated content and malformed-input rejection. Restore original bytes/attributes on failed mutation; surface incomplete rollback and retain recovery evidence. Preserve existing-file identity initially; changing write strategy is a separate justified experiment. Check filesystem/INI reparse hazards and concurrent same-folder operations. Catch failures per occurrence and distinguish invocation validation failures from target failures.

Use a windowless executable in normal mode, direct process launch with token/hash arguments, no shell evaluation or WSH/PowerShell interactive dependency after successful migration. Initialize visible error handling early enough for settings/request/startup errors. Setup transactionally stages worker/core and artifact manifest, validates framework/PE/version/hashes and restores previous registration/runtime on failure; Repair validates them offline. Keep one operation engine; maintenance invokes it safely rather than retaining divergent production Apply/Reset code.

**Verification:** differential INI/result/rollback cases, x64/x86 build/ABI, registration-derived installed COM dispatch, corrupt/missing worker, request races/cleanup, overlapping selections, repository-independent install/Repair, update rollback and normal console suppression. Remeasure stage and end-to-end timings with identical fixtures.

**(Phase 0 amendment) Migration boundary clarified.** Migration happens only if Phase 1/3 measurements show PowerShell startup/loading is material against the agreed criteria. If it happens: launching **one worker process per batch** is part of this migration (the broker keeps launching, now the worker instead of WSH/PowerShell); moving execution **into the broker** to avoid launching a worker is deferred and is not part of Phase 4. Basic Developer Mode progress and visible errors must survive the cutover in the same commit; Phase 5 may then add bounded logs and refinements. The migrate-or-skip decision must also record the endpoint-security outcome: a new worker is another locally built unsigned executable (see X1), so it needs the same authorized decision (signing, path or reputation rule) before it can be the production path.

**Acceptance / stop:** measured improvement and semantic parity, or evidence-backed skip. Stop performance work when normal use meets measured criteria. Worker spawning, broker-hosted core, in-memory requests, NativeAOT and parallel writes remain deferred unless a later separately bounded task is authorized.

## Redesign Phase 5 — Diagnostic UX and bounded logs

**Objective / scope:** finalized worker or PowerShell dispatcher, installed settings and maintenance diagnostics.

**Requirements:** preserve visible Developer Mode diagnostics. If C# is active, allocate/attach a console only in Developer Mode, show phase/target timing and one aggregate completion, and retain it for explicit dismissal; this is an on-demand process, not a resident helper. Normal mode allocates no console and shows one useful scrollable result only for real errors/warnings. Window-cache lag alone produces no warning popup. Missing console/log capability never changes mutation results; use the aggregate UI for diagnostic access if needed.

Persist Developer Mode structured UTF-8 logs beneath installed `logs`, with invocation/occurrence/stage/result/rollback information and safe Unicode escaping. Bound retention to 20 files, 1 MiB each, and 20 MiB total; rotate safely across concurrent invocations. Include Repair/Uninstall; omit secrets and unnecessary source paths. Normal success performs no persistent diagnostic logging. Log failures cannot hide actual errors or block success. Config changes still require setup; Repair preserves installed settings.

**Verification:** mode parity, silent success/console-flash manual check, mixed failures, denied/full log storage, retention/concurrency, invalid settings and console fallback.

**Acceptance / stop:** diagnostic UX preserved, bounded evidence available, normal overhead measured. No refresh-retry configuration.

## Redesign Phase 6 — Durable customization tracking

**Objective / scope:** finalized operation engine and installed `state`; keep tracking separate from request transport.

**Requirements:** record successful Apply with identity, last-known path, resource hash/path, schema and owned attribute changes. Prefer volume/file identity where available; path fallback must be explicit and conservative. Preserve preexisting attribute ownership. Successful Reset removes the corresponding record; failed targets leave it intact. Duplicate occurrences collapse durable records, not results.

Use short coordinated state transactions and atomic replacement to prevent lost concurrent updates. A write-ahead intent protects crashes between mutation and tracking; promote it only after committed success. If tracking commit fails, restore that target or retain durable unresolved recovery state and report the failure. Never silently leave an untracked success that later authorizes purge. Corrupt/unknown-schema state is preserved, marks coverage incomplete and blocks unsafe cleanup; failed Apply must not enter successful tracking.

On explicit operations/maintenance, resolve same-volume identity if practical; otherwise report moved, renamed, deleted or unavailable conservatively. Never reset a different folder recreated at the old path. No recursive disk search, watcher or monitoring. Cross-volume moves/copies and historical customizations cannot be reconstructed reliably: mark legacy coverage incomplete when upgrading an installation with pre-tracking cache. Empty tracking never proves absence of old references.

**Verification:** repeated/duplicate/partial operations, simultaneous writers, interrupted commits, tracking I/O failure/corruption, rename/move/path reuse, deletion, unavailable volume and identity fallback.

**(Phase 0 amendment) Attribute ownership:** record whether the folder already had `ReadOnly`/`System` and whether `desktop.ini` pre-existed with its own attributes, so Reset and removal restore the original state (D2 found Reset clears pre-existing ReadOnly when it deletes `desktop.ini` and leaves tool-set ReadOnly otherwise). Record whether the icon fields replaced were third-party, so Reset can report, and removal can preserve, icons this tool did not apply.

**Acceptance / stop:** durable success state matches mutations; uncertainty survives restart and forbids destructive inference. Record recovery contract and coverage limits.

## Redesign Phase 7 — Safe complete removal

**Objective / scope:** setup launcher/menu, dispatcher, Maintenance, cleanup helper and finalized tracking/operation API.

**Requirements:** ordinary Uninstall removes exact owned menu/COM/runtime while preserving needed resources and recovery/tracking state. ~~Expose `REMOVE COMPLETELY` from repository setup and installed uninstall.~~ **(2026-11-17, ADR 020)** Complete removal is exposed only through the root `Uninstall-Portable-Folder-Icons.bat` (see "Dedicated complete uninstaller" below); setup and the Explorer menu do not offer it. Offer known-customization Reset; validate current identity, current tool-owned icon reference and attributes before changing anything. Preserve unrelated/third-party edits; changed ownership becomes unresolved, not permission to clear it. Continue after individual failures and aggregate results.

Prevent operations racing removal: short installation-maintenance coordination blocks new workers, accounts for running workers and protects their resources. No persistent coordinator or scheduled task. Remove executing binaries only after processes exit using a bounded helper. A legacy `-PurgeCache` flag must not bypass the same safety gate.

Delete only resources proven unnecessary after verified resets and complete tracking coverage. Unavailable targets, corrupt state, pending intents, unknown legacy references or copied references require preservation and useful incomplete-removal reporting. Preserve the minimum state needed to explain/recover them. Do not claim all historical folders were reset or all cache removed. No delete-anyway escape hatch; an old cache with unknown references may remain indefinitely.

**Verification:** both entry points, cancellation, ordinary uninstall, successful new-install complete removal, legacy upgrade, unavailable/moved/recreated targets, external INI edits, corrupted tracking, concurrent operations, cleanup-helper failure, exact registry collision guards and repeated uninstall/reinstall.

**(Phase 0 amendment) "Remove All Applied Folder Icons / Remove Completely" workflow.** This explicit operation (separate from ordinary Uninstall, which keeps its current conservative behaviour) must:

1. **Discover tracked applications** from Phase 6 state, resolving moved/renamed identities conservatively.
2. **Discover legacy applications made before tracking**, by verified signatures only, read from `[.ShellClassInfo]`: (a) `IconResource=<this user's install root>\icons\applied\<64 hex>-<32 hex>.ico,0` (current generated resources); (b) `IconResource=<install root>\icons\<64 hex>.ico,0` whose file content hashes to its name (v0.1.0 and shared-resource references); (c) prototype `Folder_<Color>.ico` references from the pre-release `Portable-Folder-Colours` tool, only after its exact signature is confirmed from history. Anything else, including edited, mixed or third-party values, is **foreign** and never changed.
3. **Preview read-only first:** counts by category (tracked-current, tracked-moved, legacy-generated, legacy-shared-cache, prototype, foreign, ambiguous, inaccessible, skipped by policy), with sample paths and the scan scope.
4. **Explicit scope and exclusions:** the user confirms the roots (default: accessible local fixed NTFS/ReFS volumes of the current user). Excluded by default and reported: Windows, Program Files, ProgramData, other users' profiles, `$Recycle.Bin`, System Volume Information, network/UNC, removable and offline media, reparse points (not followed), and cloud placeholders (never hydrated). Every skipped, inaccessible or unresolved location is listed.
5. **Mutate only after confirmation**, folder by folder, with the same INI preservation and attribute-ownership rules as Reset; continue after failures; keep a resumable journal under installed state so an interrupted removal can continue; report exact results.
6. **Preserve** unrelated `desktop.ini` settings, other tools' and other users' icons, and every resource still possibly needed.

**Evidence required before deleting an icon resource.** Delete a resource only when **all** hold: (1) **ownership**: its canonical path is inside this user's install root `icons/` tree, not a reparse point, and its name matches an owned pattern (`<sha256>.ico` with matching content, or `applied/<64 hex>-<32 hex>.ico`); (2) **complete tracking coverage**: tracking state readable at the current schema, no pending intents or unresolved records, and no "legacy coverage incomplete" flag; (3) **no tracked reference**: no tracked folder references it now, and every tracked folder that ever referenced it was verified during this operation to no longer do so; (4) **no discovered reference**: the confirmed-scope scan found none and reported zero inaccessible or unresolved locations within that scope; (5) **informed confirmation**: the preview listed it and stated that copies outside the scanned scope (other volumes, removable/offline media, network shares, archives, backups, other profiles) cannot be checked. An empty tracking file never proves absence, and a zero-hit scan never proves a shared resource unreferenced: an installation with icons applied before tracking keeps the "legacy coverage incomplete" flag, so its shared cache is preserved, and the result explains why. No blanket `desktop.ini` deletion, automatic elevation, global icon-cache reset or Windows-wide modification. Not implemented in Phase 0.

**(v0.2.0 requirement, 2026-11-17; ADR 020) Dedicated complete uninstaller.** It reconciles and replaces the
entry-point text above. The workflow, discovery signatures and resource-deletion evidence above still apply.

1. **Entry point.** `Uninstall-Portable-Folder-Icons.bat` at the repository root, beside the setup launcher. It runs
   on double-click, uses Windows PowerShell 5.1, and needs no Python, no manual PowerShell and no parameters. The
   final application has one setup/repair launcher and one complete-uninstall launcher. Reset and Repair stay in
   Explorer; Uninstall leaves the final menu.
2. **Flow.** DISCOVER → VERIFY OWNERSHIP → PREVIEW → CONFIRM → RESTORE → VERIFY → CLEAN UP → REPORT. The preview shows
   real counts per category and scope. A Y/N prompt follows. Nothing is modified before Y, and cancelling is always
   possible.
3. **Discovery sources.** Tracking records, previous manifests, verified legacy signatures (never invented), cache
   references and per-folder resources across accessible local fixed drives, so the current manifest is not the only
   source. No network shares. Junctions and symbolic links are never followed. No automatic elevation. Inaccessible
   system areas only with an approved scope.
4. **Safe restore.**
   - Preserve unrelated `desktop.ini` settings, other applications' and user icons, ambiguous references, original
     attributes, system customizations and the file's encoding.
   - Skip and record any folder that cannot be restored safely.
   - Never delete a whole `desktop.ini`, never reset the icon cache, never restart Explorer.
5. **After confirmation.**
   - Keep a change journal (resumable after interruption), verify each restore, and report per-folder failures.
   - Keep resources that are still referenced.
   - Remove registrations, runtime and cache only when proven safe.
   - Report partial completion accurately, never claiming more than was verified.
   - Never delete the uninstaller's own source repository.
6. **One implementation.** No competing Uninstall implementations. Reuse the useful internals: exact registry
   ownership, Reset's INI and attribute rules, Phase 6 tracking. The Explorer Uninstall verb and the legacy
   `-PurgeCache` purge stay until this launcher passes acceptance, and are then retired in the same phase.
7. **Future tests (isolated fixtures only).**
   - Tracked and legacy folders, and mixed or foreign references.
   - Inaccessible folders and reparse points.
   - Interruption, cancellation, partial completion and repeat runs.
   - Missing manifests or caches.
   - ANSI, UTF-16 and UTF-8 encodings, and attribute ownership.
   - Resource safety (shared, copied, referenced elsewhere) and clean installs.

   A full uninstall acceptance needs an explicitly authorized manual gate, never real user folders.
8. **Open design points.**
   - Read literally, "never delete a whole `desktop.ini`" also keeps a file this tool created that is empty after
     restore.
   - How the launcher locates the installed runtime and journal when run from a checkout.
   - Scan duration and progress on large drives.
   - If a native menu handler is ever adopted (ADR 019), removal must report a DLL that Explorer still holds.

   Not implemented; no PC-wide scan has been run.

**Acceptance / stop:** no remaining folder knowingly loses a required resource; residuals and reasons are explicit; unrelated files survive.

## Redesign Phase 8 — Deferred research closure

**Objective / scope:** concise Decisions/Handoff entries only.

**Requirements:** close old Admin/modern-menu research obligations using sources below. Elevation cannot be assumed to solve Explorer caching; weigh protected targets/machine-wide installation against portability. Modern Windows 11 integration requires a separately evaluated native `IExplorerCommand` deployment/identity/signing path; a future tiny shim must hand operations out of process. Examine current packaging requirements only far enough to record costs, per-user feasibility and no-restart deployment uncertainties. No prototype, HKLM writes or production dependency.

**(2026-11-17)** The classic-menu side of this research was advanced early by the single-menu feasibility
investigation (ADR 019; Phase 0B section). Any native in-process handler work now goes through that decision gate,
not through this phase.

NativeAOT, worker-to-broker hosting and in-memory transport remain backlog items only if finalized measurements identify material startup/transport delay. Do not undertake their toolchain research when those stages are immaterial.

**Verification / stop:** short sourced recommendation with explicit deferred status; no production changes.

## Redesign Phase 9 — Documentation, review and final acceptance

**Objective / scope:** README, config, four permanent docs, verifier and complete shipped runtime/package.

**Requirements:** confirm all version metadata reads 0.2.0 (advanced together per "Branch, version and checkpoint policy"; Changelog `## v0.2.0 — Unreleased`) and matches actual PowerShell/C# and selection support. **(Phase 0 amendment: the original text said "0.1.1 Unreleased", which predates the v0.2.0 renaming.)** Record superseding ADRs, winning notification/resource model, benchmark comparison, recovery/removal limits, custom import and Developer Mode. Keep Handoff concise and current; do not replay investigation history. Perform systematic review in a fresh context or independent reviewer workflow, covering COM lifetime/marshalling/bitness, quoting/Unicode/long paths, large/overlapping selections, ownership, INI/attributes/rollback, resources, tracking, setup/Repair/uninstall, configuration, silence, hardcoded paths and forbidden network/background/Explorer/cache behavior. Every critical defect needs regression coverage. Nested C# and all shipped components belong in security/build verification.

**Verification:** focused fixes first, then authoritative full gate on exact candidate source/artifacts; validate public package with precisely ten colour icons and no required personal inputs. Compare Phase 1/2/3/4 timings and repeated-operation trends; explain any residual slowdown. Final Windows manual gate covers real-menu 1 and 125+ batches, multi-parent/partial/overlapping operations, Unicode paths, silence/developer UX, unchanged Explorer tabs, fresh-view rendering, custom import/overflow, repository-independent Repair, rollback and both removal modes with preserved unrelated INI. Use disposable fixtures. This is redesign acceptance, not repetition of the already-passed old Phase 2 gate.

**Acceptance / stop:** automation green, no unresolved critical defects, review findings recorded. Stop for user manual results and explicit final integration approval. Do not delete the active plan, merge, tag or release here. Promote lasting decisions and retire the temporary plan only during the subsequently authorized closure workflow.

## Plan reconciliation (Phase 0 amendment)

| Copy | Identity | Status |
|---|---|---|
| `md-instructions/Portable-Folder-Icons-v0.2.0-Implementation-Plan.md` | **(Phase 0 final)** Moved byte-for-byte from `files/plans/` on 2026-11-16 (SHA-256 `615ed1cd…` before and after the move; edited afterwards only by the marked Phase 0 final amendments). That pre-move copy was the 2026-10-06 plan (`9d7d5e3e…`, preserved in the Phase 0 snapshot) plus three Phase 0 amended lines; no other content differed | **Active** (only v0.2.0 copy) |
| `files/plans/legacy-plan/Portable-Folder-Icons-v0.1.1-Implementation-Plan.md` | Byte-identical to committed `HEAD:md-instructions/Portable-Folder-Icons-v0.1.1-Implementation-Plan.md` (SHA-256 `838c1f29…`, blob `3dc937bc`); the `md-instructions/` copy is deleted in the working tree (moved, not edited) | Superseded; archived (user decision) |
| `files/test-logs/reorientation-2026-10-01/HEAD-88007c5/md-instructions/…v0.1.1…` | Archived evidence copy inside an exact-HEAD export; same text with CRLF line endings | Evidence only |

Material differences from v0.1.1: the configurable delayed refresh retry (old Phase 3) is removed; forced Explorer navigation is removed (Phase 2); measurement precedes optimization (Phase 1); immutable shared resources are tested (Phase 3); a C# worker is conditional on measurement (Phase 4); logs/tracking/removal move to Phases 5–7; research merges into Phase 8; the public inventory is fixed at ten colour ICOs with optional local imports.

**(Phase 0 final) Decided by the user, 2026-11-16:** (1) this plan lives at `md-instructions/` (executed); (2) superseded plans are archived under `files/plans/legacy-plan/`, so the checkpoint records the v0.1.1 plan as moved there from `md-instructions/` (its text is unchanged).

## Research anchors

Checked 2026-10-06; these settle API contracts, not Windows benchmark results. Resource and batching choices above are design hypotheses with explicit experiments.

- [SHChangeNotify](https://learn.microsoft.com/en-us/windows/win32/api/shlobj_core/nf-shlobj_core-shchangenotify): delivery flags, event meanings, void return and path/PIDL limits.
- [Desktop.ini customization](https://learn.microsoft.com/en-us/windows/win32/shell/how-to-customize-folders-with-desktop-ini): Unicode INI, hidden/system INI and folder customization attributes.
- [Selection model](https://learn.microsoft.com/en-us/windows/win32/shell/context-menu-handlers): legacy Player limit versus uncapped COM Player; retained static cascade.
- [IExecuteCommand](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nn-shobjidl_core-iexecutecommand), [IObjectWithSelection](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nn-shobjidl_core-iobjectwithselection), [IShellItemArray](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nn-shobjidl_core-ishellitemarray), [IInitializeCommand::Initialize](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nf-shobjidl_core-iinitializecommand-initialize): retained selection and initialized registry-name contracts.
- [Classes and servers](https://learn.microsoft.com/en-us/windows/win32/com/classes-and-servers), [LocalServer32](https://learn.microsoft.com/en-us/windows/win32/com/localserver32): per-user COM store, executable/default-value quoting and activation lifetime.
- [Modern Explorer commands](https://learn.microsoft.com/en-us/windows/apps/desktop/modernize/integrate-packaged-app-with-file-explorer): native DLL, package/sparse identity, manifests and architecture; deferred from this redesign.
- [RightClickTools](https://github.com/LesFerch/RightClickTools), including its native handler/build: useful thin integration/operation separation; its packaging/elevation paths are not this project's portable baseline.
- [FolderColorizer source](https://github.com/OmgDezzz/FolderColorizer/blob/601e3b5c58872d31e614c73bf1250acbf0357f91/MainWindow.xaml.cs): shared resource references are an implementation pattern; Explorer termination, INI replacement and swallowed errors disqualify copying its behavior.
- [Folcolor source](https://github.com/kweatherman/Folcolor/blob/main/src/Controller/FolderColorize.cpp): preservation concerns support retaining the tested editor; its association-change/global broadcast strategy does not meet the interactive notification policy.
