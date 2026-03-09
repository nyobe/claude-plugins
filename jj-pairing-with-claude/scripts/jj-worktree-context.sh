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
The user may edit your working commit from their main workspace. The snapshot
hook runs `jj workspace update-stale` automatically before each snapshot, so
you will pick up their changes on your next edit. If you need to pick up
changes manually, run `jj workspace update-stale`.
EOF
    ;;
esac
