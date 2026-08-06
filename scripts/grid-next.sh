#!/bin/bash
# grid-next.sh [session] — jump to the pane that most wants your attention.
#
# Bound to prefix+n. Ranks panes by @state (set by pane-state.sh):
#
#   waiting  blocked on you for input/permission   — highest priority
#   done     finished its turn, ready for review
#   (others) working / idle                        — never a target
#
# Ties break oldest-first, so the pane that's been stuck longest wins. If the
# active pane is already the best candidate, this advances to the next one
# and wraps — so holding prefix+n cycles every pane needing attention rather
# than sticking on the top of the list.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/grid-lib.sh"

session="${1:-}"
[ -n "$session" ] || session=$(grid_current_session)
[ -n "$session" ] || exit 0

ranked=$(tmux list-panes -t "$session" -F '#{pane_id} #{@state} #{@state_since} #{pane_active}' 2>/dev/null \
  | awk '{
      prio = ($2 == "waiting") ? 2 : ($2 == "done") ? 1 : 0
      if (prio > 0) print prio, ($3 == "" ? 0 : $3), $1, $4
    }' \
  | sort -k1,1nr -k2,2n)

if [ -z "$ranked" ]; then
  tmux display-message "grid: nothing waiting — all panes working or idle"
  exit 0
fi

ids=()
active_at=-1
i=0
while read -r _prio _since id active; do
  ids+=("$id")
  [ "$active" = "1" ] && active_at=$i
  i=$((i + 1))
done <<< "$ranked"

# Already sitting on a candidate? Advance past it (wrapping) so repeated
# presses walk the queue instead of re-selecting the same pane.
if [ "$active_at" -ge 0 ]; then
  target="${ids[$(( (active_at + 1) % ${#ids[@]} ))]}"
else
  target="${ids[0]}"
fi

tmux select-pane -t "$target"
