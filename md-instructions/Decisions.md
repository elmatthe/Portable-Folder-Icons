# Portable Folder Icons — Decisions (ADR Log)

Append-only record of non-obvious design decisions and their reasoning. Newest
entries appear first.

---

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
