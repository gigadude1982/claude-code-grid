# savers/pipes.sh — the screensaver everyone's office PC ran in 1995.
#
# Sourced by grid-saver.sh, which has already set rows, cols, accent, sess and
# the SAV_SGR ramp. Composable: SAVER_DELAY plus saver_begin/saver_frame, so it
# runs on its own or as the backdrop under the standby panel.
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
# the pane borders. Because those are palette colours rather than the accent,
# they can't come from the SAV_SGR ramp — each one is run through sav_sgr_idx
# once at startup instead, which applies the same opacity and keeps the
# arithmetic out of the frame loop.
#
# The screen fills and clears rather than scrolling, and a pipe that walks off
# an edge wraps to the other side in a new colour.
#
# The pipe count is npipe rather than the obvious np. In a composite this file
# and standby.sh share one shell, and standby's np is its PANE count — two
# loops would have walked each other's bounds. Namespaces here are per-process,
# not per-file.

_pipe_spawn() { # <i> — drop pipe i somewhere new
  local i=$1
  px[$i]=$(( RANDOM % cols + 1 ))
  py[$i]=$(( RANDOM % rows + 1 ))
  pd[$i]=$(( RANDOM % 4 ))
  pc[$i]=${PIPE_SGR[$(( RANDOM % ${#PIPE_SGR[@]} ))]}
}

SAVER_DELAY=0.035

saver_begin() {
  PIPE_SGR=()
  sav_sgr_idx "$accent"; PIPE_SGR+=("$SAV_OUT")
  for c in $GRID_PALETTE; do
    sav_sgr_idx "${c#colour}"
    PIPE_SGR+=("$SAV_OUT")
  done

  npipe=6
  [ "$cols" -lt 60 ] && npipe=3
  for (( i = 0; i < npipe; i++ )); do _pipe_spawn $i; done

  # Clear once the screen is three-quarters full. Pipes never erase — without
  # a reset the terminal just saturates into a solid block of colour.
  budget=$(( rows * cols * 3 / 4 ))
  drawn=0
}

saver_frame() {
  for (( i = 0; i < npipe; i++ )); do
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
    sav_hidden "${py[$i]}" "${px[$i]}" \
      || frame="$frame\e[${py[$i]};${px[$i]}H\e[1;${pc[$i]}m$g"

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
    [ "$wrapped" -eq 1 ] && pc[$i]=${PIPE_SGR[$(( RANDOM % ${#PIPE_SGR[@]} ))]}

    pd[$i]=$nd
    px[$i]=$x
    py[$i]=$y
    drawn=$(( drawn + 1 ))
  done

  if [ "$drawn" -gt "$budget" ]; then
    frame="\e[2J$frame"
    drawn=0
    for (( i = 0; i < npipe; i++ )); do _pipe_spawn $i; done
    # The wipe took the panel with it. Ask for it back in this same frame
    # rather than leaving a hole until the next scheduled redraw, which can be
    # a whole second away. Only defined in a composite, hence the guard.
    [ "$(type -t sb_overlay_dirty 2>/dev/null)" = function ] && sb_overlay_dirty
  fi
}
