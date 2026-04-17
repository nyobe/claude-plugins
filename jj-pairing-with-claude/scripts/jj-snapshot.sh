#!/usr/bin/env bash

# Claude Code PostToolUse hook
# Triggers a jj snapshot so that edits become visible to other workspaces.
# Runs after Edit/Write tool calls.
#
# Only runs inside .claude/worktrees/ to avoid expensive scans in the main
# workspace (which may have large untracked files). In the main workspace,
# the user's own jj commands trigger snapshots naturally.
#
# Staleness detection is handled by the UserPromptSubmit hook (jj-workspace-sync.sh).

# Resolve symlinks so entry via session-index (~/.claude/workspaces/...) still matches.
PWD=$(pwd -P)
case "$PWD" in
  */.claude/worktrees/*)
    # If the current commit has a description, create a fresh working copy
    # so edits don't land on an already-described commit.
    desc=$(jj log -r @ --no-graph -T 'description' 2>/dev/null) || true
    if [ -n "$desc" ]; then
      jj new 2>/dev/null || true
    fi
    jj --config 'snapshot.auto-track=all()' status > /dev/null 2>&1 || true
    ;;
esac
