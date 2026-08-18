#!/bin/bash
# grid-theme.sh apply <name> | load | next | prev | menu — the grid's look.
#
# Themes restyle the chrome (title accent, the ? button, the status ground —
# via the @theme_* options that grid.tmux.conf's formats read, plus
# status-style directly, a plain style that can't do the indirection itself)
# AND the grid body: pane backgrounds with the active pane a shade apart —
# the terminal's nearest thing to opacity, real translucency being the
# emulator's — the copy-mode/search highlight, messages, and the menus.
# Semantic colors stay fixed: blocked-red and done-green mean the same thing
# in every theme. Note the pane grounds replace the terminal's default
# background, so iTerm-level transparency stops showing through while a
# theme is applied.
#
# The chosen name is written to $GRID_CONFIG/theme; grid.tmux.conf runs
# `load` at server start so a restart comes back dressed.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/grid-lib.sh"

THEMES="grid synthwave matrix amber nord dracula nosferatu gruvbox ocean"
MENU_KEYS="g s m a n d f v o"

# accent key bg fg pane-bg pane-active-bg highlight pane-fg border
#
# pane-fg recolors text drawn in the terminal's *default* color — themes
# that keep it "default" leave content alone. border is the neutral frame
# tint pane-state.sh uses for idle/working panes; blocked-red and done-green
# still override it. matrix is the full treatment: green-on-black content
# inside a white frame.
theme_colors() {
  case "$1" in
    grid)      echo "colour45 colour221 colour233 colour250 colour232 colour234 colour45 default colour240" ;;
    # synthwave spreads the whole neon rack: magenta title, cyan ?, yellow
    # status text, lime pane text, orange highlight + frame, purple ground.
    synthwave) echo "colour201 colour51 colour53 colour228 colour232 colour235 colour208 colour118 colour208" ;;
    matrix)    echo "colour46 colour118 colour16 colour255 colour16 colour232 colour46 colour46 colour255" ;;
    amber)     echo "colour214 colour208 colour234 colour222 colour232 colour58 colour214 default colour137" ;;
    nord)      echo "colour110 colour222 colour236 colour252 colour234 colour236 colour110 default colour240" ;;
    # The classic: purple on gray-black, down to the default text.
    dracula)   echo "colour141 colour228 colour235 colour253 colour233 colour235 colour141 colour141 colour240" ;;
    # The colorless vampire, save for the blood: black grounds, red accents
    # and red default text, white ?, gray chrome and frame.
    nosferatu) echo "colour160 colour255 colour232 colour250 colour16 colour233 colour160 colour160 colour245" ;;
    # yellow accents over orange default text.
    gruvbox)   echo "colour214 colour208 colour235 colour223 colour234 colour236 colour214 colour208 colour137" ;;
    # cyan-on-blue: navy grounds, cyan default text, pale-cyan chrome.
    ocean)     echo "colour45 colour87 colour18 colour123 colour17 colour18 colour45 colour51 colour39" ;;
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
  # The grid body, not just the chrome. The active pane sits a shade apart
  # from the rest — dimmed-vs-lit is the terminal's stand-in for opacity.
  # Border styles are deliberately NOT touched: pane-state.sh owns those,
  # and blocked-red must survive every theme.
  tmux set-option -g window-style        "bg=$5,fg=$8"
  tmux set-option -g window-active-style "bg=$6,fg=$8"
  tmux set-option -g @theme_border       "$9"
  tmux set-option -g mode-style          "bg=$7,fg=colour232"
  tmux set-option -g message-style       "bg=$3,fg=$1"
  tmux set-option -g menu-style          "bg=$3,fg=$4"
  tmux set-option -g menu-selected-style "bg=$7,fg=colour232"
  tmux set-option -g menu-border-style   "fg=$1,bg=$3"
  mkdir -p "$GRID_CONFIG"
  printf '%s\n' "$name" > "$GRID_CONFIG/theme"
  tmux refresh-client -S 2>/dev/null
  # Visible receipt that a menu click landed — silent at server start (no
  # client to show it on) and during party mode (a toast every cycle is
  # noise, and the whole grid changing is receipt enough).
  [ -n "${GRID_THEME_QUIET:-}" ] || tmux display-message -d 1200 "grid theme: $name" 2>/dev/null
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
    ;;
  party)
    # Toggle: the loop keys off @grid_party each cycle, so clearing the
    # option is all it takes to stop — no pid bookkeeping, worst case one
    # final cycle. Whatever theme the music stops on is saved, like any
    # other apply.
    if [ -n "$(tmux show-options -gv @grid_party 2>/dev/null)" ]; then
      tmux set-option -gu @grid_party
      tmux display-message -d 1200 "grid: party's over" 2>/dev/null
    else
      tmux set-option -g @grid_party 1
      tmux display-message -d 1200 "grid: 🎉 party mode — click 🎉 again to stop" 2>/dev/null
      (
        while [ -n "$(tmux show-options -gv @grid_party 2>/dev/null)" ]; do
          GRID_THEME_QUIET=1 "$SCRIPT_DIR/grid-theme.sh" next
          sleep 3
        done
      ) </dev/null >/dev/null 2>&1 &
    fi
    tmux refresh-client -S 2>/dev/null
    ;;
  menu)
    # Explicit client — ideally the one that was clicked, passed down from
    # the binding; run-shell has no client of its own and guessing sends
    # the menu to the wrong terminal when several are attached. -M because
    # menus not opened directly from a mouse binding ignore the mouse
    # entirely without it (tmux(1)) — clicking a row did nothing. -O
    # because mouse-mode menus otherwise close the instant the pointer
    # moves or releases outside them — the menu flickered and vanished
    # right after the chip click; with -O it stays until an actual click
    # (an item chooses, outside dismisses).
    client="${2:-}"
    [ -n "$client" ] || client=$(tmux list-clients -F '#{client_name}' 2>/dev/null | head -1)
    cur=$(current)
    mark() { if [ "$cur" = "$1" ]; then printf '✓'; else printf ' '; fi; }
    # Built in a loop so adding a theme is one line in theme_colors plus a
    # word in THEMES/MENU_KEYS, not a menu rewrite. Swatches use each theme's
    # own accent, so the menu doubles as a preview.
    cmd=(tmux display-menu -O -M ${client:+-c "$client"} -T '#[align=centre]grid theme')
    i=1
    for t in $THEMES; do
      set -- $(theme_colors "$t")
      k=$(echo "$MENU_KEYS" | awk -v i="$i" '{ print $i }')
      cmd+=("#[fg=$1]■ $t $(mark "$t")" "$k" "run-shell '$SCRIPT_DIR/grid-theme.sh apply $t'")
      i=$((i + 1))
    done
    cmd+=('' 'reset title to session name' t "set-option -F @grid_title '#{session_name}'")
    "${cmd[@]}"
    ;;
esac
