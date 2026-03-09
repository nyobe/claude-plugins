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

mkdir -p "$(dirname "$DIR")"

# Create jj workspace (owns the working copy, no divergence issues)
jj workspace add "$DIR" --name "$NAME" -r "trunk()" >&2

# Hide .jj from git (mimic what jj does in colocated repos)
echo '/*' > "$DIR/.jj/.gitignore"

echo "$DIR"
