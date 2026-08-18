#!/bin/bash
# grid-click.sh <range> <session> <pane> — the title line's click dispatcher.
#
# One MouseDown1Status binding funnels every chip here instead of growing a
# ten-deep if-shell chain in grid.tmux.conf. Three cases stay native in the
# binding because they need the client context run-shell doesn't have: the
# title rename prompt, and pane-dot / window-list selection. Popups opened
# from here get an explicit client for the same reason.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
range="${1:-}" session="${2:-}" pane="${3:-}"

client=$(tmux list-clients -F '#{client_name}' 2>/dev/null | head -1)

popup() { # popup <w> <h> <command>
  tmux display-popup ${client:+-c "$client"} -E -w "$1" -h "$2" \
    -e "GRID_SESSION=$session" -e "GRID_PANE=$pane" "$3"
}

case "$range" in
  help)   popup 84 41 "$SCRIPT_DIR/grid-help.sh" ;;
  rain)   tmux lock-server ;;
  next)   "$SCRIPT_DIR/grid-next.sh" "$session" ;;
  bcast)  tmux set-window-option -t "$pane" synchronize-panes ;;
  theme)  "$SCRIPT_DIR/grid-theme.sh" menu ;;
  add)    popup '60%' '60%' "$SCRIPT_DIR/grid-add.sh" ;;
  git)    popup '80%' '80%' "$SCRIPT_DIR/grid-git.sh" ;;
  board)  popup '80%' '70%' "$SCRIPT_DIR/grid-board.sh show" ;;
  prompt) popup '70%' '60%' "$SCRIPT_DIR/grid-prompt.sh current" ;;
  zoom)   tmux resize-pane -Z -t "$pane" ;;
  mute)
    # Quiet hours: park an expiry epoch in @grid_mute. claude-notify.sh
    # swallows banners/pushes while it's in the future and clears it once
    # past, so the 🔔 chip flips back on its own after the hour.
    m=$(tmux show-options -gv @grid_mute 2>/dev/null)
    if [ -n "$m" ]; then
      tmux set-option -gu @grid_mute
      tmux display-message -d 1200 "grid: notifications back on" 2>/dev/null
    else
      tmux set-option -g @grid_mute "$(( $(date +%s) + 3600 ))"
      tmux display-message -d 1200 "grid: notifications muted for 1h" 2>/dev/null
    fi
    tmux refresh-client -S 2>/dev/null
    ;;
esac
