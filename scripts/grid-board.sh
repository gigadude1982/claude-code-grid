#!/bin/bash
# grid-board.sh <note|show|inject> [args] — the grid's shared scratchpad.
#
# Four Claude sessions working across four repos can't see each other, so the
# session that just changed an API contract has no way to tell the session
# that consumes it. The board is a plain markdown file per grid that every
# pane can append to and that every session is handed at startup.
#
#   note "<text>"   append an entry, attributed to the calling pane's repo
#   show [session]  render it in a popup (prefix+B)
#   inject          SessionStart hook — emits the board as additionalContext
#
# The interesting one is `inject`: rather than requiring a CLAUDE.md line in
# every repo, a SessionStart hook feeds the board straight into each new
# session's context, so a pane knows what its neighbours have been doing
# before you type anything.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/grid-lib.sh"

# Resolve the board + repo label from the pane we're actually running under.
# TMUX_PANE is inherited all the way down tmux → shell → claude → Bash tool,
# so this works whether a human or a Claude session is the caller.
#
# Deliberately no fall-back to "the current client's session" here, unlike
# the other scripts: `inject` runs as a SessionStart hook for *every* Claude
# session on the machine, including ones started in an ordinary terminal.
# With a client fallback, tmux would hand back whichever session it used most
# recently and an unrelated session would get a grid's board injected into
# its context as fact. Requiring a real pane with @repo set means a non-grid
# session resolves to nothing and stays silent.
board="" repo="" session="" pane=""
if command -v tmux >/dev/null 2>&1; then
  pane="${GRID_PANE:-${TMUX_PANE:-}}"
  if [ -n "$pane" ]; then
    repo=$(tmux display-message -p -t "$pane" '#{@repo}' 2>/dev/null)
    session=$(tmux display-message -p -t "$pane" '#{session_name}' 2>/dev/null)
    [ -n "$repo" ] && [ -n "$session" ] && board=$(grid_session_opt "$session" @grid_board)
  fi
fi

cmd="${1:-show}"
# Drop the subcommand, keeping the rest as-is: `note` takes the whole
# remaining line as its text. Spelled out rather than `shift 2>/dev/null`,
# which shifts by one (the 2> is a redirection, not a count) but reads like
# it shifts by two.
[ $# -gt 0 ] && shift

case "$cmd" in
  note)
    text="$*"
    [ -n "$text" ] || { echo 'usage: grid-board.sh note "<text>"' >&2; exit 1; }
    [ -n "$board" ] || { echo "grid-board: not in a grid pane — nothing to write to" >&2; exit 1; }
    [ -n "$repo" ] || repo=$(basename "$PWD")
    printf -- '- **%s** `%s` — %s\n' "$(date '+%H:%M')" "$repo" "$text" >> "$board"
    echo "noted on the $session board"
    ;;

  show)
    # Unlike note/inject, this one *is* an explicit human action, so the
    # ambient-session fallback is the helpful behaviour rather than a hazard.
    [ -n "${1:-}" ] && session="$1"
    [ -n "$session" ] || session=$(grid_current_session)
    [ -n "$board" ] && [ -f "$board" ] || board="$GRID_CONFIG/${session:-personal}.board.md"
    printf '\033[1mgrid board — %s\033[0m\n' "${session:-?}"
    printf '\033[2m%s\033[0m\n\n' "$(printf '─%.0s' $(seq 1 60))"
    if [ -s "$board" ]; then
      cat "$board"
    else
      printf '\033[2m(empty — sessions add entries with:\n  %s note "…")\033[0m\n' "$SCRIPT_DIR/grid-board.sh"
    fi
    printf '\n\033[2mpress any key\033[0m'
    read -rsn1
    ;;

  inject)
    # SessionStart hook. Silence is the correct output for a non-grid session
    # or an empty board — never inject an empty "here is what's happening"
    # header, it reads as "nothing is happening" rather than "no data".
    [ -n "$board" ] && [ -s "$board" ] || exit 0
    command -v jq >/dev/null 2>&1 || exit 0

    context="You are one of several Claude Code sessions running side by side in the \"$session\" grid, each in a different repo.

Shared grid board — notes your neighbouring sessions left about cross-repo changes that may affect your work:

$(cat "$board")

If you make a change other repos in this grid depend on (an API contract, a shared schema, a published interface), record it with:
  $SCRIPT_DIR/grid-board.sh note \"<what changed and what it breaks>\""

    jq -n --arg ctx "$context" \
      '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
    ;;

  *)
    echo "usage: grid-board.sh <note|show|inject>" >&2
    exit 1
    ;;
esac
