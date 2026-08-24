#!/bin/zsh
# grid-menu.sh — the grid's main menu, styled after btop: a big logo in the
# theme's accent over three block-glyph items — OPTIONS / HELP / QUIT.
# ↑↓/j/k/Tab move, Enter or a click chooses, Esc/q or a click anywhere else
# closes. HELP and OPTIONS run their screens inside this same popup and drop
# back here when dismissed, btop-fashion; QUIT confirms, then shuts down
# every session — the whole tmux server — with each grid's worktrees safe-
# pruned on the way out. `t` at the confirm narrows it to this grid alone,
# which is what pdev-stop does.
#
# zsh, not bash, on purpose: telling a bare Esc apart from the Esc that opens
# an arrow-key or mouse sequence needs a sub-second read timeout, and bash
# 3.2's `read -t` can't go below one second (grid-rain.sh hit the same wall).
# splash.sh set the zsh precedent.
#
# Reached via grid-click.sh (prefix+Esc, the ≡ chip, the right-click pane
# menu), which hands the session in as $GRID_SESSION — a popup is not a pane
# and can't ask tmux which grid it belongs to.
set -u

SCRIPT_DIR="${0:A:h}"
. "$SCRIPT_DIR/grid-lib.sh"

sess=$(grid_current_session)

cols=$(tput cols 2>/dev/null); [[ "$cols" == <-> ]] || cols=90
rows=$(tput lines 2>/dev/null); [[ "$rows" == <-> ]] || rows=45

esc=$'\033'

# The accent is re-read on every draw, not cached: the options screen can
# change the theme underneath us, and the menu should come back wearing it.
accent() {
  local a=''
  [ -n "$sess" ] && a=$(tmux show-options -v -t "$sess" @theme_accent 2>/dev/null)
  [ -n "$a" ] || a=$(tmux show-options -gv @theme_accent 2>/dev/null)
  a=${a#colour}
  [[ "$a" == <-> ]] || a=45
  print -r -- "$a"
}

# shade <colour> <step> — the colour walked toward black through the 256
# cube, for the logo's vertical gradient. Colours in the 6x6x6 cube step each
# channel down; greys slide down the ramp; anything else (the 16 named ones)
# is left alone and the logo goes flat rather than wrong.
shade() {
  local n=$1 s=$2 i r g b
  if (( n >= 16 && n <= 231 )); then
    i=$((n - 16)); r=$((i / 36)); g=$((i % 36 / 6)); b=$((i % 6))
    (( r -= s )); (( r < 0 )) && r=0
    (( g -= s )); (( g < 0 )) && g=0
    (( b -= s )); (( b < 0 )) && b=0
    print $((16 + r * 36 + g * 6 + b))
  elif (( n >= 232 && n <= 255 )); then
    i=$((n - s * 3)); (( i < 232 )) && i=232
    print $i
  else
    print $n
  fi
}

logo=(
  ' ██████╗ ██████╗ ██╗██████╗ '
  '██╔════╝ ██╔══██╗██║██╔══██╗'
  '██║  ███╗██████╔╝██║██║  ██║'
  '██║   ██║██╔══██╗██║██║  ██║'
  '╚██████╔╝██║  ██║██║██████╔╝'
  ' ╚═════╝ ╚═╝  ╚═╝╚═╝╚═════╝ '
)
logo_steps=(0 0 1 1 2 3)

# The items, in btop's own lettering: light box-drawing at rest, double-line
# when selected. Three rows per word, stored newline-joined.
item_names=(options help quit)
item_normal=(
'┌─┐┌─┐┌┬┐┬┌─┐┌┐┌┌─┐
│ │├─┘ │ ││ ││││└─┐
└─┘┴   ┴ ┴└─┘┘└┘└─┘'
'┬ ┬┌─┐┬  ┌─┐
├─┤├┤ │  ├─┘
┴ ┴└─┘┴─┘┴  '
'┌─┐ ┬ ┬┬┌┬┐
│─┼┐│ ││ │
└─┘└└─┘┴ ┴'
)
item_selected=(
'╔═╗╔═╗╔╦╗╦╔═╗╔╗╔╔═╗
║ ║╠═╝ ║ ║║ ║║║║╚═╗
╚═╝╩   ╩ ╩╚═╝╝╚╝╚═╝'
'╦ ╦╔═╗╦  ╔═╗
╠═╣║╣ ║  ╠═╝
╩ ╩╚═╝╩═╝╩  '
'╔═╗ ╦ ╦╦╔╦╗
║═╬╗║ ║║ ║
╚═╝╚╚═╝╩ ╩'
)
item_w=(19 12 11)

at() { printf '%s[%d;%dH' "$esc" "$1" "$2"; }

mouse_on()  { printf '%s[?1000h%s[?1006h' "$esc" "$esc"; }
mouse_off() { printf '%s[?1000l%s[?1006l' "$esc" "$esc"; }
cleanup()   { mouse_off; printf '%s[0m%s[?25h%s[2J%s[H' "$esc" "$esc" "$esc" "$esc"; }
trap cleanup EXIT INT TERM

sel=1
item_row=(0 0 0)   # first screen row of each item, filled in by draw
content_h=$(( ${#logo} + 2 + 4 * ${#item_names} + 2 ))

# hint_row is remembered so the quit confirmation can be written over the
# hint line without a full redraw.
hint_row=$rows

draw() {
  local acc=$(accent) r i line c col
  printf '%s[2J%s[H' "$esc" "$esc"
  r=$(( (rows - content_h) / 2 )); (( r < 1 )) && r=1
  for (( i = 1; i <= ${#logo}; i++ )); do
    c=$(shade "$acc" "${logo_steps[i]}")
    col=$(( (cols - ${#logo[i]}) / 2 + 1 )); (( col < 1 )) && col=1
    at $r $col; printf '%s[1;38;5;%dm%s%s[0m' "$esc" "$c" "${logo[i]}" "$esc"
    (( r++ ))
  done
  line="claude-code-grid · ${sess:-no session}"
  col=$(( (cols - ${#line}) / 2 + 1 )); (( col < 1 )) && col=1
  at $r $col; printf '%s[2m%s%s[0m' "$esc" "$line" "$esc"
  (( r += 2 ))
  for (( i = 1; i <= ${#item_names}; i++ )); do
    item_row[i]=$r
    col=$(( (cols - item_w[i]) / 2 + 1 )); (( col < 1 )) && col=1
    if (( i == sel )); then
      printf '%s[1;38;5;%dm' "$esc" "$acc"
      for line in "${(@f)item_selected[i]}"; do at $r $col; printf '%s' "$line"; (( r++ )); done
    else
      printf '%s[38;5;245m' "$esc"
      for line in "${(@f)item_normal[i]}"; do at $r $col; printf '%s' "$line"; (( r++ )); done
    fi
    printf '%s[0m' "$esc"
    (( r++ ))
  done
  hint_row=$(( r + 1 ))
  hint '↑↓ select · enter or click choose · esc close'
  # The red ✗ close affordance, same corner as the cheatsheet's.
  at 1 $(( cols - 2 )); printf '%s[1;38;5;203m✗%s[0m' "$esc" "$esc"
}

hint() {
  local col=$(( (cols - ${#1}) / 2 + 1 )); (( col < 1 )) && col=1
  at $hint_row 1; printf '%s[2K' "$esc"
  at $hint_row $col; printf '%s[2m%s%s[0m' "$esc" "$1" "$esc"
}

# run_screen <script> — hand the popup's tty to a sub-screen, then take the
# menu back. Each screen manages its own mouse reporting.
run_screen() {
  mouse_off; printf '%s[0m%s[?25h%s[2J%s[H' "$esc" "$esc" "$esc" "$esc"
  "$1"
  printf '%s[?25l' "$esc"
  draw; mouse_on
}

# shutdown <session…> — kill each named session, ours last, and make sure
# every grid's worktrees still get their safe prune.
#
# The prune is spawned detached and delayed instead of being left to the
# session-closed hook. The hook is fine while the server lives, but killing
# the LAST session ends the server, and a hook's run-shell can go down with
# it — exactly the case "quit everything" always hits. nohup keeps the
# follow-up alive through the SIGHUP that takes the popup.
#
# Pruning twice is safe and already the shipped behaviour: pdev-stop runs
# kill → sleep 1 → prune while the hook fires for the same session.
# prune-worktrees.sh rewrites its state file and skips worktrees that are
# already gone, so the loser of the race is a no-op. The sleep keeps them
# staggered rather than concurrent.
shutdown() {
  local s state prunes=() others=()
  for s in "$@"; do
    [ -n "$s" ] || continue
    state="$GRID_CONFIG/$s.worktrees"
    [ -f "$state" ] && prunes+=("$state")
    [[ "$s" == "$sess" ]] || others+=("$s")
  done
  if (( ${#prunes} )); then
    # $0 carries the pruner, "$@" the state files — no quoting of paths
    # into a -c string.
    nohup zsh -c 'prune=$0; sleep 2; for f in "$@"; do "$prune" "$f"; done' \
      "$SCRIPT_DIR/prune-worktrees.sh" "${prunes[@]}" >/dev/null 2>&1 &
    disown 2>/dev/null
  fi
  # Ours last: the popup has to outlive the sessions it is killing.
  for s in "${others[@]}"; do tmux kill-session -t "$s" 2>/dev/null; done
  [ -n "$sess" ] && tmux kill-session -t "$sess" 2>/dev/null
  exit 0
}

# btop's QUIT leaves the whole app. Here that means the tmux server: every
# session, not just the grid the popup happens to be sitting over. `t` keeps
# the narrower "this grid only" exit, which is what pdev-stop does.
confirm_quit() {
  local all=() s names
  for s in ${(f)"$(tmux list-sessions -F '#{session_name}' 2>/dev/null)"}; do
    [ -n "$s" ] && all+=("$s")
  done
  (( ${#all} )) || return
  names=${(j:, :)all}
  (( ${#names} > 46 )) && names="${#all} sessions"
  local l1="quit — shut down every session: $names"
  # Named plainly: this kills sessions that may have nothing to do with the
  # grid, and that should not be a surprise discovered afterwards.
  local l2="each claude exits · worktrees safe-pruned   [y] all · [t] this grid · [n] cancel"
  local c1=$(( (cols - ${#l1}) / 2 + 1 )); (( c1 < 1 )) && c1=1
  local c2=$(( (cols - ${#l2}) / 2 + 1 )); (( c2 < 1 )) && c2=1
  at $hint_row 1; printf '%s[2K' "$esc"
  at $hint_row $c1; printf '%s[1;38;5;203m%s%s[0m' "$esc" "$l1" "$esc"
  at $(( hint_row + 1 )) 1; printf '%s[2K' "$esc"
  at $(( hint_row + 1 )) $c2; printf '%s[2m%s%s[0m' "$esc" "$l2" "$esc"
  local a=''
  read -srk1 a 2>/dev/null || a=''
  case "$a" in
    [yY]) shutdown "${all[@]}" ;;
    [tT]) [ -n "$sess" ] && shutdown "$sess" ;;
  esac
  at $(( hint_row + 1 )) 1; printf '%s[2K' "$esc"
  hint '↑↓ select · enter or click choose · esc close'
}

activate() {
  case $sel in
    1) run_screen "$SCRIPT_DIR/grid-options.sh" ;;
    2) run_screen "$SCRIPT_DIR/grid-help.sh" ;;
    3) confirm_quit ;;
  esac
}

printf '%s[?25l' "$esc"
draw
mouse_on

while :; do
  # `|| break` and the 2>/dev/null: read fails on EOF, which is how this
  # exits when run without a tty (tests, stray invocations).
  read -srk1 ch 2>/dev/null || break
  key=''
  if [[ "$ch" == "$esc" ]]; then
    ch2=''
    if ! read -srk1 -t 0.05 ch2 2>/dev/null; then
      key=close                       # a lone Esc — nothing followed it
    elif [[ "$ch2" == '[' ]]; then
      seq=''
      while read -srk1 -t 0.05 c3 2>/dev/null; do
        seq+=$c3
        [[ "$c3" == [A-Za-z~] ]] && break
      done
      case "$seq" in
        A) key=up ;;
        B) key=down ;;
        '<'*M)                        # SGR mouse press: <btn;col;rowM
          body=${seq#<}; body=${body%M}
          btn=${body%%;*}; restxy=${body#*;}
          cx=${restxy%%;*}; cy=${restxy#*;}
          if [[ "$btn" == 0 && "$cx" == <-> && "$cy" == <-> ]]; then
            key=close                 # a click that lands on no item closes
            for (( i = 1; i <= ${#item_names}; i++ )); do
              col=$(( (cols - item_w[i]) / 2 + 1 ))
              if (( cy >= item_row[i] && cy < item_row[i] + 3 && \
                    cx >= col - 1 && cx <= col + item_w[i] )); then
                sel=$i; draw; key=enter; break
              fi
            done
          fi
          ;;
      esac
    else
      key=close
    fi
  else
    case "$ch" in
      $'\n'|$'\r') key=enter ;;
      k) key=up ;;
      j|$'\t') key=down ;;
      q|Q) key=close ;;
    esac
  fi
  case "$key" in
    up)    (( sel = sel == 1 ? ${#item_names} : sel - 1 )); draw ;;
    down)  (( sel = sel == ${#item_names} ? 1 : sel + 1 )); draw ;;
    enter) activate ;;
    close) break ;;
  esac
done
