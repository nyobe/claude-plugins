#!/usr/bin/env bash
set -euo pipefail

# Claude Code WorktreeRemove hook
# Cleans up a jj workspace and any git worktree scaffold, then migrates
# the worktree's Claude Code sessions into the parent project so they
# remain accessible via --resume.
#
# Input (JSON on stdin):
#   { "worktree_path": "...", "cwd": "...", "session_id": "...", ... }

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INPUT=$(cat)
WPATH=$(echo "$INPUT" | jq -r '.worktree_path')
CWD=$(echo "$INPUT" | jq -r '.cwd')
NAME=$(basename "$WPATH")

# Clean up git worktree scaffold if it exists
rm -rf "$CWD/.git/worktrees/$NAME"

# Forget the jj workspace (using cwd so it works even if workspace was renamed)
cd "$WPATH" && jj workspace forget >&2 && rm -rf "$WPATH"
