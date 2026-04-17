#!/usr/bin/env bash

# PreToolUse hook for Bash: blocks jj commands that would mutate commits
# outside the current workspace's mutable range.
#
# Mutable range = own_branchpoint:: ~ other_branchpoints::
# trunk() remains protected by jj's default immutable_heads.
#
# Receives JSON on stdin with tool_input.command.
# Exit 0 to allow, exit 2 to block.

# Only applies inside worktrees with a branchpoint
# (Each workspace records its branchpoint in .jj/branchpoint via jj-worktree-create.sh hook)
# Resolve symlinks so entry via session-index (~/.claude/workspaces/...) still matches.
PWD=$(pwd -P)
case "$PWD" in
  */.claude/worktrees/*) ;;
  *) exit 0 ;;
esac

[ -f "$PWD/.jj/branchpoint" ] || exit 0
BRANCHPOINT=$(cat "$PWD/.jj/branchpoint")
[ -n "$BRANCHPOINT" ] || exit 0

# Read tool input from stdin
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -n "$COMMAND" ] || exit 0

# Collect all revisions to validate, then check them at the end.
REVS_TO_CHECK=()

# Intentionally exclude read-only flags (rebase -d, restore --from).

check_segment() {
  local seg="$1"

  if ! echo "$seg" | grep -qE '(^|[[:space:]])jj[[:space:]]'; then
    return
  fi

  local subcmd
  subcmd=$(echo "$seg" | sed -nE 's/.*jj[[:space:]]+//p' \
    | tr ' ' '\n' \
    | grep -v '^-' \
    | head -1)

  case "$subcmd" in
    squash)     collect_flag_revs "$seg" "--from" "--into" "-r" ;;
    rebase)     collect_flag_revs "$seg" "-r" "-s" "-b" ;;
    describe|edit)  collect_positional_revs "$seg" "$subcmd" 1 ;;
    abandon)    collect_positional_revs "$seg" "$subcmd" ;;
    restore)    collect_flag_revs "$seg" "--to" ;;
    diffedit|split|unsquash) collect_flag_revs "$seg" "-r" ;;
  esac
}

collect_flag_revs() {
  local seg="$1"; shift
  for flag in "$@"; do
    local val
    val=$(echo "$seg" | grep -oE -- "${flag}[[:space:]]+[^[:space:];&|]+" \
      | head -1 \
      | awk '{print $2}')
    [ -n "$val" ] && REVS_TO_CHECK+=("$val")
  done
}

# Extract positional revision args after the subcommand.
# $3 (limit): if set, stop after collecting that many revs.
collect_positional_revs() {
  local seg="$1" subcmd="$2" limit="${3:-0}"
  local after_subcmd count=0
  after_subcmd=$(echo "$seg" | sed -E "s/.*jj[[:space:]]+${subcmd}[[:space:]]*//")

  # Tokenize with xargs so quoted args like -m "commit message with words"
  # aren't word-split into fake positional revisions. On parse failure
  # (e.g. an unmatched quote), fall back to collecting nothing: the default
  # target for describe/edit/abandon is @, which is always safe.
  local tokens
  tokens=$(printf '%s\n' "$after_subcmd" | xargs -n1 printf '%s\n' 2>/dev/null) || return

  local skip_next=false
  while IFS= read -r tok; do
    [ -z "$tok" ] && continue
    if $skip_next; then skip_next=false; continue; fi
    case "$tok" in
      -m|--message) skip_next=true ;;
      # Bare shell redirection operators — filename is the next token.
      '>'|'>>'|'<'|'<<'|'<<<'|'&>'|'&>>'|[0-9]'>'|[0-9]'>>'|[0-9]'<')
        skip_next=true ;;
      # Combined redirection forms (>file, 2>&1, <<EOF, &>log) — drop only this token.
      '>'*|'<'*|'&>'*|[0-9]'>'*|[0-9]'<'*)
        ;;
      -*)  ;;
      *)   REVS_TO_CHECK+=("$tok")
           count=$((count + 1))
           [ "$limit" -gt 0 ] && [ "$count" -ge "$limit" ] && return ;;
    esac
  done <<< "$tokens"
}

# Split on shell command separators (&&, ||, ;, |) using bash string
# replacement so in-segment sequences like 2>&1 stay intact.
NL=$'\n'
CMD="$COMMAND"
CMD="${CMD//&&/$NL}"
CMD="${CMD//||/$NL}"
CMD="${CMD//;/$NL}"
CMD="${CMD//|/$NL}"
IFS=$'\n' read -r -d '' -a segments < <(printf '%s\0' "$CMD")
for segment in "${segments[@]}"; do
  check_segment "$segment"
done

# Nothing explicit to check — defaults (like @) are always safe.
[ ${#REVS_TO_CHECK[@]} -eq 0 ] && exit 0

# Filter out @-relative refs (always within the workspace chain).
FILTERED=()
for rev in "${REVS_TO_CHECK[@]}"; do
  case "$rev" in
    @*) ;;
    *)  FILTERED+=("$rev") ;;
  esac
done
[ ${#FILTERED[@]} -eq 0 ] && exit 0

# Build the mutable revset: Descendants of our branchpoint, minus descendants of other workspaces' branchpoints.
EXCLUDE_PARTS=()
MY_ROOT=$(jj workspace root)
for ws in $(jj workspace list --template 'name ++ "\n"' 2>/dev/null); do #TODO: jj v0.40 adds root() to the WorkspaceRef
  root=$(jj workspace root --name "$ws" 2>/dev/null) || continue
  [ "$root" = "$MY_ROOT" ] && continue
  if [ -f "$root/.jj/branchpoint" ]; then
    bp=$(cat "$root/.jj/branchpoint")
    [ -n "$bp" ] && EXCLUDE_PARTS+=("$bp")
  fi
done

if [ ${#EXCLUDE_PARTS[@]} -gt 0 ]; then
  EXCLUDE=$(IFS='|'; echo "${EXCLUDE_PARTS[*]}")
  MUTABLE="${BRANCHPOINT}:: ~ ($EXCLUDE)::"
else
  MUTABLE="${BRANCHPOINT}::"
fi

# Validate each collected revision against mutable revset.
for rev in "${FILTERED[@]}"; do
  result=$(jj log -r "($rev) & ($MUTABLE)" --no-graph -T 'change_id' --limit 1 2>/dev/null)

  if [ -z "$result" ]; then
    # Prompt instead of blocking — the user may have intentionally asked
    # the agent to operate outside its workspace.
    cat <<EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"'$rev' is outside this workspace's mutable range (branchpoint ${BRANCHPOINT:0:12})"}}
EOF
    exit 0
  fi
done
