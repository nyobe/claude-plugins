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

case "$PWD" in
  */.claude/worktrees/*)
    jj --config 'snapshot.auto-track=all()' status > /dev/null 2>&1 || true
    ;;
esac
