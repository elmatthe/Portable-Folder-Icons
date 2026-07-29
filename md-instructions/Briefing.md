# Portable Folder Icons — Briefing

## What This Project Does

Portable Folder Icons is a Windows 10/11 current-user tool for assigning
custom icons to individual folders from Explorer's classic context menu. A
non-technical user runs one batch launcher to install or repair a stable local
runtime and import valid ICO files from the repository. Apply and Reset are
silent by default; an opt-in Developer Mode exposes progress and result UI.

## Tech Stack

- **Language:** Windows PowerShell 5.1-compatible PowerShell
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
- A single-selection **Folder Icons** classic submenu with Apply, Reset,
  Repair, and Uninstall actions.
- Repository-independent installed runtime and repair operation.
- Default-silent Apply/Reset commands routed through an installed `wscript.exe`
  launcher that creates no console window, with visible errors in every mode
  and opt-in Developer Mode progress/completion UI.
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

v0.1.0

## High-Level State

The v0.1.0 icon behavior was manually accepted. An already-open Explorer view
may retain the previous folder color until refreshed; F5, navigating away and
back, or opening a new view displays the current color, while Reset normally
updates immediately. Release documentation and default-silent Developer Mode
are being finalized; Developer Mode still requires manual acceptance before
merge. See `Handoff.md` for live details.
