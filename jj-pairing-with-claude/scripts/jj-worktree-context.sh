#!/usr/bin/env bash

# Claude Code SessionStart hook
# If the session is inside a worktree, emits context about the snapshotting
# setup so the agent understands its environment.
#
# Text written to stdout is injected into the agent's conversation context.

case "$PWD" in
  */.claude/worktrees/*)
    if [ ! -d "$PWD/.jj" ]; then
      echo "This worktree is not a jj workspace. Run /setup to install the WorktreeCreate hook." >&2
      exit 2
    fi
    cat << 'EOF'
You are working in a jj workspace that is synced to the user's main workspace.

## Automatic snapshotting
A PostToolUse hook automatically triggers a jj snapshot after each Edit/Write
tool call, making your changes visible to the user as a jj change. You do not
need to commit manually to save work.

## Workspace naming
Please rename this workspace to a short description of your task:
    jj workspace rename <short-kebab-case-description>

## Viewing your changes
`git status` may be out of sync — use `jj status` or `jj diff` instead.

## Committing your work
When your work is ready, describe the commit and create a fresh working copy:
    jj describe -m "description of changes"
    jj new
Always `jj new` after `jj describe` — this keeps the described commit clean
and gives you a fresh working copy for further edits.

## Collaboration
The user may edit your working commit from their main workspace. A sync hook
runs automatically before you process each prompt, pulling in their changes.
You'll be told which files changed so you can re-read them.

The user may also leave inline comments for you using the `CLAUDE:` convention:
    # CLAUDE: use bcrypt here instead of plaintext
    // CLAUDE: this function needs error handling
    -- CLAUDE: add an index for this query
When you see these in the sync summary, address them and then remove the
CLAUDE: comments from the code.
EOF
    ;;
esac
