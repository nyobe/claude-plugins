#!/usr/bin/env bash
set -euo pipefail

# Emit shell commands to merge one Claude Code project directory into another.
#
# Claude Code stores sessions under ~/.claude/projects/<encoded-path>/.
# When a project moves or a worktree is cleaned up, the sessions become
# orphaned because --resume can't find them under the new path.
#
# This script prints the commands needed to migrate session files from
# SOURCE into TARGET, rewriting the cwd in each session so it appears
# in the target project's session picker. Pipe to sh to execute, or
# inspect first. Safe to re-run — already-migrated sessions are skipped.
#
# Usage:
#   claude-project-merge.sh <source> <target>
#   claude-project-merge.sh <source> <target> | sh
#
# Arguments can be either:
#   - A project dir name  (e.g., -Users-claire-src-foo)
#   - An absolute path     (e.g., /Users/claire/src/foo)
#
# Examples:
#   # Merge a moved project's old sessions into the new location:
#   claude-project-merge.sh /Users/claire/src/old/path /Users/claire/src/new/path
#
#   # Merge a worktree's sessions into its parent:
#   claude-project-merge.sh \
#     -Users-claire-src-repo--claude-worktrees-foo \
#     -Users-claire-src-repo

PROJECTS_DIR="$HOME/.claude/projects"

usage() {
  sed -n '/^# Usage:/,/^[^#]/{ /^#/s/^# \?//p }' "$0"
  exit 1
}

# Resolve an argument to a project directory path.
# Accepts either an encoded dir name or an absolute filesystem path.
resolve_project_dir() {
  local arg="$1"

  # Already an encoded project dir name (starts with -)
  if [[ "$arg" == -* ]] && [[ "$arg" != /* ]]; then
    local dir="$PROJECTS_DIR/$arg"
    if [ -d "$dir" ]; then
      echo "$dir"
      return
    fi
    echo "error: project dir not found: $dir" >&2
    return 1
  fi

  # Absolute path — encode it the way Claude Code does: replace / and . with -
  local encoded
  encoded=$(echo "$arg" | tr '/.' '-')
  local dir="$PROJECTS_DIR/$encoded"
  if [ -d "$dir" ]; then
    echo "$dir"
    return
  fi

  echo "error: project dir not found: $dir (from path $arg)" >&2
  return 1
}

# Discover the cwd used by existing sessions in a project dir.
# Reads the first line of each .jsonl until one with a "cwd" field is found.
detect_cwd() {
  local dir="$1"
  for f in "$dir"/*.jsonl; do
    [ -f "$f" ] || continue
    local cwd
    cwd=$(head -1 "$f" | jq -r '.cwd // empty' 2>/dev/null)
    if [ -n "$cwd" ]; then
      echo "$cwd"
      return
    fi
  done
}

# --- Parse args ---

if [[ $# -ne 2 ]] || [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
  usage
fi

SOURCE=$(resolve_project_dir "$1")
TARGET=$(resolve_project_dir "$2")

if [[ "$SOURCE" == "$TARGET" ]]; then
  echo "error: source and target are the same: $SOURCE" >&2
  exit 1
fi

# Detect the cwd to rewrite to from existing sessions in the target.
TARGET_CWD=$(detect_cwd "$TARGET")
if [ -z "$TARGET_CWD" ]; then
  echo "error: could not detect cwd from any session in target" >&2
  echo "hint: start a session in the target project first" >&2
  exit 1
fi

SOURCE_CWD=$(detect_cwd "$SOURCE")
NEEDS_REWRITE=false
if [ -n "$SOURCE_CWD" ] && [ "$SOURCE_CWD" != "$TARGET_CWD" ]; then
  NEEDS_REWRITE=true
fi

# --- Check what needs moving ---

q() { printf '%q' "$1"; }

# Bail if source contains anything we don't recognize
non_session=$(find "$SOURCE" -mindepth 1 -maxdepth 1 \
  -not -name '*.jsonl' \
  -not -name 'sessions-index.json' \
  ! \( -type d -exec sh -c '
    name=$(basename "$1")
    echo "$name" | grep -qE "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
  ' _ {} \; \) \
  | head -1)

if [ -n "$non_session" ]; then
  echo "error: source contains unexpected non-session content: $(basename "$non_session")" >&2
  echo "hint: this script only knows how to merge session data" >&2
  exit 1
fi

# --- Emit commands ---

echo "set -e"

moved=0
skipped=0

for jsonl in "$SOURCE"/*.jsonl; do
  [ -f "$jsonl" ] || continue
  name=$(basename "$jsonl")
  uuid="${name%.jsonl}"

  if [ -f "$TARGET/$name" ]; then
    echo "# skip: $name (already in target)"
    skipped=$((skipped + 1))
    continue
  fi

  if $NEEDS_REWRITE; then
    echo "jq --arg cwd $(q "$TARGET_CWD") -s -c '.[0].cwd = \$cwd | .[]' $(q "$jsonl") > $(q "$TARGET/$name")"
  else
    echo "cp $(q "$jsonl") $(q "$TARGET/$name")"
  fi
  [ -d "$SOURCE/$uuid" ] && echo "cp -a $(q "$SOURCE/$uuid") $(q "$TARGET/$uuid")"
  moved=$((moved + 1))
done

# Clean up source (skipped sessions are already in target)
echo "rm -rf $(q "$SOURCE")"

echo "# ${moved} session(s) to merge, ${skipped} skipped" >&2
echo "#   from: $(basename "$SOURCE")" >&2
echo "#     to: $(basename "$TARGET")" >&2
