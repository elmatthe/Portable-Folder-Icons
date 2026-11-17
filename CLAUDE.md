# Portable Folder Icons — Claude Code

@AGENTS.md

This tracked adapter loads the project rules above in every checkout. Claude Code reads `CLAUDE.md` files instead of
`AGENTS.md` whenever one exists, and resolves `@` imports relative to the importing file, so the import must stay in
this file at the repository root.

- `AGENTS.md` is the agent entrypoint and holds the project-specific rules, including development-artifact
  housekeeping. Follow its **Start Here**.
- `AI-WORKSPACE.md` and `.claude/` are local and gitignored. Open `AI-WORKSPACE.md` yourself when it exists; a
  checkout without it is still complete.
- Local files (`.claude/CLAUDE.md`, `CLAUDE.local.md`, `.claude/settings.local.json`) may hold personal notes and
  permissions, never project rules.
