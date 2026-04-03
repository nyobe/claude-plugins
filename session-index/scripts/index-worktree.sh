#!/usr/bin/env bash
set -euo pipefail

# Creates a symlink in ~/.claude/workspaces/<project>/<worktree-name>
# pointing to the worktree directory.
#
# Fires on SessionStart and CwdChanged. Only acts when cwd is inside
# a .claude/worktrees/ directory.

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd')

# Only activate inside a worktree
case "$CWD" in
  */.claude/worktrees/*)
    ;;
  *)
    exit 0
    ;;
esac

# Strip .claude/worktrees/ from the path to get a "logical" path:
#   /Users/.../claude-plugins/jj-pairing-with-claude/.claude/worktrees/foo
#   -> /Users/.../claude-plugins/jj-pairing-with-claude/foo
LOGICAL_PATH="${CWD/\/.claude\/worktrees\///}"

# Find the repo root (walk up looking for .jj or .git).
# Fall back to the directory containing .claude/worktrees/ if no repo found.
WORKTREE_PARENT="${CWD%%/.claude/worktrees/*}"
REPO_ROOT=""
DIR="$WORKTREE_PARENT"
while [ "$DIR" != "/" ]; do
  if [ -d "$DIR/.jj" ] || [ -d "$DIR/.git" ]; then
    REPO_ROOT="$DIR"
    break
  fi
  DIR="$(dirname "$DIR")"
done
: "${REPO_ROOT:=$WORKTREE_PARENT}"

# The symlink path is the logical path relative to the repo root's parent,
# so the repo basename is always the top-level directory:
#   claude-plugins/jj-pairing-with-claude/foo  (nested)
#   pulumi-service/deploy-exec-root            (simple)
REPO_PARENT="$(dirname "$REPO_ROOT")"
REL_PATH="${LOGICAL_PATH#"$REPO_PARENT"/}"

INDEX_ROOT="$HOME/.claude/workspaces"
INDEX_DIR="$INDEX_ROOT/$(dirname "$REL_PATH")"
mkdir -p "$INDEX_DIR"

# Create symlink (idempotent — update if already exists)
ln -sfn "$CWD" "$INDEX_DIR/$(basename "$REL_PATH")"

# Copy list script into index root on first run
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ ! -f "$INDEX_ROOT/list.sh" ]; then
  cp "$SCRIPT_DIR/list.sh" "$INDEX_ROOT/list.sh"
  chmod +x "$INDEX_ROOT/list.sh"
fi
