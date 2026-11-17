# Portable Folder Icons — Decisions (ADR Log)

Append-only record of non-obvious design decisions and their reasoning. Newest
entries appear first.

---

## 020 — Complete removal only through a root Uninstall launcher; Uninstall leaves the Explorer menu — 2026-11-17 — Claude

**Status:** Accepted requirement (user, 2026-11-17). Design and implementation pending (reconciled Phase 7); nothing
implemented. Until the replacement passes acceptance, the current Explorer Uninstall verb and the legacy warned purge
stay as they are.
**Context:** The final application should have one setup/repair launcher (`Setup_and_Run-Portable-Folder-Icons.bat`)
and one complete-uninstall launcher. Reset and Repair stay in Explorer. The plan's Phase 7 offered "remove completely"
from both setup and the installed Uninstall, and Phase 0 found that the installed purge deletes `icons\` with only a
warning (D4).
**Decision:** Complete removal lives only in a root `Uninstall-Portable-Folder-Icons.bat`. It runs on double-click,
like setup, with Windows PowerShell 5.1, no Python, no manual PowerShell and no parameters. The Explorer menu drops
Uninstall (final menu: Reset to Default, Repair, Choose Folder Icon; ADR 019). The flow is DISCOVER → VERIFY OWNERSHIP
→ PREVIEW → CONFIRM (Y/N) → RESTORE → VERIFY → CLEAN UP → REPORT:
- **Discover** from tracking records, previous manifests, verified legacy signatures (never invented), cache
  references and per-folder resources across accessible local fixed drives, so the current manifest is not the only
  source. Network shares, junctions and symbolic links are not followed, there is no automatic elevation, and
  inaccessible system areas need an approved scope.
- **Preview** shows real counts, and nothing changes before a Y answer. Cancelling is always possible.
- **Restore** preserves unrelated `desktop.ini` settings, other applications' and user icons, ambiguous references,
  original attributes, system customizations and the file's encoding. A folder that cannot be restored safely is
  skipped and recorded. The uninstaller never deletes a whole `desktop.ini`, never resets the icon cache and never
  restarts Explorer.
- **After confirmation** a change journal is kept, each restore is verified, per-folder failures are reported, and
  resources still referenced are kept. Registrations, runtime and cache are removed only when proven safe, partial
  completion is reported accurately, and the uninstaller's own source repository is never deleted.

There is one implementation; useful internals (registry ownership, Reset's INI rules) are reused. Legacy paths are
retired only after the replacement passes.
**Alternatives considered:** Keeping complete removal in the menu (an Explorer verb is a poor host for a long,
confirmed, journalled operation, and it multiplies under multi-selection, D4/M04). Keeping two entry points, setup and
installed Uninstall (competing implementations).
**Consequences:** Phase 7 depends on Phase 6 tracking for safe restores; legacy coverage stays incomplete without it.
Acceptance needs isolated fixtures plus an explicitly authorized manual uninstall gate, never real user folders. Open
design points for Phase 7:
- Read literally, "never delete a whole `desktop.ini`" also keeps a file this tool created that is empty after
  restore.
- How the launcher finds the installed runtime when it runs from a checkout.
- Scan duration on large drives (the preview states the scope).

## 019 — Final menu: one Folder Icons entry; Phase 0B static layout stays the fallback; native single submenu needs an in-process extension — 2026-11-17 — Claude

**Status:** Requirement accepted (user, 2026-11-17). Architecture decision **pending user review**. Phase 0B (ADR 015)
remains the committed working fallback (M01 PASS), not the final design.
**Context:** The user wants one top-level **Folder Icons** entry with Reset to Default, Repair Portable Folder Icons
and Choose Folder Icon. It should hold one complete icon list with mouse-wheel and keyboard navigation and scrolling,
and the user strongly prefers a native Windows submenu to a separate window. Uninstall leaves the menu (ADR 020).
**Findings, 2026-11-17** (details, sources and comparison: plan, "Final menu UX requirement and single-menu
feasibility"):
- **Documented.**
  - Static verbs (SubCommands, which needs HKLM; ExtendedSubCommandsKey, which works from HKCU) are the only
    no-code cascade. Every dynamic menu route runs inside the caller, usually Explorer: an IContextMenu handler is an
    in-process COM DLL, and IExplorerCommand "supports in-process activation only", with one subcommand level.
    Out-of-process activation exists only for invocation (DelegateExecute/IExecuteCommand, DropTarget), not for building
    a menu.
  - Microsoft "recommends against writing managed in-process extensions to Windows Explorer and does not consider them
    a supported scenario."
  - The Windows 11 first-level menu needs a packaged or sparse-package native IExplorerCommand DLL.
  - Win32 menus can scroll: MENUINFO.cyMax says scroll bars are used "when the menu items exceed the space available",
    although "About Menus" says such a menu "will be truncated". They can split into columns with
    `MFT_MENUBREAK`/`MFT_MENUBARBREAK`, and have a standard keyboard interface (Up/Down item, Left/Right column, access
    key, Enter, Esc).
  - No Microsoft statement on mouse-wheel scrolling of popup menus was found.
- **Measured, isolated, not Explorer** (experiment E1 on Windows 11 build 26200.9725). The same DefCM builder that caps
  static cascades at 16 (`c-0009`) kept every item of one dynamically inserted submenu: Reset, Repair, a separator and N
  icons for N = 0 to 300, in order, with column breaks intact.
- **Hypotheses, unverified.**
  - Explorer adds no cap to a handler's submenu.
  - IExplorerCommand subcommands may share the static 16-cap.
  - The wheel may not scroll tall context menus (developer forum reports), while scroll arrows and the keyboard do.
    **(Confirmed for an isolated popup by P1 and W1, 2026-11-17; see the update below.)**
  - The broker could be reused unchanged: a handler calls `IInitializeCommand::Initialize` with an Apply/Reset name and
    a property bag holding `PfiAction`/`PfiIconHash`, then `SetSelection` and `Execute`, which are the only contract
    `ValidateCommand` checks.

**Decision (pending):** A single complete native submenu is not achievable with static registration. It requires a new
in-process Explorer extension, which conflicts with ADR 002, ADR 005 and the plan's invariants ("no … C/assembly, or
new runtime language"; compiled extension rejected). It can proceed only with the user's explicit approval of:
- an in-process exception: native C++, which needs a toolchain this machine lacks, or managed C# built with the inbox
  compiler, which Microsoft does not support in-process;
- a new DLL loaded into Explorer and every process that shows a shell context menu, classified by WatchGuard or
  signed;
- Setup, Repair and the uninstaller handling a DLL that Explorer keeps locked;
- a manual Explorer acceptance gate.

The recommended first step needs no approval: the user-run probe P1 (wheel, keyboard and scroll on a native user32
popup with 45 and 120 items).
**Alternatives considered:**
- (A) Phase 0B two-entry static layout: works today, no new risk, but not one entry.
- (C) One entry opening a compact picker window: scrolls and searches natively, out of process, no Explorer code. It
  needs a new broker action (the broker accepts only Apply/Reset), so a rebuild and a WatchGuard decision, and it is
  not the native submenu the user prefers.
- (D) Hybrid: one static entry with Reset, Repair and 13 icons plus "More icons…" opening the picker.
- Send To subfolder: not top-level, pollutes the user's Send To folder.
- Packaged Windows 11 menu: native DLL plus package identity and signing; Windows 10 differs.

**Consequences:** No architecture change until the user decides. Phase 0A stays the next functional phase.

**Update 2026-11-17: P1 user results and wheel experiment W1** (details: plan, "P1 user results and mouse-wheel
experiment W1").
- **P1, user-run on an isolated Shell-built popup, not Explorer.**
  - PASS: one submenu held the full inventory, all 120 icons were reachable with the scroll arrows, and keyboard
    Up/Down worked (selections Icon 013, 040, 035 and 120 logged).
  - **FAIL: the mouse wheel does not scroll it.**
  - Not proven: Explorer integration, Home/End and access keys, columns at other resolutions and scaling, broker
    dispatch from a dynamic handler, WatchGuard acceptance.
  - Not a complete PASS.
- **W1, isolated, synthetic input, thread-local `WH_MSGFILTER` in the test process.**
  - Wheel messages reach the menu's modal loop (`MSGF_MENU`) but the default loop ignores them.
  - Consuming them and posting Up/Down key messages scrolls the menu by moving the selection, clamped and without
    wrapping.
  - No documented API scrolls a popup menu, so this relies on posted keyboard messages, an undocumented way to drive a
    menu.
  - In Explorer it would need a hook on Explorer's UI thread installed by in-process code, which is option B plus a
    hook.
  - **BLOCKED_BY_ENDPOINT_SECURITY.** WatchGuard Endpoint Security 360 deleted the W1 script as "Malware or
    potentially unwanted program (PUP)" at about 08:29 (local quarantine record `7b16cb86-…`). It used a thread hook,
    posted keyboard messages, `Add-Type` and screen capture. The trigger is unconfirmed.
  - It is not recreated or continued without the security owner's review of an exact implementation. Real wheel
    hardware through a hook (gate P1-W) stays unverified.
  - A production wheel hook would risk the same classification on users' machines.
- **Effect on the decision (still pending the user).** A native submenu meets the wheel requirement only through that
  hook, so B is weaker than first assessed. Claude recommends C as the final design (Choose Folder Icon… opens an
  out-of-process picker with the complete list), D if quick native access to 12 icons is wanted, and A as the fallback
  until then. A native menu with arrows but no wheel is acceptable only as a fallback.

## 018 — Tracked root CLAUDE.md adapter that imports AGENTS.md — 2026-11-16 — Claude

**Status:** Accepted (user requirement: Claude Code instruction portability)
**Context:** The only Claude Code instruction file was the gitignored `.claude/CLAUDE.md` (Open Issue 20). Claude Code
documentation (code.claude.com, "Memory", via Context7 on 2026-11-16): relative `@` imports resolve against the file
that contains them, so its `@AGENTS.md` pointed at a non-existent `.claude/AGENTS.md`; when any `CLAUDE.md` exists,
Claude Code reads the `CLAUDE.md` files instead of `AGENTS.md`; project files may sit at `./CLAUDE.md` or
`./.claude/CLAUDE.md` and all discovered files are concatenated. A fresh checkout had no Claude adapter at all, and
this checkout's sessions did not receive `AGENTS.md` automatically.
**Decision:** Track a minimal root `CLAUDE.md` whose only import is `@AGENTS.md` (always present), with three short
notes: the import must stay at the root, `AI-WORKSPACE.md` and `.claude/` are local, and project rules never live in
local files. It does not import the gitignored `AI-WORKSPACE.md` (absent in a fresh checkout; the documentation found
does not state how a missing import target is handled); `AGENTS.md` Start Here already tells agents to open it. The
local `.claude/CLAUDE.md` is left untouched. `scripts/verify.ps1` (gate `c-0006`) requires the file, allows it in the
root layout, and checks that it stays unignored and keeps the `@AGENTS.md` line.
**Alternatives considered:** Fixing the local file to `@../AGENTS.md` (still untracked, so fresh checkouts gain
nothing); force-adding `.claude/` (machine-local settings and a 37 KB permission file); copying the rules into
`CLAUDE.md` (two sources of truth).
**Consequences:** Fresh checkouts load `AGENTS.md`, including the housekeeping rule, through the tracked adapter. In
this checkout both `CLAUDE.md` files load; the local one's imports still resolve under `.claude/` and add nothing.
Verified statically (file, import line, not ignored, docs); an interactive `/context all` check of a new session is
the remaining confirmation. Supersedes the "local pointer" consequence of ADR 017.
**Follow-up — 2026-11-17:** the next fresh Claude Code session in this checkout loaded both the root `CLAUDE.md` and
`AGENTS.md` as project instructions at startup, without any manual read (the local `.claude/CLAUDE.md` is unchanged).

## 017 — Continuous development-artifact housekeeping — 2026-11-16 — Claude

**Status:** Accepted (user requirement; permanent for every phase)
**Context:** Phase 0 left about 70 MB of gate run folders, snapshots and diagnostics, plus test logs, fixtures and
superseded harness builds under `files/`. Nothing removed them, and the user does not want agents' temporary files to
accumulate or to have to clean them up.
**Decision:** The rule lives once, in the tracked root `AGENTS.md` (Project-Specific Rules), which Codex reads natively
and Claude Code reaches through `.claude/CLAUDE.md`. Agents clean up after every verification cycle or phase: record
results durably first, keep only evidence with a stated reason (`RETAIN.md` plus a Handoff note), never touch source,
assets, user data or recovery-critical evidence, and keep the native harness build cache while it serves verification
or a security classification. Gate outputs are cleaned with one small helper inside the gate,
`helpers/Remove-GateOutputs.ps1` (dry run by default; refuses links, unexpected roots and unsafe names), whose
safeguards are check `c-0008`; other generated paths are removed by explicit reviewed lists.
**Alternatives considered:** Cleaning only at release (accumulates for months); age- or count-based retention
tooling (more machinery than needed); deleting `outputs/` wholesale (would destroy retained evidence and user-recorded
manual results).
**Consequences:** Run evidence is short-lived, so results must reach Handoff, the plan or tests before cleanup.
`.claude/CLAUDE.md` is gitignored, so its pointer to the rule is local; the tracked `AGENTS.md` is the durable copy.
(Follow-up 2026-11-16: the tracked root `CLAUDE.md` now imports `AGENTS.md` for Claude Code; see ADR 018.)

## 016 — Active plan in md-instructions; superseded plans archived in files/plans/legacy-plan — 2026-11-16 — Claude

**Status:** Accepted (user decision)
**Context:** The v0.2.0 plan sat untracked in `files/plans/` while the committed v0.1.1 plan had been moved out of
`md-instructions/` to `files/plans/legacy-plan/` in the working tree. AI-WORKSPACE puts plans in `md-instructions/`
and says to delete them when done.
**Decision:** The only active plan is `md-instructions/Portable-Folder-Icons-v0.2.0-Implementation-Plan.md` (moved
byte-for-byte; SHA-256 recorded in the plan's "Plan reconciliation"). Superseded plans are kept, unchanged, under
`files/plans/legacy-plan/` and tracked there, rather than deleted.
**Alternatives considered:** Keeping the active plan in `files/plans/` (hides it from the documented location);
deleting the v0.1.1 plan (loses the history it records outside Git log).
**Consequences:** References point to `md-instructions/`. Retiring the v0.2.0 plan later follows the same pattern.

## 015 — Phase 0B: budgeted static menu with alphabetic-range overflow entries — 2026-11-16 — Claude

**Status:** Accepted design (user-approved); implemented 2026-11-16 on `feature/v0.2.0`, automated PASS, manual M01
PASS (user, 2026-11-16). Working fallback: the user prefers a single top-level entry as the final design.
**Context:** Manual M01 failed: Explorer showed Choose Folder Icon plus 15 icons and no Reset/Repair/Uninstall. An
isolated probe of the Shell's static-menu builder on this machine (Windows 11 build 26200.9725) rendered at most 16
entries per top-level static menu entry, counted depth-first across nested `ExtendedSubCommandsKey` submenus in key
order; nested groups share that budget and a second top-level entry gets its own. No Microsoft documentation states
the limit, so it is an observed compatibility constraint, not a Windows guarantee.
**Decision:** Keep ADR 011's single primary **Folder Icons** submenu, but list Reset, Repair and Uninstall first and
keep **Choose Folder Icon** with a reserved allotment of 12 icons (budget 16 − 4 other entries). Put the remaining icons
in additional top-level static entries of at most 16 icons each, labelled by alphabetical range, under exactly owned
keys that setup and Repair recreate and prune and Uninstall removes. Keep Apply verb names, `PfiAction`, `PfiIconHash`,
`DelegateExecute` and broker dispatch unchanged; do not rebuild the broker for this. Keep setup current-user and
one-click. Acceptance needs the Shell-built menu (a gate check), not only registry contents, at 0, 1, 12, 13, 16, 21,
28, 29, 45 and 120 icons, plus manual M01.
**Alternatives considered:** Nested alphabetical groups (share the budget; disproven by probe E4); a picker window
through the broker (scales, but needs a new broker action, new binaries and an endpoint-security decision; out of scope
for Phase 0B); relying on menu scrolling (entries are dropped, not scrolled).
**Consequences:** Large inventories add one top-level classic-menu entry per further 16 icons (120 icons: 8 entries);
this clutter is an accepted trade-off. The budget is one constant, re-measured by the Shell-builder check on each
Windows build where acceptance is claimed. Supersedes ADR 011 only for the layout of the icon list.

**Follow-up — implementation, 2026-11-16 (Phase 0B):** only `scripts/Windows/PortableFolderIcons.Integration.ps1`
changed in the product. `$script:PfiStaticMenuEntryBudget = 16` is the one constant; chooser allotment = budget − 4,
overflow capacity = budget. The chooser key is `Utility_0900_Choose_Icons` (sorts after `Utility_0100_Reset`,
`_0200_Repair`, `_0300_Uninstall`, whose names, commands and broker contract are unchanged); the separator flag
(`CommandFlags` 32) moved from Reset, now first, to the chooser. Menu order is case-insensitive invariant-culture with
an ordinal tie-break, independent of manifest order and machine culture (identical to the previous `Sort-Object`
order for every current label). Apply keys keep one `PortableFolderIcons.Apply.NNNN` sequence in menu order across all
stores, with unchanged `PfiAction`, `PfiIconHash`, `MultiSelectModel=Player` and `DelegateExecute`, so the broker and
its registration-derived contracts are unchanged (broker binaries untouched; no rebuild). Overflow entries are
`<parent>.More.NN` → `<chooser store>.MoreNN`, NN 01–99, labelled `Folder Icons (First–Last)` (en dash; one icon:
`Folder Icons (Name)`; each end over 40 characters is shortened to 39 plus an ellipsis). Ownership is by exact name:
registration removes every owned overflow key and recreates the needed ones, Uninstall removes them all, near
lookalikes are never touched. More than 12 + 99 × 16 = 1596 icons makes registration fail with a Setup_and_Run
message instead of dropping any. The Shell builder re-measured the budget at 16 of 40 (`c-0009`). Runtime and
assembly versions were not advanced: the plan's coordinated version step needs a broker rebuild, which this phase
excludes (plan, "Branch, version and checkpoint policy").

## 014 — Build the native test harness once per input set; classify every launch — 2026-11-16 — Claude

**Status:** Accepted (verification infrastructure; local, uncommitted until the checkpoint is authorized)
**Context:** WatchGuard approved one build of the C# test harness (`35482483…`) and blocked the next (`b2eaad08…`).
Every run recompiled the harness, and the inbox compiler is not deterministic: the builds differed only in the PE
timestamp and the MVID, so each run produced a new, unclassified program. Separately, the `c-0002` and `c-0004`
wrappers captured runner stderr under `-ErrorAction Stop`, which turned a denied launch into FAIL.
**Decision:** Build each harness (x64, x86) once into the ignored gate cache, keyed by a fingerprint of every build
input (harness source, broker bytes and assembly identity, compiler bytes and version, `csc.rsp`, `mscorlib.dll`,
switches, target), and reuse it only after re-verifying its record and hashes. Launch compiled test programs only
through `Invoke-PfiNativeProcess` and classify each result as PASS, FAIL, CRASH, BLOCKED_BY_ENDPOINT_SECURITY, BLOCKED
or NOT RUN; PASS needs exit 0 and a pass line with assertions. Record launches and refuse to relaunch a binary whose
last launch was blocked until the user acknowledges a reclassification of that exact hash. Keep the explicit opt-ins.
**Alternatives considered:** Deterministic compilation (not available in the inbox .NET Framework compiler); editing
the binary's timestamp/MVID to stabilise the hash (alters provenance; refused); renaming, relocating or retrying a
blocked binary (a bypass; refused); a path or publisher rule (the security owner's decision, still possible).
**Consequences:** One security classification per input set now persists across runs. Any change to the harness
source, the broker binaries or the compiler produces a new build that needs classification again, which is the
correct behaviour. A cached build is not approval; only an executed run is evidence. Check `c-0007` covers this.

**Follow-up — 2026-11-16 (checkpoint session):** a direct `scripts/verify.ps1` (and `files/tests/Invoke-Tests.ps1`)
still launched the cached harness by default. Every verification entrypoint now withholds compiled-harness launches
unless the run is explicitly authorized (`-AllowNativeHarness` or `PFI_GATE_NATIVE_HARNESS=allow`; `-SkipNativeHarness`
still forces the withhold), decided by one function, `Test-PfiNativeLaunchAuthorized`. A withheld launch stays
`BLOCKED_BY_ENDPOINT_SECURITY (withheld, not launched)` and the verifier ends `RESULT: BLOCKED`, never PASS. The gate
now calls both tools with no native flag, so every full run exercises that default, and it fails the check if a
launch is recorded without authorization.

## 013 — One verification gate; endpoint-security blocks are BLOCKED, not FAIL — 2026-11-16 — Claude

**Status:** Accepted for Phase 0 (gate files are local and uncommitted until a checkpoint is authorized)
**Context:** Verification was `scripts/verify.ps1` plus two hand-run broker runners. The workspace template
supplies a `generic` verification gate under `files/dev-work/verification-gate/`. On 2026-11-16 WatchGuard
Endpoint Security blocked a freshly compiled, unsigned C# test harness, which the old runners reported as an
ordinary failure.
**Decision:** Adopt the template's generic runner as the single entrypoint, copied with three marked changes
(status index under `outputs/`, `scripts/verify.ps1` kept as check `c-0006`, check exit codes 2/3/4 for
BLOCKED, BLOCKED_BY_ENDPOINT_SECURITY and NOT RUN). The suite and verifier gain `-SkipNativeHarness`; a
withheld or OS-denied harness launch yields BLOCKED (suite exit 3, verifier exit 2), never PASS. The gate
withholds the harness launch by default until an authorized security review, and failures already present
when the gate was established are labelled BASELINE without changing their FAIL status.
**Alternatives considered:** A second custom runner (duplicates the template); moving `scripts/verify.ps1`
into the gate (breaks the configured command and history); re-running, renaming or relocating the blocked
binary (a bypass, refused).
**Consequences:** No full PASS is possible until the security owner decides how the harness may run. Every
future compiled executable, including a possible Phase 4 worker, needs the same decision.

## 012 — Record the local COM selection transport — 2026-10-01 — Codex

**Status:** Observed uncommitted implementation; acceptance/checkpoint pending
**Context:** Committed `88007c5` records the Phase 2 architecture gate only.
The preserved worktree now contains a compiled selection broker, but repository
history does not record its implementation or architecture approval. This ADR
records the architecture actually present without retroactively claiming
approval or superseding the committed single-selection contract as released.
**Observed implementation:** Retain the classic nested registry menu and use
an exact current-user `DelegateExecute`/`LocalServer32` COM registration for
Apply/Reset. A .NET Framework C# executable implements `IInitializeCommand`,
`IObjectWithSelection`, and `IExecuteCommand`; it enumerates `IShellItemArray`
filesystem paths in supplied order and writes one atomic GUID-named JSON
request. Only the token and SHA-256 travel to the installed PowerShell
dispatcher, which processes targets sequentially and presents one aggregate
outcome. Setup stages the OS-appropriate x64/x86 artifact and build manifest;
Repair and Uninstall validate/manage exact COM ownership.
**Reasoning supported by the existing gate:** Shell selection transport and
one request per invocation avoid command-line path aggregation and the
ambiguity of a timed queue of independently launched item processes. The
compiled component serves transport; the scalable menu still uses ADR 011's
static chooser. This does not implement the Windows 11 modern first-level menu.
**Consequences:** C# source, developer build steps, binary/source hash identity,
COM activation/lifetime, rollback, deployment/security review, and live Explorer
testing become Phase 2 obligations. The current synthetic seam does not prove
that registration and initialization agree: Reset is registered as
`Utility_0100_Reset`, while the broker accepts `PortableFolderIcons.Reset`.
Resolve that boundary before accepting Phase 2. No new rights, signing,
publication, or architecture authorization is inferred from local files.

**Phase 2 follow-up — 2026-10-01:** The user's explicit continuation directive
authorizes finishing this implementation, with acceptance and commit held at
the manual Explorer gate. The canonical Reset registry key and initialized
command name are both `Utility_0100_Reset`, retaining utility ordering. Its
`PfiAction`, request action, and dispatcher action remain `Reset`; Apply keys
remain `PortableFolderIcons.Apply.NNNN` with action `Apply` and a validated
icon SHA-256. No verb name is needed in the payload: the broker validates the
registry identity before dispatch, and the payload reader independently validates
the action/hash. Both modes use the same contract. Tests derive identities and
properties from registration and exercise actual initialization/property reads.
Microsoft specifies that the initialized name is the registry command key's
name: [IInitializeCommand::Initialize](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nf-shobjidl_core-iinitializecommand-initialize).
Native property reads also require architecture-correct
[VARIANT layout](https://learn.microsoft.com/en-us/windows/win32/api/oaidl/ns-oaidl-variant);
the fixed 16-byte buffer was replaced with a union containing the native
two-pointer record member, producing 24 bytes on x64 and 16 on x86. Focused
tests cover both layouts and processes. Actual installed x64 COM dispatch and
request cleanup now pass; menu/UI/rendering acceptance remains manual.

## 011 — Isolate dynamic icons in a nested static chooser — 2026-08-25 — Codex

**Status:** Accepted
**Context:** The expanded and future ICO inventory can exceed screen height.
Microsoft's static `ExtendedSubCommandsKey` model defines one ordered popup and
separator flags, but no independently scrolling region whose sibling commands
remain pinned inside the same popup.
**Decision:** Keep the classic registry architecture and make the root
**Folder Icons** popup short: one **Choose Folder Icon** child cascade followed
by Reset, Repair, and Uninstall. Store dynamic Apply verbs only beneath the
child cascade, alphabetically and without a hardcoded count. Omit the empty
chooser when no icon is accepted while retaining all utilities.
**Alternatives considered:** A visually pinned footer would require behavior
the static menu contract does not expose. A COM shell extension solely for this
appearance would add deployment, signing, security, and maintenance cost.
**Consequences:** Native overflow affects only the icon-choice popup. The
utility commands remain immediately accessible, and Repair/Uninstall own and
replace/remove both exact project-owned cascade stores.

## 010 — Default-silent actions with opt-in Developer Mode — 2026-07-29 — Codex

**Status:** Accepted for implementation; awaiting manual acceptance
**Context:** Apply and Reset are routine context-menu actions. Keeping a
diagnostic terminal and confirmation dialog visible on every success adds
friction, but hiding failures would make the tool difficult to support.
**Decision:** Add the strict TOML Boolean `[settings] developer_mode`, default
it to `false`, and parse only that setting with Windows PowerShell 5.1 code.
Setup persists the effective value in the installed `settings.json` and builds
Apply/Reset commands from it. Normal mode hides their terminal and suppresses
success UI, but error dialogs remain visible. Developer Mode retains progress
and completion/warning dialogs. Repair reads and preserves installed settings.
**Alternatives considered:** Reading the repository on every action would
break portability; environment variables or machine-wide registry state would
be implicit and harder to audit; a TOML package would add an unnecessary
dependency.
**Consequences:** A configuration change takes effect after setup is rerun.
The installed runtime remains independent of the repository, rollback covers
settings, and Uninstall removes installed settings with the runtime.

**Implementation correction:** `powershell.exe -WindowStyle Hidden` still
briefly created a visible console before PowerShell processed that option.
Normal Apply/Reset therefore use an installed VBScript through `wscript.exe`,
which starts the dispatcher with window style 0 and waits for completion.
Selected paths are encoded as UTF-16 hex before entering the secondary command
line, preventing `%`, `!`, ampersands, parentheses, apostrophes, spaces, and
Unicode from being reinterpreted. Developer Mode still invokes PowerShell
directly and visibly.

## 009 — Version applied icon resources and fully reload one parent tab — 2026-07-28 — Codex

**Status:** Accepted; supersedes #004 for Apply/Reset repaint behavior
**Context:** Three manual tests proved that path/PIDL notifications, ordinary
refresh, and same-location navigation left a customized folder bound to a
stale system image-list entry. Reset was immediate because it left the
customized-folder state. A unique ICO filename alone and targeted
`SHUpdateImage` also failed to change the stale entry.
**Decision:** Give every Apply a unique resource beneath
`icons\applied`, retain resources across Apply operations, then navigate the one matching
Shell tab to its parent and back. Detect both completed navigations from that
automation object's canonical filesystem location and Busy state, without a
fixed sleep. Developer Mode may expose Apply/Reset progress and warnings.
**Alternatives considered:** More item notifications, `SHUpdateImage`, a
global association/cache refresh, Explorer restart, and arbitrary delays were
ineffective or too disruptive.
**Consequences:** The matching tab remains open and returns to its original
folder, but selection, scroll position, and navigation history may change.
Generated resources accumulate safely until Reset reclaims only resources
owned by that folder; Repair counts them but cannot safely infer they are
unreferenced.

## 008 — Correct icon-source directory capitalization — 2026-07-28 — Codex

**Status:** Accepted; supersedes #001 only for path capitalization
**Context:** The finalized source directory was manually corrected from the
typo `files\ICO-FIles` to `files\ICO-Files`.
**Decision:** Treat `files\ICO-Files` as the exact distributable installer
source everywhere.
**Alternatives considered:** Relying on Windows case-insensitivity would leave
Git archives and case-sensitive tooling with the incorrect spelling.
**Consequences:** Runtime code, tests, configuration, documentation, and the
retained implementation plan use the corrected path.

## 007 — Retain content-hashed icons across repair and uninstall — 2026-07-28 — Codex

**Status:** Accepted
**Context:** Existing customized folders store absolute paths to installed
icons and must survive source rename/replacement or ordinary uninstall.
**Decision:** Cache by full SHA-256, never overwrite different content in
place, never prune old hashes during setup/repair, and preserve the cache by
default during uninstall.
**Alternatives considered:** Filename caches and ordinary uninstall cleanup
would break already-customized folders.
**Consequences:** Cache storage grows until the user explicitly accepts the
warned purge option.

## 006 — Install a stable self-contained LocalAppData runtime — 2026-07-28 — Codex

**Status:** Accepted
**Context:** Context-menu commands and applied folder icons must continue to
work when the repository moves or is deleted.
**Decision:** Stage and validate a complete runtime, manifest, and hashed icon
cache beneath `%LOCALAPPDATA%\Portable-Folder-Icons`; registry commands point
only there.
**Alternatives considered:** Calling repository scripts is simpler but not
portable after setup; Program Files needs elevation.
**Consequences:** Repository setup performs explicit update/rescan, while
installed Repair can operate independently.

## 005 — Use only inbox Windows PowerShell and built-in APIs — 2026-07-28 — Codex

**Status:** Accepted
**Context:** The target user may lack admin rights, Python, package managers,
and network access.
**Decision:** Target Windows PowerShell 5.1 with built-in .NET, registry,
COM, and Win32 APIs; add no Python environment or third-party dependency.
**Alternatives considered:** Python would add runtime/setup overhead; a
compiled extension would add deployment and security complexity.
**Consequences:** The implementation stays auditable and offline, with tests
written as a self-contained PowerShell harness.

## 004 — Targeted Shell refresh without Explorer restart — 2026-07-28 — Codex

**Status:** Accepted
**Context:** Folder icon changes should appear promptly without closing user
windows, clearing the global icon cache, or restarting Explorer.
**Decision:** Send path-scoped `SHChangeNotify` attribute/update events and
refresh only open filesystem Explorer windows currently displaying the
changed folder's parent.
**Alternatives considered:** Restarting `explorer.exe` disrupts every window;
global cache rebuilds are slow and destructive; notification alone can leave
some windows visually stale.
**Consequences:** Open windows and their locations remain intact, though
Windows caching can still require navigating away and back on some systems.

## 003 — Version 1 is single-selection only — 2026-07-28 — Codex

**Status:** Accepted
**Context:** Safely transporting multiple arbitrary Explorer paths and
reporting partial failures requires a separate interaction design.
**Decision:** Register `MultiSelectModel=Single` and independently validate
exactly one directory target at runtime.
**Alternatives considered:** Dormant or best-effort multi-select behavior was
rejected because it could truncate or misapply selections.
**Consequences:** Multi-folder application remains an explicit future feature.

## 002 — Use a static current-user classic cascade — 2026-07-28 — Codex

**Status:** Accepted
**Context:** The tool needs a nested Windows 10/11 menu without admin rights,
Explorer restart, or a compiled extension.
**Decision:** Use Microsoft's documented `ExtendedSubCommandsKey\shell`
pattern beneath a tool-owned
`HKCU\Software\Classes\Directory\shell\PortableFolderIcons` verb.
**Alternatives considered:** HKLM requires elevation; CommandStore adds shared
global state; COM and modern Windows 11 first-menu integration require a
compiled/package integration outside v0.1.0.
**Consequences:** The menu appears under Windows 11 **Show more options** and
can be recreated by replacing only one exact HKCU subtree.

## 001 — Preserve source icons under files/ICO-FIles — 2026-07-28 — Codex

**Status:** Superseded by #008 only for path capitalization
**Context:** The global workspace convention treats `files/` as
development-only, while the user explicitly selected `files\ICO-FIles` as the
distributable import source.
**Decision:** Keep this exact immediate-file source directory as a narrow
project exception, while ensuring installed behavior depends only on copied
content beneath LocalAppData.
**Alternatives considered:** Moving icons under `scripts/` would follow the
generic convention but violate the finalized project path.
**Consequences:** Release packaging must include this one `files/` subtree;
runtime code must never reference it after installation.
