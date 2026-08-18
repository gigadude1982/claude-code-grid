#!/bin/bash
# grid-click.sh <range> <session> <pane> <client> — the title line's click
# dispatcher.
#
# One MouseDown1Status binding funnels every chip here instead of growing a
# ten-deep if-shell chain in grid.tmux.conf. Two cases stay native in the
# binding — pane-dot and window-list selection need the mouse event's `=`
# target, which doesn't survive into a shell. Everything else takes its
# context from the arguments, all expanded from the *event* in the binding:
# with several terminals attached, session/pane/client name the grid that
# was actually clicked — never "the first client", which sent popups to
# whichever terminal happened to be listed first.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
range="${1:-}" session="${2:-}" pane="${3:-}" client="${4:-}"

[ -n "$client" ] || client=$(tmux list-clients -F '#{client_name}' 2>/dev/null | head -1)

popup() { # popup <w> <h> <command>
  tmux display-popup ${client:+-c "$client"} -E -w "$1" -h "$2" \
    -e "GRID_SESSION=$session" -e "GRID_PANE=$pane" "$3"
}

case "$range" in
  title)
    # Session-scoped title, falling back to the global default for the
    # prefill. The prompt opens on the clicking client and writes back to
    # that client's session, so each grid renames its own header.
    cur=$(tmux show-options -v -t "$session" @grid_title 2>/dev/null)
    [ -n "$cur" ] || cur=$(tmux show-options -gv @grid_title 2>/dev/null)
    tmux command-prompt ${client:+-t "$client"} -I "$cur" -p 'grid title:' \
      "set-option -t '$session' @grid_title '%%'"
    ;;
  help)   popup 84 41 "$SCRIPT_DIR/grid-help.sh" ;;
  rain)   tmux lock-server ;;
  next)   "$SCRIPT_DIR/grid-next.sh" "$session" ;;
  bcast)  tmux set-window-option -t "$pane" synchronize-panes ;;
  theme)  "$SCRIPT_DIR/grid-theme.sh" menu "$client" "$session" ;;
  party)  "$SCRIPT_DIR/grid-theme.sh" party "$session" ;;
  add)    popup '60%' '60%' "$SCRIPT_DIR/grid-add.sh" ;;
  git)    popup '80%' '80%' "$SCRIPT_DIR/grid-git.sh" ;;
  cost)   popup 66 20 "$SCRIPT_DIR/grid-cost.sh popup '$session'" ;;
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
      tmux display-message ${client:+-c "$client"} -d 1200 "grid: notifications back on" 2>/dev/null
    else
      tmux set-option -g @grid_mute "$(( $(date +%s) + 3600 ))"
      tmux display-message ${client:+-c "$client"} -d 1200 "grid: notifications muted for 1h" 2>/dev/null
    fi
    tmux refresh-client -S 2>/dev/null
    ;;
esac
