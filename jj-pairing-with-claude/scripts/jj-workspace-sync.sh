#!/usr/bin/env bash

# Claude Code UserPromptSubmit hook
# Checks if the jj workspace is stale (user edited our working commit from
# their main workspace) and updates it before the agent starts working.
#
# When stale, diffs before/after to report:
#   - Which files changed (so the agent knows what to re-read)
#   - Any CLAUDE: comments the user left inline (so the agent gets direction)
#
# Text written to stdout is injected into the agent's conversation context.

case "$PWD" in
  */.claude/worktrees/*)
    # jj status exits non-zero if the workspace is stale, and the error
    # message includes the operation ID from when the working copy was
    # last updated: "not updated since operation <hex>".
    STATUS_ERR=$(jj status 2>&1)
    if [ $? -ne 0 ]; then
      # Extract the stale operation ID, then resolve @ at that operation
      # to find the pre-rewrite commit.
      STALE_OP=$(echo "$STATUS_ERR" | sed -n 's/.*operation \([a-f0-9]*\)).*/\1/p')
      OLD_COMMIT=$(jj --at-op "$STALE_OP" log -r @ --no-graph -T commit_id 2>/dev/null)

      jj workspace update-stale > /dev/null 2>&1

      # -- Build context message --
      echo "Your jj workspace was synced with changes from the user."
      echo ""

      # Changed files summary
      STAT=$(jj diff --from "$OLD_COMMIT" --stat 2>/dev/null)
      if [ -n "$STAT" ]; then
        echo "Changed files:"
        echo "$STAT"
        echo ""
      fi

      # Extract CLAUDE: comments from added lines in the diff.
      # Matches any comment style: # // -- /* or bare CLAUDE:
      NOTES=$(jj diff --from "$OLD_COMMIT" --git 2>/dev/null \
        | awk '
          /^diff --git/ {
            # extract filename from "diff --git a/foo b/foo"
            file = $NF
            sub(/^b\//, "", file)
          }
          /^@@/ {
            # parse new-file line number from "@@ -a,b +N,M @@"
            s = $0
            sub(/.*\+/, "", s)
            sub(/,.*/, "", s)
            line = s - 1  # will increment on each line
          }
          /^[^+-]/ { line++; next }  # context line
          /^-/ { next }              # deleted line (dont count)
          /^\+/ {
            line++
            if (/CLAUDE:/) {
              text = $0
              sub(/^\+[ \t]*/, "", text)           # strip leading +/whitespace
              sub(/^[#\/\*-]+ *CLAUDE: */, "", text)  # strip comment prefix + CLAUDE:
              sub(/ *[*\/]*$/, "", text)            # strip trailing */ or //
              printf "%s:%d: %s\n", file, line, text
            }
          }
        '
      )
      if [ -n "$NOTES" ]; then
        echo "The user left comments for you:"
        echo "$NOTES"
        echo ""
        echo "Review these comments and ask any clarifying questions before proceeding."
        echo "When you're done addressing a comment, remove the CLAUDE: marker from the code."
      else
        echo "Re-read any files you're working with before editing — contents on disk have changed."
      fi
    fi
    ;;
esac
