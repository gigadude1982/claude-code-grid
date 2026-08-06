#!/bin/bash
# grid-mark.sh [pane] — toggle this pane's broadcast mark.
#
# Bound to prefix+m. tmux's own marked-pane is a single global slot, which
# can't express "these three, not that one", so the grid keeps its own flag
# in a @marked pane option. grid.tmux.conf renders a ⦿ in the border of
# marked panes, and grid-prompt.sh sends to exactly that set.
#
# The point is that prefix+b (synchronize-panes) is all-or-nothing: "commit
# and push" is usually right for three of the four panes and actively wrong
# for the one mid-refactor.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/grid-lib.sh"

pane="${1:-}"
[ -n "$pane" ] || pane=$(grid_current_pane)
[ -n "$pane" ] || exit 0

repo=$(tmux display-message -p -t "$pane" '#{@repo}' 2>/dev/null)
[ -n "$repo" ] || { tmux display-message "grid: not a grid pane"; exit 0; }

if [ "$(tmux display-message -p -t "$pane" '#{@marked}' 2>/dev/null)" = "1" ]; then
  tmux set-option -p -t "$pane" @marked ""
  tmux display-message "grid: unmarked $repo"
else
  tmux set-option -p -t "$pane" @marked 1
  tmux display-message "grid: marked $repo"
fi

tmux refresh-client -S 2>/dev/null
