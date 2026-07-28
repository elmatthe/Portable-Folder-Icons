# Portable Folder Icons — Decisions (ADR Log)

Append-only record of non-obvious design decisions and their reasoning. Newest
entries appear first.

---

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
