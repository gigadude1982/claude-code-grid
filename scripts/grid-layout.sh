#!/bin/bash
# grid-layout.sh apply <layout> [session] | next|prev [session]
#                | menu [client] [session] | current [session]  — how the grid
# arranges its panes.
#
# The grid always tiled, which is the right default at four panes and the
# wrong one at two: tmux tiles a two-pane window into stacked rows, so two
# conversations you want to read side by side end up one above the other.
# This makes the arrangement a per-session setting instead — tiled, columns
# (side by side), rows (stacked), or one main pane with the rest beside or
# below it.
#
# Layouts are SESSION-scoped like themes, and for the same reason: the
# personal grid running two panes wants columns while the work grid running
# five wants tiled. The choice is written to $GRID_CONFIG/layout.<session> so
# it survives a server restart; grid_layout() in grid-lib.sh reads the file
# when the option isn't set, which is why there's no load hook to go with it.
#
# Reached by prefix+Space (cycle), the ▦ chip and the right-click pane menu
# (menu), scrolling the chip (cycle), and the options screen.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/grid-lib.sh"

MENU_KEYS="t c r l m"

# sess_of_client <client> — the session a client is attached to.
sess_of_client() {
  tmux list-clients -F '#{client_name} #{session_name}' 2>/dev/null \
    | awk -v c="$1" '$1 == c { print $2; exit }'
}

# Nothing passed a session in — this is `grid-layout` typed in a pane, so ask
# grid-lib rather than the attached client, which would answer for whichever
# grid that terminal happens to be showing.
fallback_session() {
  grid_current_session
}

apply() { # apply <layout> <session>
  name=$(grid_layout_name "$1") || {
    echo "grid-layout: unknown layout '$1' (try: $GRID_LAYOUTS)" >&2; exit 1; }
  sess="$2"
  tmux set-option -t "$sess" @grid_layout "$name"
  mkdir -p "$GRID_CONFIG"
  printf '%s\n' "$name" > "$GRID_CONFIG/layout.$sess"
  # A zoomed pane hides the arrangement being changed, so the change looks
  # like it did nothing until you unzoom. Unzoom first and the result is
  # visible immediately, which is the whole point of the gesture. `-Z` is a
  # toggle, not an unzoom, so it has to be asked whether it's zoomed first —
  # firing it blind would ZOOM an unzoomed window and hide the new layout.
  if [ "$(tmux display-message -p -t "$sess:0" '#{window_zoomed_flag}' 2>/dev/null)" = 1 ]; then
    tmux resize-pane -Z -t "$sess:0" 2>/dev/null
  fi
  tmux select-layout -t "$sess:0" "$name" 2>/dev/null
  tmux refresh-client -S 2>/dev/null
  [ -n "${GRID_LAYOUT_QUIET:-}" ] || tmux display-message -d 1200 \
    "grid layout ($sess): $(grid_layout_label "$name") — $(grid_layout_desc "$name")" 2>/dev/null
}

# step <1|-1> <session> — the neighbour of the session's layout, wrapping.
step() {
  echo "$GRID_LAYOUTS" | awk -v cur="$(grid_layout "$2")" -v d="$1" '{
    for (i = 1; i <= NF; i++) if ($i == cur) {
      n = i + d; if (n < 1) n = NF; if (n > NF) n = 1; print $n; exit
    }
    print $1
  }'
}

mode="${1:-menu}"

case "$mode" in
  apply)
    sess="${3:-$(fallback_session)}"
    [ -n "$sess" ] || exit 0
    apply "${2:-tiled}" "$sess"
    ;;
  next|prev)
    sess="${2:-$(fallback_session)}"
    [ -n "$sess" ] || exit 0
    if [ "$mode" = next ]; then n=$(step 1 "$sess"); else n=$(step -1 "$sess"); fi
    apply "$n" "$sess"
    ;;
  current)
    sess="${2:-$(fallback_session)}"
    [ -n "$sess" ] || exit 0
    echo "$(grid_layout_label "$(grid_layout "$sess")")"
    ;;
  menu)
    # Same -O -M dance as grid-theme.sh's menu: -M because a menu not opened
    # straight from a mouse binding ignores the mouse, -O so it survives the
    # pointer leaving it instead of vanishing the instant the chip is
    # released. The client is passed in so the menu lands on the terminal
    # that was clicked rather than whichever one tmux lists first.
    client="${2:-}"
    [ -n "$client" ] || client=$(tmux list-clients -F '#{client_name}' 2>/dev/null | head -1)
    sess="${3:-}"
    [ -n "$sess" ] || sess=$(sess_of_client "$client")
    [ -n "$sess" ] || sess=$(fallback_session)
    cur=$(grid_layout "$sess")
    mark() { if [ "$cur" = "$1" ]; then printf '✓'; else printf ' '; fi; }
    cmd=(tmux display-menu -O -M ${client:+-c "$client"} -T "#[align=centre]$sess layout")
    i=1
    for l in $GRID_LAYOUTS; do
      k=$(echo "$MENU_KEYS" | awk -v i="$i" '{ print $i }')
      cmd+=("$(grid_layout_label "$l") — $(grid_layout_desc "$l") $(mark "$l")" \
            "$k" "run-shell '$SCRIPT_DIR/grid-layout.sh apply $l $sess'")
      i=$((i + 1))
    done
    "${cmd[@]}"
    ;;
  *)
    echo "usage: grid-layout.sh apply <layout> [session] | next|prev [session] | menu | current" >&2
    exit 1
    ;;
esac
