#!/usr/bin/env bash

# Claude Code UserPromptSubmit hook
# Checks if the jj workspace is stale (user edited our working commit from
# their main workspace) and updates it before the agent starts working.
#
# Emits a message to the agent's context if the workspace was refreshed.

case "$PWD" in
  */.claude/worktrees/*)
    # jj status exits non-zero if the workspace is stale
    if ! jj status > /dev/null 2>&1; then
      jj workspace update-stale > /dev/null 2>&1
      echo "Your jj workspace was stale and has been refreshed. Files on disk may have changed since you last read them — re-read any files you're working with."
    fi
    ;;
esac
