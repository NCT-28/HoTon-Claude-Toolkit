# claude-toolkit

Common Claude Code project setup (MCP servers, hooks, skills, CLAUDE.md skeleton),
extracted from HoTon-LmR. Install into any new project with one command.

Source of truth for the toolkit files lives here. Edit here, then re-run
`install.sh` in each project to sync.

## Contents

- `mcp/.mcp.json` — serena (code nav), context7 (lib docs), context-mode (large-output sandbox)
- `claude/settings.json` — 6 hooks wired up (UserPromptSubmit, SessionStart, PreToolUse x3, PostToolUse x2, PreCompact)
- `claude/hooks/*.sh` — the hook scripts themselves (generic, no project-specific paths)
- `claude/skills/mcp-workflow.md`, `verification.md` — behavioral skills referenced by CLAUDE.md.template
- `claude/skills/graphify/` — graphify skill (works only if the target project also runs `graphify` separately)
- `CLAUDE.md.template` — generic behavioral guidelines section. Project-specific sections
  (Project Overview, Service Map, Key Commands...) are NOT included — add those yourself
  below the toolkit marker in the generated file.

Deliberately excluded: the `verify` skill from HoTon-LmR (hoton-lmu/docker-specific,
not generic).

## Install into a project

**Any machine, no local clone needed** — `bootstrap.sh` clones (or pulls, if already
cached) the repo, then runs `install.sh` for you:

```bash
curl -fsSL https://raw.githubusercontent.com/NCT-28/HoTon-Claude-Toolkit/main/bootstrap.sh \
  | bash -s -- /path/to/project
```

Caches the clone at `~/.local/share/claude-toolkit` by default. Override with
`CLAUDE_TOOLKIT_DIR=...` (cache location) or `CLAUDE_TOOLKIT_REPO=...` (a fork/mirror URL).

**Already have this repo cloned locally** — call `install.sh` directly:

```bash
~/Desktop/workplace/develop/HoTon-Project/claude-toolkit/install.sh /path/to/project   # or cd into it and omit the arg
```

Idempotent:
- `.claude/settings.json`, `.claude/hooks/*.sh`, `.claude/skills/{mcp-workflow.md,verification.md,graphify/}`
  are synced from the toolkit; a differing existing copy is backed up to `*.bak-<timestamp>` first.
- `.mcp.json` is merged (existing project servers win over toolkit servers on name clash), old file backed up.
- `CLAUDE.md` is only created if missing — an existing one is never touched or overwritten.

## Requirements

- `jq` (JSON merge/backup diffing)
- `graphify` on `$PATH` if you want the graphify PreToolUse hook-guards to do anything
  (they no-op safely if `graphify` isn't installed)

## Updating the toolkit itself

Pull changes from whichever project you improved a hook/skill in, then re-run
`install.sh` in other projects to propagate.
