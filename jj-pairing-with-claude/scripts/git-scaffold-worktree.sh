#!/usr/bin/env bash
set -euo pipefail

# Scaffold a git worktree entry for a jj workspace so that git-dependent
# tools (submodules, Makefile, Claude Code) can discover the repo.
#
# This is just for tool compatibility — jj owns the working copy.
#
# Usage:
#   git-scaffold-worktree.sh <workspace-dir>
#
# Idempotent: skips if the workspace already has a git worktree scaffold.

DIR="${1:?Usage: git-scaffold-worktree.sh <workspace-dir>}"
NAME=$(basename "$DIR")

# Skip if already scaffolded (gitdir pointer exists)
if [ -f "$DIR/.git" ] && grep -q "^gitdir:" "$DIR/.git" 2>/dev/null; then
  exit 0
fi

# Find the main .git directory.
# Standard layout: <repo>/.claude/worktrees/<name>
MAIN_GIT="$(cd "$DIR/../../.." && pwd)/.git"

if [ ! -d "$MAIN_GIT" ]; then
  echo "git-scaffold-worktree: could not find .git directory at $MAIN_GIT" >&2
  exit 1
fi

WKTREE_GIT="$MAIN_GIT/worktrees/$NAME"
mkdir -p "$WKTREE_GIT"

# Get the commit hash that jj checked out
COMMIT=$(jj -R "$DIR" log -r @ --no-graph -T 'commit_id' --limit 1 2>/dev/null)

echo "$COMMIT" > "$WKTREE_GIT/HEAD"
echo "../.." > "$WKTREE_GIT/commondir"
echo "$DIR/.git" > "$WKTREE_GIT/gitdir"

# Point the workspace at the git worktree entry
echo "gitdir: $WKTREE_GIT" > "$DIR/.git"

# Populate the git index so git tools work immediately.
# Without this, git sees every file as "deleted" since the index is empty.
git -C "$DIR" reset >/dev/null 2>&1
