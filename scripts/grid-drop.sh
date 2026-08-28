#!/bin/bash
# grid-drop.sh [pane] — remove a repo's pane from the running grid.
#
# Bound to prefix+X (behind a confirm-before, since this kills a live Claude
# session). Drops the pane, re-applies the grid's layout, and forgets the repo
# in <session>.repos so the next launch doesn't bring it back.
#
# The repo's worktree entry is deliberately left in <session>.worktrees: the
# safe-prune at teardown is the only thing allowed to decide a worktree is
# disposable, and it needs the entry to make that call.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/grid-lib.sh"

pane="${1:-}"
[ -n "$pane" ] || pane=$(grid_current_pane)
[ -n "$pane" ] || { echo "grid-drop: not inside tmux" >&2; exit 1; }

session=$(tmux display-message -p -t "$pane" '#{session_name}' 2>/dev/null)
label=$(tmux display-message -p -t "$pane" '#{@repo}' 2>/dev/null)
[ -n "$label" ] || { echo "grid-drop: pane $pane isn't a grid pane" >&2; exit 1; }

if [ "$(tmux list-panes -t "$session:0" -F x | wc -l | tr -d ' ')" -le 1 ]; then
  tmux display-message "grid: won't drop the last pane — use ${session:0:1}dev-stop"
  exit 0
fi

f="$GRID_CONFIG/$session.repos"
if [ -f "$f" ]; then
  # Entries are stored root-relative ("a/b") but labels are flattened
  # ("a-b"), so match on the flattened form of each line.
  awk -v drop="$label" '{ l = $0; gsub("/", "-", l); if (l != drop) print }' "$f" > "$f.tmp" \
    && mv "$f.tmp" "$f"
fi

tmux kill-pane -t "$pane"
grid_apply_layout "$session"
tmux display-message "grid: dropped $label"
