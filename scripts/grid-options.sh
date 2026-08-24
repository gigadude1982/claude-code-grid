#!/bin/zsh
# grid-options.sh — the grid's options screen, btop-styled: the settings
# that were scattered across chips and menus (theme, title, mute, party,
# broadcast, rain delay) gathered in one place. ↑↓/j/k move, ‹ › (←/→) or
# Enter change, a click selects-and-changes, Esc/q goes back — to the main
# menu when launched from grid-menu.sh, or just closes when run standalone.
#
# zsh for the same reason as grid-menu.sh: bash 3.2's `read -t` can't do the
# sub-second timeout that separates a bare Esc from an escape sequence.
#
# Values are re-read from tmux on every draw rather than cached, so a change
# made elsewhere (the theme menu, the mute chip) shows truthfully here.
set -u

SCRIPT_DIR="${0:A:h}"
. "$SCRIPT_DIR/grid-lib.sh"

sess=$(grid_current_session)
pane=$(grid_current_pane)

cols=$(tput cols 2>/dev/null); [[ "$cols" == <-> ]] || cols=90
rows=$(tput lines 2>/dev/null); [[ "$rows" == <-> ]] || rows=45

esc=$'\033'

accent() {
  local a=''
  [ -n "$sess" ] && a=$(tmux show-options -v -t "$sess" @theme_accent 2>/dev/null)
  [ -n "$a" ] || a=$(tmux show-options -gv @theme_accent 2>/dev/null)
  a=${a#colour}
  [[ "$a" == <-> ]] || a=45
  print -r -- "$a"
}

# btop's lettering for the title, double-line variant.
header=(
'╔═╗╔═╗╔╦╗╦╔═╗╔╗╔╔═╗'
'║ ║╠═╝ ║ ║║ ║║║║╚═╗'
'╚═╝╩   ╩ ╩╚═╝╝╚╝╚═╝'
)

opt_names=(
  'theme'
  'grid title'
  'notifications'
  'party mode'
  'broadcast typing'
  'rain screensaver'
)
opt_descs=(
  'colour scheme for this session — chrome, pane grounds, highlight; applies instantly'
  'the centered name on the title line; empty falls back to the session name'
  'claude banners and pushes; muting lasts an hour, then flips back on its own'
  'cycle through every theme, one every 3s, until toggled off'
  'type into ALL panes at once — the ⇄ chip'
  'idle time before matrix rain takes every client (server-wide)'
)

# The rain delays on offer, in seconds. 0 = never.
rain_steps=(0 60 300 600 1800)
rain_label() {
  case "$1" in
    0|'') print 'off' ;;
    60) print '1m' ;; 300) print '5m' ;; 600) print '10m' ;; 1800) print '30m' ;;
    *) print "${1}s" ;;
  esac
}

value_of() {
  case $1 in
    1)
      local t=$(tmux show-options -v -t "$sess" @grid_theme 2>/dev/null)
      [ -n "$t" ] || t=$(tmux show-options -gv @grid_theme 2>/dev/null)
      print -r -- "${t:-grid}"
      ;;
    2)
      local t=$(tmux show-options -v -t "$sess" @grid_title 2>/dev/null)
      [ -n "$t" ] || t=$(tmux show-options -gv @grid_title 2>/dev/null)
      print -r -- "${t:-(session name)}"
      ;;
    3)
      if [ -n "$(tmux show-options -gv @grid_mute 2>/dev/null)" ]; then
        print 'muted 1h'
      else
        print 'on'
      fi
      ;;
    4)
      if [ -n "$(tmux show-options -v -t "$sess" @grid_party 2>/dev/null)" ]; then
        print 'on 🎉'
      else
        print 'off'
      fi
      ;;
    5)
      tmux display-message -p -t "${pane:-$sess}" '#{?pane_synchronized,on,off}' 2>/dev/null || print 'off'
      ;;
    6)
      rain_label "$(tmux show-options -gv lock-after-time 2>/dev/null)"
      ;;
  esac
}

edit_title() {
  local cur=$(tmux show-options -v -t "$sess" @grid_title 2>/dev/null) t=''
  mouse_off; printf '%s[?25h' "$esc"
  at $input_row 1; printf '%s[2K' "$esc"
  at $input_row 1
  t=$cur
  # vared edits the current value in place; plain read (typed fresh) is the
  # fallback for whatever tty state vared refuses.
  if ! vared -p "  grid title (empty = session name): " t 2>/dev/null; then
    printf '  grid title (empty = session name): '
    IFS= read -r t || t=$cur
  fi
  if [ -n "$t" ]; then
    tmux set-option -t "$sess" @grid_title "$t" 2>/dev/null
  else
    tmux set-option -t "$sess" -u @grid_title 2>/dev/null
  fi
  printf '%s[?25l' "$esc"; mouse_on
}

change() { # change <index> <1|-1>
  local dir=$2
  case $1 in
    1)
      if (( dir < 0 )); then "$SCRIPT_DIR/grid-theme.sh" prev "$sess" >/dev/null 2>&1
      else "$SCRIPT_DIR/grid-theme.sh" next "$sess" >/dev/null 2>&1; fi
      ;;
    2) edit_title ;;
    3)
      # Mirrors the 🔔 chip in grid-click.sh: an epoch in @grid_mute that
      # claude-notify.sh honours until it passes.
      if [ -n "$(tmux show-options -gv @grid_mute 2>/dev/null)" ]; then
        tmux set-option -gu @grid_mute 2>/dev/null
      else
        tmux set-option -g @grid_mute "$(( $(date +%s) + 3600 ))" 2>/dev/null
      fi
      tmux refresh-client -S 2>/dev/null
      ;;
    4) "$SCRIPT_DIR/grid-theme.sh" party "$sess" >/dev/null 2>&1 ;;
    5) tmux set-window-option -t "${pane:-$sess}" synchronize-panes 2>/dev/null ;;
    6)
      local cur=$(tmux show-options -gv lock-after-time 2>/dev/null) i=1 n=${#rain_steps}
      for (( i = 1; i <= n; i++ )); do [ "${rain_steps[i]}" = "${cur:-600}" ] && break; done
      (( i > n )) && i=4          # unknown value: treat as the 10m default
      (( i += dir )); (( i < 1 )) && i=n; (( i > n )) && i=1
      tmux set-option -g lock-after-time "${rain_steps[i]}" 2>/dev/null
      ;;
  esac
}

at() { printf '%s[%d;%dH' "$esc" "$1" "$2"; }
mouse_on()  { printf '%s[?1000h%s[?1006h' "$esc" "$esc"; }
mouse_off() { printf '%s[?1000l%s[?1006l' "$esc" "$esc"; }
cleanup()   { mouse_off; printf '%s[0m%s[?25h%s[2J%s[H' "$esc" "$esc" "$esc" "$esc"; }
trap cleanup EXIT INT TERM

sel=1
box_w=64
n_opts=${#opt_names}
content_h=$(( ${#header} + 2 + n_opts + 2 + 4 ))
first_row=1 box_col=1 input_row=$rows desc_row=$rows

draw() {
  local acc=$(accent) r i line col v marker
  printf '%s[2J%s[H' "$esc" "$esc"
  r=$(( (rows - content_h) / 2 )); (( r < 1 )) && r=1
  for line in "${header[@]}"; do
    col=$(( (cols - ${#line}) / 2 + 1 )); (( col < 1 )) && col=1
    at $r $col; printf '%s[1;38;5;%dm%s%s[0m' "$esc" "$acc" "$line" "$esc"
    (( r++ ))
  done
  (( r++ ))
  box_col=$(( (cols - box_w) / 2 + 1 )); (( box_col < 1 )) && box_col=1
  local label=${sess:-grid}
  at $r $box_col
  printf '%s[38;5;%dm┌─ %s ' "$esc" "$acc" "$label"
  printf '─%.0s' {1..$(( box_w - ${#label} - 5 ))}; printf '┐%s[0m' "$esc"
  (( r++ ))
  first_row=$r
  for (( i = 1; i <= n_opts; i++ )); do
    v=$(value_of $i)
    at $r $box_col; printf '%s[38;5;%dm│%s[0m' "$esc" "$acc" "$esc"
    at $r $(( box_col + box_w - 1 )); printf '%s[38;5;%dm│%s[0m' "$esc" "$acc" "$esc"
    if (( i == sel )); then
      at $r $(( box_col + 2 ))
      printf '%s[1;38;5;%dm▶ %-18s%s[0m' "$esc" "$acc" "${opt_names[i]}" "$esc"
      at $r $(( box_col + box_w - ${#v} - 8 ))
      printf '%s[1;38;5;%dm‹ %s ›%s[0m' "$esc" "$acc" "$v" "$esc"
    else
      at $r $(( box_col + 2 ))
      printf '%s[38;5;250m  %-18s%s[0m' "$esc" "${opt_names[i]}" "$esc"
      at $r $(( box_col + box_w - ${#v} - 8 ))
      printf '%s[38;5;245m  %s%s[0m' "$esc" "$v" "$esc"
    fi
    (( r++ ))
  done
  at $r $box_col
  printf '%s[38;5;%dm└' "$esc" "$acc"
  printf '─%.0s' {1..$(( box_w - 2 ))}; printf '┘%s[0m' "$esc"
  (( r += 2 ))
  desc_row=$r
  line=${opt_descs[sel]}
  col=$(( (cols - ${#line}) / 2 + 1 )); (( col < 1 )) && col=1
  at $r $col; printf '%s[2m%s%s[0m' "$esc" "$line" "$esc"
  (( r += 2 ))
  input_row=$r
  line='↑↓ select · ‹ › change · enter toggle/edit · esc back'
  col=$(( (cols - ${#line}) / 2 + 1 )); (( col < 1 )) && col=1
  at $r $col; printf '%s[2m%s%s[0m' "$esc" "$line" "$esc"
  at 1 $(( cols - 2 )); printf '%s[1;38;5;203m✗%s[0m' "$esc" "$esc"
}

printf '%s[?25l' "$esc"
draw
mouse_on

while :; do
  read -srk1 ch 2>/dev/null || break
  key=''
  if [[ "$ch" == "$esc" ]]; then
    ch2=''
    if ! read -srk1 -t 0.05 ch2 2>/dev/null; then
      key=back
    elif [[ "$ch2" == '[' ]]; then
      seq=''
      while read -srk1 -t 0.05 c3 2>/dev/null; do
        seq+=$c3
        [[ "$c3" == [A-Za-z~] ]] && break
      done
      case "$seq" in
        A) key=up ;;
        B) key=down ;;
        C) key=right ;;
        D) key=left ;;
        '<'*M)
          body=${seq#<}; body=${body%M}
          btn=${body%%;*}; restxy=${body#*;}
          cx=${restxy%%;*}; cy=${restxy#*;}
          if [[ "$btn" == 0 && "$cx" == <-> && "$cy" == <-> ]]; then
            if (( cy >= first_row && cy < first_row + n_opts && \
                  cx >= box_col && cx < box_col + box_w )); then
              i=$(( cy - first_row + 1 ))
              # First click lands the cursor; a click on the already-selected
              # row is the change gesture, so a misclick can't toggle.
              if (( i == sel )); then key=right; else sel=$i; draw; fi
            else
              key=back
            fi
          fi
          ;;
      esac
    else
      key=back
    fi
  else
    case "$ch" in
      $'\n'|$'\r') key=right ;;
      k) key=up ;;
      j|$'\t') key=down ;;
      h) key=left ;;
      l) key=right ;;
      q|Q) key=back ;;
    esac
  fi
  case "$key" in
    up)    (( sel = sel == 1 ? n_opts : sel - 1 )); draw ;;
    down)  (( sel = sel == n_opts ? 1 : sel + 1 )); draw ;;
    left)  change $sel -1; draw ;;
    right) change $sel 1; draw ;;
    back)  break ;;
  esac
done
