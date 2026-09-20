# savers/starfield.sh — warp-speed stars streaming out of the centre.
#
# Sourced by grid-saver.sh, which has already set rows, cols, accent, sess and
# the SAV_SGR ramp. Composable: SAVER_DELAY plus saver_begin/saver_frame, so it
# runs on its own or as the backdrop under the standby panel.
#
# No trigonometry and no floats: bash 3.2 has neither. A star is a fixed-point
# direction vector (sdx, sdy, each -1000..1000) and a radius sr that grows by a
# twelfth of itself every frame, which is what makes the field accelerate
# outward instead of drifting. Screen position is just the vector scaled by the
# radius — the divisors below differ by 2x because terminal cells are about
# twice as tall as they are wide, and equal divisors give an oval, not a
# starfield.
#
# Depth reads as brightness: a star starts as a dim accent speck and ends bold
# white just before it leaves the screen.
#
# The radius array is sr[] rather than the obvious r[]. In a composite this
# file and standby.sh share one shell, and standby uses a bare `r` as the loop
# counter that walks the five rows of its block clock — which, against an
# array, assigns to element zero and would quietly teleport star 0 once a
# second. Namespaces are per-process here, not per-file.

_star_spawn() { # <i> — re-roll star i back to the centre
  local i=$1
  sdx[$i]=$(( RANDOM % 2001 - 1000 ))
  sdy[$i]=$(( RANDOM % 2001 - 1000 ))
  # A vector this close to dead centre would crawl for its whole life. Note
  # ${v#-} is the absolute value: stripping the leading minus off the string
  # is cheaper than branching, and -lt still reads it as a number.
  while [ "${sdx[$i]#-}" -lt 150 ] && [ "${sdy[$i]#-}" -lt 150 ]; do
    sdx[$i]=$(( RANDOM % 2001 - 1000 ))
    sdy[$i]=$(( RANDOM % 2001 - 1000 ))
  done
  sr[$i]=200
}

SAVER_DELAY=0.05

saver_begin() {
  cx=$(( cols / 2 + 1 ))
  cy=$(( rows / 2 + 1 ))
  # Density scaled to the terminal, capped: past ~140 stars a frame costs more
  # than the 0.05s between frames and the field visibly stutters.
  n=$(( cols * rows / 30 + 20 ))
  [ "$n" -gt 140 ] && n=140

  for (( i = 0; i < n; i++ )); do
    _star_spawn $i
    # Stagger the radii so the first frame is a full field, not a dot.
    sr[$i]=$(( RANDOM % 5000 + 200 ))
    px[$i]=-1
  done
}

saver_frame() {
  for (( i = 0; i < n; i++ )); do
    if [ "${px[$i]}" -ge 0 ]; then
      sav_hidden "${py[$i]}" "${px[$i]}" || frame="$frame\e[${py[$i]};${px[$i]}H "
    fi
    rr=${sr[$i]}
    x=$(( cx + sdx[i] * rr / 100000 ))
    y=$(( cy + sdy[i] * rr / 200000 ))
    if [ "$x" -lt 1 ] || [ "$x" -gt "$cols" ] || [ "$y" -lt 1 ] || [ "$y" -gt "$rows" ]; then
      _star_spawn $i
      px[$i]=-1
      continue
    fi
    if   [ "$rr" -lt 800 ];  then st=${SAV_SGR[0]}; g='.'
    elif [ "$rr" -lt 2000 ]; then st=${SAV_SGR[1]}; g='·'
    elif [ "$rr" -lt 3500 ]; then st=${SAV_SGR[2]}; g='*'
    else                          st=${SAV_SGR[3]}; g='*'
    fi
    # A star behind the panel keeps travelling but is not drawn, and is not
    # remembered as drawn — otherwise the next frame erases a cell this one
    # never wrote, punching a space through a ledger row.
    if sav_hidden "$y" "$x"; then
      px[$i]=-1
    else
      frame="$frame\e[${y};${x}H\e[${st}m${g}"
      px[$i]=$x
      py[$i]=$y
    fi
    sr[$i]=$(( rr + rr / 12 + 1 ))
  done
}
