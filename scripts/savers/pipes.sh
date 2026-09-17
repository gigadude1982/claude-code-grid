# savers/pipes.sh — the screensaver everyone's office PC ran in 1995.
#
# Sourced by grid-saver.sh, which has already set rows, cols, accent and sess.
#
# Each pipe walks one cell per frame, mostly straight, occasionally bending.
# The glyph drawn is decided by the turn, not the heading: a pipe arriving at a
# cell leaves an arm pointing back the way it came, and another pointing where
# it goes next. Moving up and bending right means arms pointing DOWN and RIGHT,
# which is ╭ — the table below reads inside-out until you see that, so it's
# spelled out rather than derived.
#
# Colours come from GRID_PALETTE (grid-lib.sh, already sourced by the host) with
# the session's accent mixed in, so the pipes speak the same colour language as
# the pane borders. The screen fills and clears rather than scrolling, and a
# pipe that walks off an edge wraps to the other side in a new colour.

_pipe_spawn() { # <i> — drop pipe i somewhere new
  local i=$1
  px[$i]=$(( RANDOM % cols + 1 ))
  py[$i]=$(( RANDOM % rows + 1 ))
  pd[$i]=$(( RANDOM % 4 ))
  pc[$i]=${PIPE_COLORS[$(( RANDOM % ${#PIPE_COLORS[@]} ))]}
}

animate() {
  PIPE_COLORS=("$accent")
  for c in $GRID_PALETTE; do PIPE_COLORS+=("${c#colour}"); done

  np=6
  [ "$cols" -lt 60 ] && np=3
  for (( i = 0; i < np; i++ )); do _pipe_spawn $i; done

  # Clear once the screen is three-quarters full. Pipes never erase — without
  # a reset the terminal just saturates into a solid block of colour.
  budget=$(( rows * cols * 3 / 4 ))
  drawn=0

  while :; do
    frame=''
    for (( i = 0; i < np; i++ )); do
      d=${pd[$i]}
      # ~1 frame in 7 bends. Reversing is never offered: a pipe doubling back
      # over itself is the one move that reads as a glitch.
      roll=$(( RANDOM % 14 ))
      if   [ "$roll" -eq 0 ]; then nd=$(( (d + 1) % 4 ))
      elif [ "$roll" -eq 1 ]; then nd=$(( (d + 3) % 4 ))
      else                        nd=$d
      fi

      if [ "$nd" -eq "$d" ]; then
        if [ "$d" -eq 0 ] || [ "$d" -eq 2 ]; then g='│'; else g='─'; fi
      else
        # 0 up · 1 right · 2 down · 3 left, read as "<came in heading><leaves heading>"
        case "$d$nd" in
          01) g='╭' ;; 03) g='╮' ;;
          21) g='╰' ;; 23) g='╯' ;;
          10) g='╯' ;; 12) g='╮' ;;
          30) g='╰' ;; 32) g='╭' ;;
          *)  g='│' ;;
        esac
      fi
      frame="$frame\e[${py[$i]};${px[$i]}H\e[1;38;5;${pc[$i]}m$g"

      x=${px[$i]}
      y=${py[$i]}
      case "$nd" in
        0) y=$(( y - 1 )) ;;
        1) x=$(( x + 1 )) ;;
        2) y=$(( y + 1 )) ;;
        3) x=$(( x - 1 )) ;;
      esac
      # Wrapping recolours: the jump across the screen is a discontinuity
      # either way, and a colour change makes it read as a new pipe rather
      # than a rendering fault.
      wrapped=0
      [ "$x" -lt 1 ]       && { x=$cols; wrapped=1; }
      [ "$x" -gt "$cols" ] && { x=1;     wrapped=1; }
      [ "$y" -lt 1 ]       && { y=$rows; wrapped=1; }
      [ "$y" -gt "$rows" ] && { y=1;     wrapped=1; }
      [ "$wrapped" -eq 1 ] && pc[$i]=${PIPE_COLORS[$(( RANDOM % ${#PIPE_COLORS[@]} ))]}

      pd[$i]=$nd
      px[$i]=$x
      py[$i]=$y
      drawn=$(( drawn + 1 ))
    done

    if [ "$drawn" -gt "$budget" ]; then
      frame="\e[2J$frame"
      drawn=0
      for (( i = 0; i < np; i++ )); do _pipe_spawn $i; done
    fi

    printf '%b' "$frame"
    sleep 0.035
  done
}
