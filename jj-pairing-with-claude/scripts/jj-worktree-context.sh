#!/usr/bin/env bash

# Injects jj workspace context into the agent conversation.
#
# Registered as three hooks:
#   SessionStart         — covers `claude --worktree`
#   PostToolUse(EnterWorktree) — covers interactive worktree entry
#   SubagentStart        — covers subagents spawned in worktrees
#
# Output format depends on hook type:
#   SessionStart → plain text on stdout
#   PostToolUse/SubagentStart → JSON with additionalContext

INPUT=$(cat)
EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // empty')

# Only activate inside a jj worktree
# Resolve symlinks so entry via session-index (~/.claude/workspaces/...) still matches.
PWD=$(pwd -P)
case "$PWD" in
  */.claude/worktrees/*)
    if [ ! -d "$PWD/.jj" ]; then
      echo "This worktree is not a jj workspace. Run /setup to install the WorktreeCreate hook." >&2
      exit 2
    fi
    ;;
  *)
    exit 0
    ;;
esac

subagent_context() {
    PARENT_REPO="${PWD%%/.claude/worktrees/*}"
    cat <<EOF
You are working in a git worktree. All files live under:
    $PWD
When constructing absolute paths, ALWAYS use that root.

IMPORTANT: Do NOT use the parent repository at:
    $PARENT_REPO
That path points to a different checkout. Searching or reading files there
will return the wrong content. The .claude/worktrees/ component is part of
the correct path — never strip it.
EOF
}

session_context() {
    cat <<EOF
You are working in a git worktree — an isolated copy of the repository with its
own branch checkout. It is also a jj workspace that is synced to the main workspace.
Please run all commands from within this directory ($PWD) instead of the
original repository root.
EOF
    cat <<'EOF'

## Workspace naming
First, please rename this workspace to a short description of your task:
    jj workspace rename <short-kebab-case-description>

## Automatic snapshotting
A PostToolUse hook automatically triggers a jj snapshot after each Edit/Write
tool call, making your changes visible to the user as a jj change. You do not
need to commit manually to save work. Use `jj status` or `jj diff` to view
your changes — `git status` may be out of sync.

## Committing your work
When your work is ready, commit and start a fresh working copy:
    jj commit -m "description of changes

    Co-Authored-By: Claude <noreply@anthropic.com>"
This describes the current commit and creates a new empty change on top.
(A safeguard in the snapshot hook also enforces this: if it detects a described
working copy, it automatically runs `jj new` before snapshotting to avoid
altering described commits unintentionally.)

## Modifying previous commits
Prefer squashing changes into a target commit rather than using `jj edit` —
the snapshot hook will interfere with mutating described commits.
    jj squash --into <commit>
Or to move only specific files:
    jj squash --into <commit> <path>...
To update the description of a previous commit:
    jj describe <commit> -m "updated description"

## Collaboration
The user may edit your working commit from their main workspace. A sync hook
runs automatically before you process each prompt, pulling in their changes.
The hook will tell you which files changed so you can re-read them.

The user may also leave inline comments for you (case-insensitive):

  Single-line (no colon):
    // claude use bcrypt here instead of plaintext

  Multi-line (colon signals a block — continues until a non-comment line):
    // claude: error handling
    // add retries for transient failures
    // log permanent failures to sentry

When you see these in the sync summary, ask clarifying questions if anything
is ambiguous before proceeding. Remove the claude comments from the code as
you address them.
EOF
}

case "$EVENT" in
  # Subagents only need path guidance.
  SubagentStart)
    jq -n --arg ctx "$(subagent_context)" '{
      hookSpecificOutput: {
        hookEventName: "SubagentStart",
        additionalContext: $ctx
      }
    }'
    ;;
  PostToolUse)
    jq -n --arg ctx "$(session_context)" --arg event "$EVENT" '{
      hookSpecificOutput: {
        hookEventName: $event,
        additionalContext: $ctx
      }
    }'
    ;;
  *)
    # SessionStart (and any other hook) injects stdout directly
    session_context
    ;;
esac

