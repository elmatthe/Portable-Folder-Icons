# Portable Folder Icons — Briefing

## What This Project Does

Portable Folder Icons is a Windows 10/11 current-user tool for assigning
custom icons to individual folders from Explorer's classic context menu. A
non-technical user runs one batch launcher to install or repair a stable local
runtime and import valid ICO files from the repository.

## Tech Stack

- **Language:** Windows PowerShell 5.1-compatible PowerShell
- **GUI:** Explorer classic context menu plus focused native prompts
- **Dependencies:** Inbox Windows PowerShell and built-in .NET/Win32 APIs only
- **Platform:** Windows 10/11

## Architecture

The root batch launcher invokes the repository installer beneath
`scripts/Windows`. Setup validates immediate ICO files from
`files/ICO-FIles`, copies accepted content into a SHA-256-named cache beneath
`%LOCALAPPDATA%\Portable-Folder-Icons`, stages a self-contained runtime, writes
a manifest, and registers a tool-owned HKCU cascading menu. Installed actions
apply or reset only folder-icon fields in `desktop.ini`, repair the installed
integration without the repository, or uninstall while preserving cached
icons by default.

## Features

- Deterministic icon discovery, validation, labels, collision handling, and
  content-hashed caching.
- A single-selection **Folder Icons** classic submenu with Apply, Reset,
  Repair, and Uninstall actions.
- Repository-independent installed runtime and repair operation.
- Targeted Shell notification and Explorer-window refresh without restarting
  Explorer or clearing the global icon cache.
- Pure PowerShell verification with no admin, Python, package, or network
  dependency.

## Project Layout Notes

This is Windows-only, so shipped PowerShell runtime files live under
`scripts/Windows`. As a deliberate project exception, distributable source
icons live under `files/ICO-FIles`; the installed runtime never depends on
that repository path.

## Current Version

v0.1.0

## High-Level State

The v0.1.0 feature set is implemented through Phase 5. Automated verification
is green; the systematic bug hunt and user-run Explorer acceptance pass remain
before approval to merge. See `Handoff.md` for live details.
