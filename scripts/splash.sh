#!/bin/zsh
# splash.sh <label> [cols] [rows] — full-pane splash rendered before claude
# launches in a grid pane. Picks a random ASCII art piece that fits the pane,
# centers it, and tints it with the pane's border color (@repo_color) so each
# quadrant's art matches its frame. The repo/branch line sits beneath the art.
# Pane too small for any piece? Degrades to just that line. The splash lives
# on the normal screen (claude runs on the alternate screen), so it's also
# what you see whenever claude exits.
#
# GRID_SPLASH_ART=<name> forces a specific piece (see art_names below).
set -u

label="${1:-}"
cols="${2:-}"; [ -z "$cols" ] && cols=$(tput cols 2>/dev/null); [ -z "$cols" ] && cols=80
rows="${3:-}"; [ -z "$rows" ] && rows=$(tput lines 2>/dev/null); [ -z "$rows" ] && rows=24

art_names=(claude rocket skull robot cat peaks storm moon)

art_claude=$(cat <<'EOF'
 ██████╗██╗      █████╗ ██╗   ██╗██████╗ ███████╗
██╔════╝██║     ██╔══██╗██║   ██║██╔══██╗██╔════╝
██║     ██║     ███████║██║   ██║██║  ██║█████╗
██║     ██║     ██╔══██║██║   ██║██║  ██║██╔══╝
╚██████╗███████╗██║  ██║╚██████╔╝██████╔╝███████╗
 ╚═════╝╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚══════╝
EOF
)

art_rocket=$(cat <<'EOF'
        /\
       /  \
      /    \
     |      |
     | (  ) |
     |      |
     | (  ) |
    /|      |\
   / |      | \
  /  |______|  \
 |__/|      |\__|
     |__/\__|
       /**\
      (****)
       \**/
        \/
EOF
)

art_skull=$(cat <<'EOF'
      ______
   .-"      "-.
  /            \
 |              |
 |,  .-.  .-.  ,|
 | )(__/  \__)( |
 |/     /\     \|
 (_     ^^     _)
  \__|IIIIII|__/
   | \IIIIII/ |
   \          /
    `--------`
EOF
)

art_robot=$(cat <<'EOF'
        [¤]
      .-----.
     | o   o |
     |  ---  |
   .-'-------'-.
  |  |       |  |
  d  |  ===  |  b
     |_______|
       || ||
      _|| ||_
     |__| |__|
EOF
)

art_cat=$(cat <<'EOF'
    /\_____/\
   /  o   o  \
  ( ==  ^  == )
   )         (
  (           )
 ( (  )   (  ) )
(__(__)___(__)__)
EOF
)

art_peaks=$(cat <<'EOF'
       *  .    +   .  *
  .  +    .  /\  .    .
      .     /  \   +
     /\    / ,  \     .
    /  \  / ,    \  /\
   / ,  \/    ,   \/  \
  / .    \  ,   .  \ , \
 /___,____\____,____\___\
EOF
)

art_storm=$(cat <<'EOF'
      .--~~~~~~--.
   .-(            )-.
  (                  )
   `--.__________.--'
         ____
        /   /
       /   /___
      /   ____/
     /   /
    /   /
   /___/
EOF
)

art_moon=$(cat <<'EOF'
      _..._
    .::o:::::.
   ::::::::::::
   :::o::::::::
   :::::::o::::
    `:::::::::'
      `'''''`
EOF
)

# --- pick a piece that fits ---------------------------------------------
art_size() {  # sets reply=(width height)
  local w=0 h=0 line
  while IFS= read -r line; do
    h=$((h + 1))
    (( ${#line} > w )) && w=${#line}
  done <<< "$1"
  reply=($w $h)
}

chosen="" cw=0 ch=0
n=${#art_names[@]}
start=$(( RANDOM % n ))
for i in {0..$(( n - 1 ))}; do
  name=${art_names[$(( (start + i) % n + 1 ))]}
  [ -n "${GRID_SPLASH_ART:-}" ] && name=$GRID_SPLASH_ART
  art="${(P)${:-art_$name}}"
  [ -z "$art" ] && continue
  art_size "$art"
  if (( reply[1] <= cols && reply[2] + 4 <= rows )); then
    chosen=$art cw=$reply[1] ch=$reply[2]
    break
  fi
  [ -n "${GRID_SPLASH_ART:-}" ] && break
done

# --- tint: match the pane's border color, else random from the palette --
c=""
if [ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ]; then
  c=$(tmux display-message -p -t "$TMUX_PANE" '#{@repo_color}' 2>/dev/null)
  c=${c#colour}
fi
case "$c" in
  <->) ;;
  *) palette=(45 141 214 114 203 81 178 135); c=${palette[$(( RANDOM % ${#palette[@]} + 1 ))]} ;;
esac
tint=$'\033[38;5;'"${c}m"
bold=$'\033[1m' dim=$'\033[2;37m' reset=$'\033[0m'

branch=$(git branch --show-current 2>/dev/null)
footer="▸ $label"
[ -n "$branch" ] && footer+=" ($branch)"

# --- render -------------------------------------------------------------
if [ -n "$chosen" ]; then
  printf '\033[2J\033[H'
  top=$(( (rows - ch - 3) / 2 )); (( top < 0 )) && top=0
  for (( i = 0; i < top; i++ )); do print; done
  lpad=$(( (cols - cw) / 2 )); (( lpad < 0 )) && lpad=0
  pad=$(printf '%*s' "$lpad" '')
  while IFS= read -r line; do
    print -r -- "${pad}${tint}${line}${reset}"
  done <<< "$chosen"
  print
  fpad=$(( (cols - ${#footer}) / 2 )); (( fpad < 0 )) && fpad=0
  printf '%*s' "$fpad" ''
fi
printf '%s▸ %s%s' "${bold}${tint}" "$label" "$reset"
[ -n "$branch" ] && printf ' %s(%s)%s' "$dim" "$branch" "$reset"
print
