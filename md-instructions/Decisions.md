# Portable Folder Icons — Decisions (ADR Log)

Append-only record of non-obvious design decisions and their reasoning. Newest
entries appear first.

---

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

**Status:** Accepted
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
