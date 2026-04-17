#!/usr/bin/env bash
set -euo pipefail

# Claude Code WorktreeCreate hook
# Creates a jj workspace for the agent to work in.
#
# Input (JSON on stdin):
#   { "name": "...", "cwd": "...", "session_id": "...", ... }
#
# Output (stdout):
#   Absolute path to the created workspace directory.
#   All other output must go to stderr.

INPUT=$(cat)
NAME=$(echo "$INPUT" | jq -r '.name')
CWD=$(echo "$INPUT" | jq -r '.cwd')

DIR="$CWD/.claude/worktrees/$NAME"

# Idempotent: Claude Code re-fires this hook on session resume, so noop if the workspace already exists.
if [ -d "$DIR/.jj" ]; then
  echo "$DIR"
  exit 0
fi

mkdir -p "$(dirname "$DIR")"
jj workspace add "$DIR" --name "$NAME" -r "trunk()" >&2

# Record the branchpoint to define the agent's mutable revset. (Read by jj-guard.sh)
jj -R "$DIR" log -r '@' --no-graph -T 'change_id' > "$DIR/.jj/branchpoint" 2>/dev/null
chmod 444 "$DIR/.jj/branchpoint"

# Hide .jj from git (mimic what jj does in colocated repos)
echo '/*' > "$DIR/.jj/.gitignore"

# Scaffold a git worktree entry so git-dependent tools (and Claude Code's
# repo-root detection) resolve to the workspace directory, not the parent repo.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
"$SCRIPT_DIR/git-scaffold-worktree.sh" "$DIR" >&2

echo "$DIR"
