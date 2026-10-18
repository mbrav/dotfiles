#!/usr/bin/env bash
# PreToolUse hook (Bash): allow `git push` without a prompt when this session is
# the Herdr agent `cto` or a team lead (`<project>-lead`). Everyone else falls
# through to the normal permission flow. Force pushes and deletes always fall
# through, since they still need Michael's go-ahead.
set -u

cmd="$(jq -r '.tool_input.command // empty')"

# Only plain git pushes, one command, no chaining.
[[ "$cmd" =~ ^[[:space:]]*git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+push([[:space:]]|$) ]] || exit 0
[[ "$cmd" =~ [\;\&\|\`\$\<\>] ]] && exit 0
[[ "$cmd" =~ (^|[[:space:]])(-f|--force|--force-with-lease[^[:space:]]*|--force-if-includes|-d|--delete|--mirror|--prune)([[:space:]]|$) ]] && exit 0
[[ "$cmd" =~ [[:space:]]\+[^[:space:]] ]] && exit 0      # +refspec = force
[[ "$cmd" =~ [[:space:]]:[^[:space:]] ]] && exit 0       # :ref = delete

[ "${HERDR_ENV:-}" = 1 ] && [ -n "${HERDR_PANE_ID:-}" ] || exit 0
name="$(herdr agent list 2>/dev/null \
  | jq -r --arg p "$HERDR_PANE_ID" '.result.agents[] | select(.pane_id == $p) | .name' | head -1)"

case "$name" in
  cto|*-lead)
    jq -n --arg n "$name" '{hookSpecificOutput: {hookEventName: "PreToolUse",
      permissionDecision: "allow",
      permissionDecisionReason: ("git push allowed for Herdr agent " + $n)}}'
    ;;
esac
exit 0
