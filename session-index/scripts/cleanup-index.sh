#!/usr/bin/env bash
set -euo pipefail

# Removes dead symlinks from ~/.claude/workspaces/ whose targets no longer exist.
# Fires on SessionEnd.
#
# We clean up all dead symlinks (not just the current session's) since
# worktree removal may have happened without a corresponding SessionEnd.

INPUT=$(cat)  # consume stdin (required by hook protocol)

INDEX_ROOT="$HOME/.claude/workspaces"
[ -d "$INDEX_ROOT" ] || exit 0

# Remove dead symlinks
find "$INDEX_ROOT" -type l ! -exec test -e {} \; -delete 2>/dev/null || true

# Remove empty project directories
find "$INDEX_ROOT" -mindepth 1 -maxdepth 1 -type d -empty -delete 2>/dev/null || true
