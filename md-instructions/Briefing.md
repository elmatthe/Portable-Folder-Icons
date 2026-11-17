# Portable Folder Icons — Briefing

## What This Project Does

Portable Folder Icons is a Windows 10/11 current-user tool for assigning
custom icons to individual folders from Explorer's classic context menu. A
non-technical user runs one batch launcher to install or repair a stable local
runtime and import valid ICO files from the repository. Apply and Reset are
silent by default; an opt-in Developer Mode exposes progress and result UI.

## Tech Stack

- **Language:** Windows PowerShell 5.1-compatible PowerShell; the preserved
  local Phase 2 implementation also contains a C# .NET Framework COM broker
- **GUI:** Explorer classic context menu plus focused native prompts
- **Dependencies:** Inbox Windows PowerShell and built-in .NET/Win32 APIs only
- **Platform:** Windows 10/11

## Architecture

The root batch launcher invokes the repository installer beneath
`scripts/Windows`. Setup validates immediate ICO files from
`files/ICO-Files`, copies accepted content into a SHA-256-named cache beneath
`%LOCALAPPDATA%\Portable-Folder-Icons`, stages a self-contained runtime, writes
a manifest and strict installed settings file, and registers a tool-owned HKCU
cascading menu. Setup reads only `[settings] developer_mode` from `config.toml`,
persists the effective Boolean as `settings.json`, and stages all activated
state so rollback restores the previous runtime, manifest, settings, and menu.
Installed actions
apply or reset only folder-icon fields in `desktop.ini`, repair the installed
integration without the repository, or uninstall while preserving cached
icons by default. Each Apply copies the selected hash-validated ICO to a
unique, folder-scoped resource filename so the Shell cannot reuse the prior
rendered-resource identity.

## Features

- Deterministic icon discovery, validation, labels, collision handling, and
  content-hashed caching.
- A **Folder Icons** classic submenu listing Reset, Repair, and Uninstall
  first, then a **Choose Folder Icon** child cascade with the first 12 icons
  alphabetically. Further icons appear in additional top-level entries labelled
  by alphabetical range, at most 16 each, because the Shell's static-menu
  builder was observed to drop entries beyond 16 per top-level entry (ADR 015).
- Repository-independent installed runtime and repair operation.
- Default-silent Apply/Reset commands routed through an installed `wscript.exe`
  launcher that creates no console window, with visible errors in every mode
  and opt-in Developer Mode progress/completion UI. In normal mode, Repair and
  Uninstall start through the same launcher, so no PowerShell or Windows
  Terminal window appears behind their dialogs (ADR 022).
- Targeted Shell notification and parent-view refresh without restarting
  Explorer or clearing the global icon cache.
- Pure PowerShell verification with no admin, Python, package, or network
  dependency.

## Project Layout Notes

This is Windows-only, so shipped PowerShell runtime files live under
`scripts/Windows`. As a deliberate project exception, distributable source
icons live under `files/ICO-Files`; the installed runtime never depends on
that repository path.

## Current Version

v0.1.1 (in development)

## High-Level State

v0.1.0 was manually accepted, merged, and formally released. Focused v0.1.1
implementation is active on `feature/v0.1.1`. At `88007c5`, Phase 1 is
committed and Phase 2 contains only a documented transport architecture gate.
The preserved worktree additionally contains an uncommitted COM local-server
selection broker, JSON payload transport, and sequential aggregate Apply/Reset
processing. This local implementation passes its automated Phase 2 checkpoint
and awaits manual Explorer acceptance; it must not be described as released
or committed.

The local broker uses `DelegateExecute`, `IInitializeCommand`,
`IObjectWithSelection`, and `IExecuteCommand` to receive an `IShellItemArray`.
It passes one installed JSON request to PowerShell using a token and SHA-256,
preserving Shell array order and repeated occurrences. Setup stages an x64 or
x86 .NET Framework executable; Repair and Uninstall manage exact current-user
COM ownership. Compilation is a developer build step using the inbox .NET
Framework compiler, not a package/network dependency for end-user setup.
Request state is not customization tracking, and the later retry, persistent
logs, tracking, and safe complete-removal phases remain unimplemented.

As of 2026-10-01, all 19 intentional local ICOs validate (ten tracked original
colours plus nine untracked test/development icons); added-asset publication
rights remain unresolved. Exact HEAD automation passes 292 assertions. Local
automation passes 371 PowerShell assertions plus 350 C# harness assertions,
and the full gate passes. Focused x64 and x86 harness runs each pass 350
assertions, including registration-derived initialization and native VARIANT
layout. The canonical Reset verb is `Utility_0100_Reset`; its request action
remains `Reset`. Actual installed x64 COM Apply/Reset dispatch passes on two
repository fixtures, preserving unrelated INI content and consuming request
state. Existing `.ai/` guidance and the generated `REPO-STRUCTURE.md` are
ignored local developer artifacts, explicitly checked as untracked by the
verifier. See `Handoff.md` for evidence and the pending manual gate.

An already-open Explorer view may retain the previous folder color until
refreshed; F5, navigating away and back, or opening a new view displays the
current color, while Reset normally updates immediately.
