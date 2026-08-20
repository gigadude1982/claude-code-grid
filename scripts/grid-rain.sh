#!/bin/bash
# grid-rain.sh — matrix rain screensaver.
#
# Used as tmux's lock-command: lock-after-time runs it against each client
# after the idle threshold, and tmux unlocks the client when it exits — so
# the contract is "animate until any key". bash 3.2's read -t can't do
# sub-second timeouts, so the animation runs as a background job while the
# foreground blocks on a single read; the EXIT trap reaps it either way.
#
# The rain falls in the active theme's accent — matrix rains green,
# nosferatu red, ocean cyan — with bright white heads, and the glyph pool is
# half-width katakana plus digits, per the film. Also runnable on demand:
# `tmux lock-server`, or "matrix rain" in the right-click pane menu.
set -u

# Rain in the accent of THIS terminal's session — themes are per-session,
# and the lock runs once per client. Our tty names the client: stdin is the
# client's terminal in the lock context.
#
# The session is read off `session_attached_list`, NOT `list-clients`.
# Locking a client sets its suspended flag, and list-clients hides
# suspended clients — so the tty match that used to live here could never
# fire from inside the lock command. It fell through every time to the
# untargeted `display-message`, which answers with the server's *current*
# session: whichever terminal you were last typing in when the idle one
# locked. That is the colour crossing terminals. session_attached_list
# applies no such filter and still names us. (`display-message -c` is no
# help either: -c steers #{client_*} only, and #{@theme_accent} resolves
# against the current session regardless.)
#
# `tty` runs BEFORE the pipeline, deliberately. Expanding it inside the
# awk argument puts the command substitution in the pipeline's second
# element, whose stdin is the pipe — `tty` answers "not a tty" there and
# the match never fires.
#
# Fallbacks, for when there is no tty or no such format (tmux < 3.1): the
# current session, then the global option — which on a themed grid only
# holds the conf's default and rains a colour no chip on screen is wearing.
mytty=$(tty 2>/dev/null)
case "$mytty" in (/dev/*) ;; (*) mytty='' ;; esac
sess=''
[ -n "$mytty" ] && sess=$(tmux list-sessions -F '#{session_name} #{session_attached_list}' 2>/dev/null \
  | awk -v t="$mytty" '{ n = split($2, a, ","); for (i = 1; i <= n; i++) if (a[i] == t) { print $1; exit } }')
[ -n "$sess" ] || sess=$(tmux display-message -p '#{session_name}' 2>/dev/null)
accent=''
[ -n "$sess" ] && accent=$(tmux show-options -v -t "$sess" @theme_accent 2>/dev/null)
[ -n "$accent" ] || accent=$(tmux show-options -gv @theme_accent 2>/dev/null)
accent=${accent#colour}
case "$accent" in (*[!0-9]*|'') accent=46 ;; esac

# An array dodges bash 3.2's byte-vs-character substring ambiguity on
# multibyte strings — indexing glyphs is safe where slicing them isn't.
GLYPHS=(ｱ ｲ ｳ ｴ ｵ ｶ ｷ ｸ ｹ ｺ ｻ ｼ ｽ ｾ ｿ ﾀ ﾁ ﾂ ﾃ ﾄ ﾅ ﾆ ﾇ ﾈ ﾉ ﾊ ﾋ ﾌ ﾍ ﾎ ﾏ ﾐ ﾑ ﾒ ﾓ ﾔ ﾕ ﾖ ﾗ ﾘ ﾙ ﾚ ﾛ ﾜ ﾝ 0 1 2 3 4 5 6 7 8 9 Z X '$' '#' '%' '+' '=' '-')

# Size from the tty on stdin — tput can't reach the client's tty in the
# lock-command context and quietly reports 80x24, which painted the rain
# into the screen's first quadrant. stty asks the fd the keys arrive on.
# The tmux fallback is last-ditch and unavoidably untargeted — it reports
# the *current* client, which on a multi-terminal grid may not be us.
size=$(stty size 2>/dev/null)
rows=${size%% *}
cols=${size##* }
if ! [ "$rows" -gt 0 ] 2>/dev/null || ! [ "$cols" -gt 0 ] 2>/dev/null; then
  size=$(tmux display-message -p '#{client_height} #{client_width}' 2>/dev/null)
  rows=${size%% *}
  cols=${size##* }
fi
[ "$rows" -gt 0 ] 2>/dev/null || rows=24
[ "$cols" -gt 0 ] 2>/dev/null || cols=80
TAIL=12

cleanup() {
  [ -n "${anim:-}" ] && kill "$anim" 2>/dev/null
  wait 2>/dev/null
  printf '\e[?1000l\e[?1006l\e[0m\e[?25h\e[2J\e[H\e[?1049l'
}
trap cleanup EXIT INT TERM

# Mouse reporting (1000, SGR-encoded via 1006) is on for the duration: a
# click lands as an escape sequence on the same stdin the read below waits
# on, so mouse and keyboard both wake the grid.
printf '\e[?1049h\e[?25l\e[2J\e[?1000h\e[?1006h'

animate() {
  n=${#GLYPHS[@]}
  c=0
  while [ "$c" -lt "$cols" ]; do
    y[c]=$((RANDOM % (rows + TAIL)))
    c=$((c + 1))
  done
  while :; do
    frame=''
    # Advance ~a third of the columns per tick: cheaper than a full sweep,
    # and the desync is what reads as rain instead of a falling curtain.
    i=0
    while [ "$i" -lt $((cols / 3 + 1)) ]; do
      c=$((RANDOM % cols))
      h=${y[$c]}
      # bright head
      if [ "$h" -lt "$rows" ]; then
        frame="$frame\e[$((h + 1));$((c + 1))H\e[1;97m${GLYPHS[$((RANDOM % n))]}"
      fi
      # the head it just left cools into the trail colour
      if [ "$h" -ge 1 ] && [ "$h" -le "$rows" ]; then
        frame="$frame\e[${h};$((c + 1))H\e[0;38;5;${accent}m${GLYPHS[$((RANDOM % n))]}"
      fi
      # erase the tail end
      t=$((h - TAIL))
      if [ "$t" -ge 0 ] && [ "$t" -lt "$rows" ]; then
        frame="$frame\e[$((t + 1));$((c + 1))H "
      fi
      y[$c]=$((h + 1))
      [ "${y[$c]}" -gt $((rows + TAIL)) ] && y[$c]=0
      i=$((i + 1))
    done
    printf '%b' "$frame"
    sleep 0.06
  done
}

animate &
anim=$!

# Any key or mouse click — or EOF, when there's no tty to read — ends the
# show.
IFS= read -rsn1 || true
