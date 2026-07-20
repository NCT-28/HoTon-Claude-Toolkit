#!/usr/bin/env bash
# Install the shared Claude Code toolkit (mcp servers, hooks, skills, CLAUDE.md
# skeleton) into a project. Safe to re-run (idempotent, backs up before overwrite).
#
# Usage:
#   ~/dotfiles/claude-toolkit/install.sh [--skip-index] [--skip-plugins] [target-dir]
#   (defaults to $PWD if target-dir omitted)
#
# By default, after copying files, also runs `serena project index` (builds the
# LSP symbol cache) and `graphify update` (builds graphify-out/) against the
# target project — both are local/offline, no LLM calls. Pass --skip-index to
# skip that (e.g. very large repo, or you want to trigger it manually later).
#
# Also ensures the `superpowers` Claude Code plugin (github:obra/superpowers) is
# installed — this is a global, user-scope install (not per-project), skipped if
# already present. Pass --skip-plugins to skip that.

set -euo pipefail

SKIP_INDEX=false
SKIP_PLUGINS=false
ARGS=()
for arg in "$@"; do
  case "$arg" in
    --skip-index) SKIP_INDEX=true ;;
    --skip-plugins) SKIP_PLUGINS=true ;;
    *) ARGS+=("$arg") ;;
  esac
done

# Resolve this script's own dir, following symlinks, without GNU-only readlink -f.
resolve_dir() {
  local src="$1"
  while [ -L "$src" ]; do
    local dir
    dir="$(cd -P "$(dirname "$src")" && pwd)"
    src="$(readlink "$src")"
    [[ "$src" != /* ]] && src="$dir/$src"
  done
  cd -P "$(dirname "$src")" && pwd
}
TOOLKIT_DIR="$(resolve_dir "${BASH_SOURCE[0]}")"

TARGET="${ARGS[0]:-$PWD}"
if [ ! -d "$TARGET" ]; then
  echo "error: target dir '$TARGET' does not exist" >&2
  exit 1
fi
TARGET="$(cd "$TARGET" && pwd)"

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq required (used for JSON merge/backup checks)" >&2
  exit 1
fi

TS="$(date +%Y%m%d-%H%M%S)"
installed=()
skipped=()
backed_up=()

echo "Installing claude-toolkit into: $TARGET"

mkdir -p "$TARGET/.claude/hooks" "$TARGET/.claude/skills"

# --- settings.json: back up if different, then overwrite ---
dst="$TARGET/.claude/settings.json"
src="$TOOLKIT_DIR/claude/settings.json"
if [ -f "$dst" ] && ! cmp -s "$src" "$dst"; then
  cp "$dst" "$dst.bak-$TS"
  backed_up+=(".claude/settings.json -> settings.json.bak-$TS")
fi
if [ ! -f "$dst" ] || ! cmp -s "$src" "$dst"; then
  cp "$src" "$dst"
  installed+=(".claude/settings.json")
else
  skipped+=(".claude/settings.json (identical)")
fi

# --- hooks: always sync from toolkit (generic, no project-specific edits expected) ---
for f in "$TOOLKIT_DIR"/claude/hooks/*.sh; do
  name="$(basename "$f")"
  dst="$TARGET/.claude/hooks/$name"
  if [ -f "$dst" ] && ! cmp -s "$f" "$dst"; then
    cp "$dst" "$dst.bak-$TS"
    backed_up+=(".claude/hooks/$name -> $name.bak-$TS")
  fi
  cp "$f" "$dst"
  chmod +x "$dst"
  installed+=(".claude/hooks/$name")
done

# --- skills: mcp-workflow.md, verification.md, graphify/ ---
for name in mcp-workflow.md verification.md; do
  src="$TOOLKIT_DIR/claude/skills/$name"
  dst="$TARGET/.claude/skills/$name"
  if [ -f "$dst" ] && ! cmp -s "$src" "$dst"; then
    cp "$dst" "$dst.bak-$TS"
    backed_up+=(".claude/skills/$name -> $name.bak-$TS")
  fi
  cp "$src" "$dst"
  installed+=(".claude/skills/$name")
done

if [ -d "$TARGET/.claude/skills/graphify" ]; then
  rm -rf "$TARGET/.claude/skills/graphify.bak-$TS"
  mv "$TARGET/.claude/skills/graphify" "$TARGET/.claude/skills/graphify.bak-$TS"
  backed_up+=(".claude/skills/graphify -> graphify.bak-$TS")
fi
cp -R "$TOOLKIT_DIR/claude/skills/graphify" "$TARGET/.claude/skills/graphify"
installed+=(".claude/skills/graphify/")

# --- .mcp.json: merge mcpServers, don't clobber project-specific servers ---
dst="$TARGET/.mcp.json"
if [ -f "$dst" ]; then
  cp "$dst" "$dst.bak-$TS"
  backed_up+=(".mcp.json -> .mcp.json.bak-$TS")
  jq -s '.[0].mcpServers as $existing | .[1].mcpServers as $new |
         .[0] + {mcpServers: ($new + $existing)}' \
    "$dst" "$TOOLKIT_DIR/mcp/.mcp.json" > "$dst.tmp"
  mv "$dst.tmp" "$dst"
  installed+=(".mcp.json (merged)")
else
  cp "$TOOLKIT_DIR/mcp/.mcp.json" "$dst"
  installed+=(".mcp.json")
fi

# --- CLAUDE.md: never overwrite existing project content ---
dst="$TARGET/CLAUDE.md"
if [ -f "$dst" ]; then
  skipped+=("CLAUDE.md (exists — see $TOOLKIT_DIR/CLAUDE.md.template for the shared sections to diff/merge by hand)")
else
  cp "$TOOLKIT_DIR/CLAUDE.md.template" "$dst"
  installed+=("CLAUDE.md (from template — fill in Project Overview)")
fi

# --- serena: index project (auto-creates .serena/project.yml, local LSP symbol cache) ---
if [ "$SKIP_INDEX" = false ]; then
  if command -v serena >/dev/null 2>&1; then
    echo "Indexing project with serena..."
    # decline every "enable additional language?" prompt (finite feed, avoids
    # SIGPIPE-from-`yes`-under-set-o-pipefail reporting a false failure)
    if printf 'n\n%.0s' {1..30} | serena project index "$TARGET" >/dev/null 2>&1; then
      installed+=(".serena/ (indexed)")
    else
      skipped+=("serena index (command failed — run 'serena project index $TARGET' manually to see the error)")
    fi
  else
    skipped+=("serena index (serena not on \$PATH)")
  fi

  # --- graphify: build knowledge graph (AST-only, no LLM calls) ---
  if command -v graphify >/dev/null 2>&1; then
    echo "Building graphify knowledge graph..."
    if (cd "$TARGET" && graphify update . >/dev/null 2>&1); then
      installed+=("graphify-out/ (built)")
    else
      skipped+=("graphify update (command failed — run 'graphify update $TARGET' manually to see the error)")
    fi
  else
    skipped+=("graphify update (graphify not on \$PATH)")
  fi
else
  skipped+=("serena index, graphify update (--skip-index passed)")
fi

# --- superpowers plugin: global user-scope, install once if missing ---
if [ "$SKIP_PLUGINS" = false ]; then
  if command -v claude >/dev/null 2>&1; then
    if claude plugin list --json 2>/dev/null | jq -e 'any(.[]; .id == "superpowers@superpowers-dev")' >/dev/null 2>&1; then
      skipped+=("superpowers plugin (already installed)")
    else
      echo "Installing superpowers plugin (global, user-scope)..."
      claude plugin marketplace add obra/superpowers >/dev/null 2>&1 || true
      if claude plugin install superpowers@superpowers-dev >/dev/null 2>&1; then
        installed+=("superpowers@superpowers-dev plugin (global — applies to all projects, not just this one)")
      else
        skipped+=("superpowers plugin (install failed — run 'claude plugin marketplace add obra/superpowers && claude plugin install superpowers@superpowers-dev' manually)")
      fi
    fi
  else
    skipped+=("superpowers plugin ('claude' CLI not on \$PATH)")
  fi
else
  skipped+=("superpowers plugin (--skip-plugins passed)")
fi

echo
echo "Installed:"
for i in "${installed[@]}"; do echo "  + $i"; done
if [ "${#backed_up[@]}" -gt 0 ]; then
  echo "Backed up (differed from toolkit version):"
  for i in "${backed_up[@]}"; do echo "  ~ $i"; done
fi
if [ "${#skipped[@]}" -gt 0 ]; then
  echo "Skipped:"
  for i in "${skipped[@]}"; do echo "  - $i"; done
fi
echo
echo "Done. Review .mcp.json / CLAUDE.md, then restart Claude Code session in this project."
