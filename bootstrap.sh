#!/usr/bin/env bash
# One-liner entry point: clone-or-update the toolkit repo to a local cache,
# then run its install.sh against a target project.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/NCT-28/HoTon-Claude-Toolkit/main/bootstrap.sh | bash -s -- /path/to/project
#   (or, already cloned: ./bootstrap.sh /path/to/project)
#
# Env:
#   CLAUDE_TOOLKIT_DIR   where to cache the clone (default: ~/.local/share/claude-toolkit)
#   CLAUDE_TOOLKIT_REPO  repo URL to clone (default: NCT-28/HoTon-Claude-Toolkit)

set -euo pipefail

REPO_URL="${CLAUDE_TOOLKIT_REPO:-https://github.com/NCT-28/HoTon-Claude-Toolkit.git}"
CACHE_DIR="${CLAUDE_TOOLKIT_DIR:-$HOME/.local/share/claude-toolkit}"

if [ -d "$CACHE_DIR/.git" ]; then
  git -C "$CACHE_DIR" pull --ff-only -q
else
  git clone -q "$REPO_URL" "$CACHE_DIR"
fi

exec "$CACHE_DIR/install.sh" "$@"
