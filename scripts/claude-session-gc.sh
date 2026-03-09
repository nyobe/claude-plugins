#!/usr/bin/env bash
set -euo pipefail

# Emit shell commands to merge orphaned worktree sessions into their parent
# projects.
#
# Scans ~/.claude/projects/ for worktree project dirs (containing
# --claude-worktrees-) whose corresponding worktree directory no longer
# exists on disk, then emits merge commands for each one.
#
# Usage:
#   claude-session-gc.sh              # preview
#   claude-session-gc.sh | sh         # execute
#
# Requires claude-project-merge.sh in the same directory.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECTS_DIR="$HOME/.claude/projects"
MERGE="$SCRIPT_DIR/claude-project-merge.sh"

if [ ! -x "$MERGE" ]; then
  echo "error: claude-project-merge.sh not found at $MERGE" >&2
  exit 1
fi

orphaned=0
skipped=0

for project_dir in "$PROJECTS_DIR"/*--claude-worktrees-*; do
  [ -d "$project_dir" ] || continue
  dir_name=$(basename "$project_dir")

  # Decode the project dir name back to an absolute path.
  # Encoding: replace / and . with -
  # Decoding is ambiguous (- could be literal or a separator), but we can
  # check if the worktree directory exists by looking for .claude/worktrees/
  # in the encoded name and reconstructing the path.

  # Extract the worktree name (after the last --claude-worktrees-)
  worktree_name="${dir_name##*--claude-worktrees-}"

  # Derive the parent project dir name (strip last --claude-worktrees-* segment)
  parent_dir_name="${dir_name%--claude-worktrees-*}"
  parent_dir="$PROJECTS_DIR/$parent_dir_name"

  if [ ! -d "$parent_dir" ]; then
    echo "# skip: $dir_name (parent project dir not found: $parent_dir_name)" >&2
    skipped=$((skipped + 1))
    continue
  fi

  # Try to find the actual worktree path on disk.
  # The parent's sessions contain the cwd, which tells us the project root.
  parent_cwd=""
  for f in "$parent_dir"/*.jsonl; do
    [ -f "$f" ] || continue
    parent_cwd=$(head -1 "$f" | jq -r '.cwd // empty' 2>/dev/null)
    [ -n "$parent_cwd" ] && break
  done

  if [ -z "$parent_cwd" ]; then
    echo "# skip: $dir_name (can't detect parent cwd)" >&2
    skipped=$((skipped + 1))
    continue
  fi

  worktree_path="$parent_cwd/.claude/worktrees/$worktree_name"

  # Only merge if the worktree directory is gone
  if [ -d "$worktree_path" ]; then
    continue
  fi

  echo "# orphaned: $dir_name"
  "$MERGE" "$dir_name" "$parent_dir_name" 2>&1
  echo ""
  orphaned=$((orphaned + 1))
done

echo "# found ${orphaned} orphaned worktree project(s), ${skipped} skipped" >&2
