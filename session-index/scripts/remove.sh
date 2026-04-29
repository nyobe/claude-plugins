#!/usr/bin/env bash
set -euo pipefail

# Removes an indexed worktree: forgets the jj workspace, deletes the
# physical directory, and cleans up the git worktree scaffold.
#
# Emits shell commands to stdout — inspect, then pipe to sh:
#   remove.sh <label>           # dry run
#   remove.sh <label> | sh      # execute
#
# <label> matches what `list.sh` shows (e.g. claude-plugins/foo/bar).

if [ $# -ne 1 ]; then
  echo "usage: $0 <label>" >&2
  exit 2
fi

LABEL=$1
INDEX_ROOT="$HOME/.claude/workspaces"
LINK="$INDEX_ROOT/$LABEL"

if [ ! -L "$LINK" ]; then
  echo "no such workspace: $LABEL" >&2
  exit 1
fi

TARGET=$(readlink "$LINK")

echo "set -e"

if [ ! -d "$TARGET" ]; then
  # Symlink is dead — just unlink it.
  echo "rm '$LINK'"
  exit 0
fi

NAME=$(basename "$TARGET")

# Find repo root by walking up from the .claude/worktrees/ parent.
PARENT="${TARGET%%/.claude/worktrees/*}"
REPO_ROOT=""
DIR="$PARENT"
while [ "$DIR" != "/" ]; do
  if [ -d "$DIR/.jj" ] || [ -d "$DIR/.git" ]; then
    REPO_ROOT="$DIR"
    break
  fi
  DIR=$(dirname "$DIR")
done

if [ -z "$REPO_ROOT" ]; then
  echo "could not find repo root for $TARGET" >&2
  exit 1
fi

echo "rm -rf '$REPO_ROOT/.git/worktrees/$NAME'"
echo "(cd '$TARGET' && jj workspace forget)"
echo "rm -rf '$TARGET'"
echo "rm '$LINK'"
