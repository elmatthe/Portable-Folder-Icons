# Portable Folder Icons — Decisions (ADR Log)

Append-only record of non-obvious design decisions and their reasoning. Newest
entries appear first.

---

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

**Status:** Accepted design (user-approved); not implemented
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
