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

# Resolve symlinks so entry via session-index (~/.claude/workspaces/...) still matches.
PWD=$(pwd -P)
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

      echo "To see the exact changes the user made, run:"
      echo "  jj diff --from $OLD_COMMIT"
      echo ""

      # Extract claude comments from added lines in the diff (case-insensitive).
      # Two forms:
      #   // claude <text>    → single-line comment
      #   // claude: <heading>  → multi-line: accumulates subsequent comment
      #   // continuation       lines until a non-comment line
      NOTES=$(jj diff --from "$OLD_COMMIT" --git 2>/dev/null \
        | awk '
          function flush() {
            if (claude_file != "") {
              printf "%s:%d:%s\n", claude_file, claude_line, claude_text
              claude_file = ""
              claude_text = ""
              multiline = 0
            }
          }
          function strip_comment(s) {
            sub(/^[ \t]*/, "", s)
            sub(/^[#\/\*-]+ */, "", s)
            sub(/ *[*\/]*$/, "", s)
            return s
          }
          /^diff --git/ {
            flush()
            file = $NF
            sub(/^b\//, "", file)
          }
          /^@@/ {
            flush()
            s = $0
            sub(/.*\+/, "", s)
            sub(/,.*/, "", s)
            line = s - 1
          }
          /^[^+-]/ { flush(); line++; next }
          /^-/ { next }
          /^\+/ {
            line++
            raw = $0; sub(/^\+/, "", raw)

            if (tolower(raw) ~ /claude:/) {
              flush()
              text = strip_comment(raw)
              sub(/^[Cc][Ll][Aa][Uu][Dd][Ee]: */, "", text)
              claude_file = file
              claude_line = line
              claude_text = (text != "") ? " " text : ""
              multiline = 1
              next
            }

            if (multiline) {
              stripped = raw; sub(/^[ \t]*/, "", stripped)
              if (stripped ~ /^[#\/\*-]/) {
                claude_text = claude_text "\n  " strip_comment(raw)
                next
              }
              flush()
            }

            if (tolower(raw) ~ /claude[^:]/) {
              text = strip_comment(raw)
              sub(/^[Cc][Ll][Aa][Uu][Dd][Ee] */, "", text)
              printf "%s:%d: %s\n", file, line, text
            }
          }
          END { flush() }
        '
      )
      if [ -n "$NOTES" ]; then
        echo "The user left comments for you:"
        echo "$NOTES"
        echo ""
        echo "Review these comments and ask any clarifying questions before proceeding."
        echo "When you're done addressing a comment, remove the claude: marker (and any continuation lines) from the code."
      fi
    fi
    ;;
esac
