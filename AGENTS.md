# Portable Folder Icons — Agent Instructions

The entrypoint for every coding agent in this repository. Codex and most other agents load this file automatically; Claude Code loads it through `CLAUDE.md`. No other per-agent file is needed.

## Start Here

1. Read `AI-WORKSPACE.md`: the shared rules for working, testing, Git and safety. This file does not import it for you, so open it yourself, then follow its **Session Start**.
2. Read `md-instructions/Handoff.md` (current state, work in progress, next action), then `md-instructions/Briefing.md` (what this project is and is for).
3. Confirm the branch, recent commits and working-tree state with Git before changing anything. If a handoff, plan or earlier conversation conflicts with the repository, investigate before acting.
4. Load other documents only when the task needs them. `AI-WORKSPACE.md` lists what each one holds, and `.ai/WORKFLOWS.md` has the routines for features, bug fixes, refactors, reviews, handoffs and commits.

## Always

- Register a new feature in `md-instructions/Feature-Map.md` before writing its code, and keep the map in step with its tests.
- Report only checks that actually ran, with their real result. Implemented is not verified.
- Keep all work inside this repository, and never print or commit secrets.
- Put anything the next session needs into the repository (Handoff, Decisions, the Feature Map). An agent's memory, personal skills and home-folder configuration are not part of the project.
- When a sandbox or permission rule blocks a command, such as a commit while `.git` is read-only, say what was not done. Do not work around it.
- Update `md-instructions/Handoff.md` before you stop.
- Never merge into `main`, force-push or rewrite history without the user's explicit approval.

## Project-Specific Rules

Only genuine requirements of this repository belong here. They take precedence over `AI-WORKSPACE.md`; do not copy shared policy into this section. Keep them in this tracked file. Machine-local files are gitignored and personal, so project rules must never live in them: `AGENTS.override.md` (Codex reads it instead of this file when it exists), `CLAUDE.local.md` and `.claude/settings.local.json`.

### Repository development artifact housekeeping

Every coding agent (Claude Code, Codex CLI and any other) is responsible for the temporary and generated files it creates, throughout implementation, so the repository stays small, organized and recoverable. Clean up continuously, not only at release, and never ask the user to clean up agent temporary files during normal development.

- **When.** After every completed verification cycle or implementation phase, review the generated artifacts and remove those no longer needed.
- **Primary target: `files/dev-work/verification-gate/outputs/`.** It is temporary evidence storage, not an archive. When a phase completes successfully, first record its important results durably (regression tests, `md-instructions/Handoff.md` **Last verification**, a concise report or `GATE.md`), then remove its run outputs. Do not accumulate run directories.
- **Retain an artifact only** for an active investigation, an unresolved regression, a pending manual acceptance gate, recovery of uncommitted work, or a specifically documented future verification need. Put a `RETAIN.md` in each retained folder saying why it is kept and when it can be removed, mention it in Handoff, and remove it once that reason ends.
- **Elsewhere in `files/`** the same principles apply to temporary test directories, obsolete fixtures, test logs, old screenshots and traces, generated diagnostic output, superseded build products, temporary extracted or copied files, unused backups, abandoned or interrupted run directories, redundant verification evidence and failed test artifacts (typically under `files/test-logs/`, `files/temp/`, `files/run-temp/` and `files/backups/`).
- **Never delete** `files/` or a whole development subdirectory indiscriminately. Never delete, as routine housekeeping, personal or production ICOs, installed runtime resources, tracked source, maintained fixtures and test suites, approved assets, user data or user-authored content, or recovery-critical evidence. Keep only development directories that serve a continuing purpose.
- **Keep the native harness build cache** (`files/dev-work/verification-gate/cache/native-harness/`) while it serves reproducible verification or an endpoint-security classification; deleting it forces new, unclassified executables.
- **Before removing anything:** (1) identify its owner and purpose; (2) confirm it is no longer needed; (3) promote important findings into durable documentation or regression tests; (4) confirm it is not needed to recover uncommitted work; (5) delete only verified disposable artifacts; (6) confirm the deletion scope and what remains.
- **Tools.** For gate outputs use `files/dev-work/verification-gate/helpers/Remove-GateOutputs.ps1` (dry run by default, `-Apply` to delete; it removes only unretained immediate child folders of the ignored outputs folder and refuses links, unexpected roots and unsafe names). Remove anything else by explicit, reviewed path lists, never by broad recursive deletes.
- **Report** at the end of each phase which generated directories were cleaned, what was intentionally retained and why, and any cleanup limitation.
