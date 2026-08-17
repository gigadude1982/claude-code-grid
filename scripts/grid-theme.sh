#!/bin/bash
# grid-theme.sh apply <name> | load | next | prev | menu — the grid's look.
#
# Themes restyle the chrome — title accent, the ? button, the status ground —
# via the @theme_* options that grid.tmux.conf's formats read, plus
# status-style directly (a plain style, not a format, so it can't do the
# indirection itself). Semantic colors stay fixed: blocked-red and done-green
# mean the same thing in every theme.
#
# The chosen name is written to $GRID_CONFIG/theme; grid.tmux.conf runs
# `load` at server start so a restart comes back dressed.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/grid-lib.sh"

THEMES="grid synthwave matrix amber"

# accent key bg fg
theme_colors() {
  case "$1" in
    grid)      echo "colour45 colour221 colour233 colour250" ;;
    synthwave) echo "colour201 colour51 colour53 colour183" ;;
    matrix)    echo "colour46 colour118 colour232 colour71" ;;
    amber)     echo "colour214 colour208 colour234 colour180" ;;
    *)         return 1 ;;
  esac
}

apply() {
  name="$1"
  colors=$(theme_colors "$name") || { echo "grid-theme: unknown theme '$name'" >&2; exit 1; }
  set -- $colors
  tmux set-option -g @grid_theme   "$name"
  tmux set-option -g @theme_accent "$1"
  tmux set-option -g @theme_key    "$2"
  tmux set-option -g @theme_bg     "$3"
  tmux set-option -g @theme_fg     "$4"
  tmux set-option -g status-style  "bg=$3,fg=$4"
  mkdir -p "$GRID_CONFIG"
  printf '%s\n' "$name" > "$GRID_CONFIG/theme"
  tmux refresh-client -S 2>/dev/null
}

current() {
  c=$(tmux show-options -gv @grid_theme 2>/dev/null)
  [ -n "$c" ] || c=grid
  printf '%s' "$c"
}

# step <1|-1> — the neighbor of the current theme in THEMES, wrapping.
step() {
  echo "$THEMES" | awk -v cur="$(current)" -v d="$1" '{
    for (i = 1; i <= NF; i++) if ($i == cur) {
      n = i + d; if (n < 1) n = NF; if (n > NF) n = 1; print $n; exit
    }
    print $1
  }'
}

case "${1:-menu}" in
  apply)
    apply "$2"
    ;;
  load)
    saved=$(cat "$GRID_CONFIG/theme" 2>/dev/null || true)
    theme_colors "${saved:-grid}" >/dev/null 2>&1 || saved=grid
    apply "${saved:-grid}"
    ;;
  next|prev)
    if [ "$1" = next ]; then n=$(step 1); else n=$(step -1); fi
    apply "$n"
    tmux display-message -d 1200 "grid theme: $n" 2>/dev/null
    ;;
  menu)
    # Explicit client: run-shell from a binding (and the CLI) has no client
    # of its own, and display-menu needs one to draw on.
    client=$(tmux list-clients -F '#{client_name}' 2>/dev/null | head -1)
    cur=$(current)
    mark() { if [ "$cur" = "$1" ]; then printf '✓'; else printf ' '; fi; }
    tmux display-menu ${client:+-c "$client"} -T '#[align=centre]grid theme' \
      "#[fg=colour45]■ grid blue $(mark grid)"       g "run-shell '$SCRIPT_DIR/grid-theme.sh apply grid'" \
      "#[fg=colour201]■ synthwave $(mark synthwave)" s "run-shell '$SCRIPT_DIR/grid-theme.sh apply synthwave'" \
      "#[fg=colour46]■ matrix $(mark matrix)"        m "run-shell '$SCRIPT_DIR/grid-theme.sh apply matrix'" \
      "#[fg=colour214]■ amber $(mark amber)"         a "run-shell '$SCRIPT_DIR/grid-theme.sh apply amber'" \
      '' \
      'reset title to session name' t "set-option -F @grid_title '#{session_name}'"
    ;;
esac
