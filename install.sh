#!/usr/bin/env bash
# Install the shared Claude Code toolkit (mcp servers, hooks, skills, CLAUDE.md
# skeleton) into a project. Safe to re-run (idempotent, backs up before overwrite).
#
# Usage:
#   ~/dotfiles/claude-toolkit/install.sh [target-dir]
#   (defaults to $PWD if target-dir omitted)

set -euo pipefail

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

TARGET="${1:-$PWD}"
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
