#!/bin/bash
# grid-theme.sh apply <name> [session] | load [session] | next|prev [session]
#              | party [session] | menu [client] [session]     — the grid's look.
#
# Themes are SESSION-scoped: each attached terminal can run its own. The
# @theme_* options grid.tmux.conf's formats read are set on the session
# (falling back to the conf's global defaults when unset), status/message
# styles at session scope, and the window/pane styles on each of the
# session's windows. Chrome and body both: title accent, the ? button, the
# status ground, pane backgrounds (active a shade apart — the terminal's
# nearest thing to opacity), the copy-mode/search highlight, and the menus.
# Semantic colors stay fixed: blocked-red and done-green mean the same
# thing in every theme. Pane grounds replace the terminal's default
# background, so iTerm-level transparency stops showing through while a
# theme is applied.
#
# Each session's choice is written to $GRID_CONFIG/theme.<session>; a
# session-created hook in grid.tmux.conf runs `load <session>` so grids
# come back dressed after a restart. A legacy single `theme` file (from
# when themes were server-global) seeds sessions that have no file yet.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/grid-lib.sh"

THEMES="grid synthwave matrix amber nord dracula nosferatu gruvbox ocean tokyo solarized cyberpunk ember forest"
MENU_KEYS="g s m a n d f v o t l c e b"

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
    # night-city blues with a purple highlight.
    tokyo)     echo "colour111 colour149 colour234 colour146 colour233 colour235 colour141 default colour60" ;;
    solarized) echo "colour33 colour136 colour235 colour245 colour234 colour236 colour33 default colour240" ;;
    # hot pink and acid yellow on black.
    cyberpunk) echo "colour198 colour226 colour232 colour123 colour232 colour234 colour226 default colour198" ;;
    # coals: orange accents, the active pane smoulders dark red.
    ember)     echo "colour202 colour220 colour233 colour223 colour232 colour52 colour202 default colour130" ;;
    # greens on loam; the active pane is the canopy.
    forest)    echo "colour114 colour178 colour234 colour151 colour232 colour22 colour114 default colour65" ;;
    *)         return 1 ;;
  esac
}

# sess_of_client <client> — the session a client is attached to.
sess_of_client() {
  tmux list-clients -F '#{client_name} #{session_name}' 2>/dev/null \
    | awk -v c="$1" '$1 == c { print $2; exit }'
}

# fallback_session — when no session was passed (bare CLI use).
fallback_session() {
  tmux display-message -p '#{session_name}' 2>/dev/null
}

apply() { # apply <name> <session>
  name="$1" sess="$2"
  colors=$(theme_colors "$name") || { echo "grid-theme: unknown theme '$name'" >&2; exit 1; }
  set -- $colors
  tmux set-option -t "$sess" @grid_theme    "$name"
  tmux set-option -t "$sess" @theme_accent  "$1"
  tmux set-option -t "$sess" @theme_key     "$2"
  tmux set-option -t "$sess" @theme_bg      "$3"
  tmux set-option -t "$sess" @theme_fg      "$4"
  tmux set-option -t "$sess" @theme_border  "$9"
  tmux set-option -t "$sess" status-style   "bg=$3,fg=$4"
  tmux set-option -t "$sess" message-style  "bg=$3,fg=$1"
  # Window/pane styles are window options — dealt to each of the session's
  # windows (a grid has one). Border styles are deliberately NOT touched:
  # pane-state.sh owns those, and blocked-red must survive every theme.
  for w in $(tmux list-windows -t "$sess" -F '#{window_id}' 2>/dev/null); do
    tmux set-option -w -t "$w" window-style        "bg=$5,fg=$8"
    tmux set-option -w -t "$w" window-active-style "bg=$6,fg=$8"
    tmux set-option -w -t "$w" mode-style          "bg=$7,fg=colour232"
    tmux set-option -w -t "$w" menu-style          "bg=$3,fg=$4"
    tmux set-option -w -t "$w" menu-selected-style "bg=$7,fg=colour232"
    tmux set-option -w -t "$w" menu-border-style   "fg=$1,bg=$3"
    # The one border style a theme does own: the active pane's frame follows
    # @theme_accent while its pane is in a neutral state, so it has to be
    # re-derived when the accent changes underneath it. pane-state.sh keeps
    # the semantic colours, which is why this can't just be set to "$1".
    "$SCRIPT_DIR/pane-state.sh" --active "$w" 2>/dev/null
  done
  mkdir -p "$GRID_CONFIG"
  printf '%s\n' "$name" > "$GRID_CONFIG/theme.$sess"
  tmux refresh-client -S 2>/dev/null
  # Visible receipt that a menu click landed — silent at server start (no
  # client to show it on) and during party mode (a toast every cycle is
  # noise, and the whole grid changing is receipt enough).
  [ -n "${GRID_THEME_QUIET:-}" ] || tmux display-message -d 1200 "grid theme ($sess): $name" 2>/dev/null
}

current() { # current <session>
  c=$(tmux show-options -v -t "$1" @grid_theme 2>/dev/null)
  [ -n "$c" ] || c=$(tmux show-options -gv @grid_theme 2>/dev/null)
  [ -n "$c" ] || c=grid
  printf '%s' "$c"
}

# step <1|-1> <session> — the neighbor of the session's theme, wrapping.
step() {
  echo "$THEMES" | awk -v cur="$(current "$2")" -v d="$1" '{
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
    # An explicit pick ends the party for that session — only the party
    # loop itself (marked by GRID_THEME_QUIET) may keep cycling.
    [ -n "${GRID_THEME_QUIET:-}" ] || tmux set-option -u -t "$sess" @grid_party 2>/dev/null
    apply "$2" "$sess"
    ;;
  load)
    # With a session: dress that one from its saved file (legacy global
    # file as seed, nothing saved = leave the conf defaults). Without:
    # every current session — the conf runs this once at server start.
    if [ -n "${2:-}" ]; then sessions="$2"; else
      sessions=$(tmux list-sessions -F '#{session_name}' 2>/dev/null)
    fi
    for sess in $sessions; do
      saved=$(cat "$GRID_CONFIG/theme.$sess" 2>/dev/null)
      [ -n "$saved" ] || saved=$(cat "$GRID_CONFIG/theme" 2>/dev/null)
      [ -n "$saved" ] || continue
      theme_colors "$saved" >/dev/null 2>&1 || continue
      GRID_THEME_QUIET=1 apply "$saved" "$sess"
    done
    ;;
  next|prev)
    sess="${2:-$(fallback_session)}"
    [ -n "$sess" ] || exit 0
    # Scrolling is an explicit pick too: take the wheel, stop the party.
    [ -n "${GRID_THEME_QUIET:-}" ] || tmux set-option -u -t "$sess" @grid_party 2>/dev/null
    if [ "$mode" = next ]; then n=$(step 1 "$sess"); else n=$(step -1 "$sess"); fi
    apply "$n" "$sess"
    ;;
  party)
    # Toggle, per session: the loop keys off the session's @grid_party each
    # cycle, so clearing the option is all it takes to stop — no pid
    # bookkeeping, worst case one final cycle. Whatever theme the music
    # stops on is saved, like any other apply.
    sess="${2:-$(fallback_session)}"
    [ -n "$sess" ] || exit 0
    if [ -n "$(tmux show-options -v -t "$sess" @grid_party 2>/dev/null)" ]; then
      tmux set-option -u -t "$sess" @grid_party
      tmux display-message -d 1200 "grid: party's over in $sess" 2>/dev/null
    else
      tmux set-option -t "$sess" @grid_party 1
      tmux display-message -d 1200 "grid: 🎉 party mode in $sess — click 🎉 again to stop" 2>/dev/null
      (
        while [ -n "$(tmux show-options -v -t "$sess" @grid_party 2>/dev/null)" ]; do
          GRID_THEME_QUIET=1 "$SCRIPT_DIR/grid-theme.sh" next "$sess"
          sleep 3
        done
      ) </dev/null >/dev/null 2>&1 &
    fi
    tmux refresh-client -S 2>/dev/null
    ;;
  menu)
    # Client passed from the binding so the menu lands on the terminal that
    # was clicked (run-shell has no client of its own; guessing sent menus
    # to the wrong terminal). -M because menus not opened directly from a
    # mouse binding ignore the mouse entirely (tmux(1)); -O because
    # mouse-mode menus otherwise close the instant the pointer moves or
    # releases outside them — the menu flickered and vanished right after
    # the chip click. With both, it stays until an actual click: an item
    # chooses, outside dismisses.
    client="${2:-}"
    [ -n "$client" ] || client=$(tmux list-clients -F '#{client_name}' 2>/dev/null | head -1)
    sess="${3:-}"
    [ -n "$sess" ] || sess=$(sess_of_client "$client")
    [ -n "$sess" ] || sess=$(fallback_session)
    cur=$(current "$sess")
    mark() { if [ "$cur" = "$1" ]; then printf '✓'; else printf ' '; fi; }
    # Built in a loop so adding a theme is one line in theme_colors plus a
    # word in THEMES/MENU_KEYS, not a menu rewrite. Swatches use each
    # theme's own accent, so the menu doubles as a preview.
    cmd=(tmux display-menu -O -M ${client:+-c "$client"} -T "#[align=centre]$sess theme")
    i=1
    for t in $THEMES; do
      set -- $(theme_colors "$t")
      k=$(echo "$MENU_KEYS" | awk -v i="$i" '{ print $i }')
      cmd+=("#[fg=$1]■ $t $(mark "$t")" "$k" "run-shell '$SCRIPT_DIR/grid-theme.sh apply $t $sess'")
      i=$((i + 1))
    done
    cmd+=('' 'reset title to session name' r "set-option -t '$sess' -u @grid_title")
    "${cmd[@]}"
    ;;
esac
