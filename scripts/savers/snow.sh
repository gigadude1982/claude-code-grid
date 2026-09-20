# savers/snow.sh — snow that drifts, lands, and piles up.
#
# Sourced by grid-saver.sh, which has already set rows, cols, accent, sess and
# the SAV_SGR ramp. Composable: SAVER_DELAY plus saver_begin/saver_frame, so it
# runs on its own or as the backdrop under the standby panel.
#
# The accumulation is the point. Falling flakes on their own are a screensaver
# you've seen; a floor that slowly grows drifts, slumps when one gets too steep,
# and eventually melts away to start again is one worth glancing back at. Come
# back after an hour and the snow is deep.
#
# Sway comes from a six-step table indexed by the frame counter plus a per-flake
# offset, applied every third frame. No trigonometry (bash 3.2 has no floats),
# and the per-flake offset is what stops the whole field swaying in unison like
# a curtain.
#
# ground[x] is the pile depth in column x. A flake lands when it reaches
# rows-ground[x], so the pile's own surface is the floor — which is why drifts
# build on drifts instead of everything settling flat.

SAVER_DELAY=0.06

saver_begin() {
  n=$(( cols / 3 + 8 ))
  [ "$n" -gt 80 ] && n=80

  SWAY=(0 1 1 0 -1 -1)
  GL=('*' '·' '+')
  maxpile=$(( rows / 3 )); [ "$maxpile" -lt 2 ] && maxpile=2

  for (( c = 0; c <= cols + 1; c++ )); do ground[$c]=0; done
  total=0
  limit=$(( cols * maxpile * 8 / 10 ))

  for (( i = 0; i < n; i++ )); do
    fx[$i]=$(( RANDOM % cols + 1 ))
    fy[$i]=$(( RANDOM % rows + 1 ))
    fs[$i]=$(( RANDOM % 2 + 1 ))
    fa[$i]=0
    fp[$i]=$(( RANDOM % 6 ))
    fg[$i]=$(( RANDOM % 3 ))
    px[$i]=-1
  done

  tick=0
  printf '\e[2J'
}

saver_frame() {
  tick=$(( tick + 1 ))

  for (( i = 0; i < n; i++ )); do
    if [ "${px[$i]}" -ge 0 ]; then
      sav_hidden "${py[$i]}" "${px[$i]}" || frame="$frame\e[${py[$i]};${px[$i]}H "
    fi

    x=${fx[$i]}
    y=${fy[$i]}

    [ $(( tick % 3 )) -eq 0 ] && x=$(( x + SWAY[(tick / 3 + fp[i]) % 6] ))
    [ "$x" -lt 1 ] && x=$cols
    [ "$x" -gt "$cols" ] && x=1

    fa[$i]=$(( fa[i] + fs[i] ))
    if [ "${fa[$i]}" -ge 2 ]; then
      fa[$i]=0
      y=$(( y + 1 ))
    fi

    floor=$(( rows - ground[x] ))
    if [ "$y" -ge "$floor" ]; then
      # Land — but slump into a lower neighbour first if this column has
      # become a spire. Without this the same few columns win every flake
      # and the floor grows teeth instead of drifts.
      lx=$x
      if [ "$x" -gt 1 ] && [ $(( ground[x] - ground[x-1] )) -ge 2 ]; then
        lx=$(( x - 1 ))
      elif [ "$x" -lt "$cols" ] && [ $(( ground[x] - ground[x+1] )) -ge 2 ]; then
        lx=$(( x + 1 ))
      fi
      if [ "${ground[$lx]}" -lt "$maxpile" ]; then
        ground[$lx]=$(( ground[lx] + 1 ))
        total=$(( total + 1 ))
        ly=$(( rows - ground[lx] + 1 ))
        # The pile still GROWS behind the panel even though it isn't drawn
        # there — the drift has to be continuous when the panel later shrinks
        # or the geometry change would reveal a notch in the snow.
        sav_hidden "$ly" "$lx" || frame="$frame\e[${ly};${lx}H\e[${SAV_SGR[1]}m█"
      fi
      fx[$i]=$(( RANDOM % cols + 1 ))
      fy[$i]=$(( RANDOM % 3 - 3 ))
      fs[$i]=$(( RANDOM % 2 + 1 ))
      fg[$i]=$(( RANDOM % 3 ))
      px[$i]=-1
      continue
    fi

    fx[$i]=$x
    fy[$i]=$y
    if [ "$y" -ge 1 ]; then
      if sav_hidden "$y" "$x"; then
        px[$i]=-1
      else
        frame="$frame\e[${y};${x}H\e[${SAV_SGR[3]}m${GL[${fg[$i]}]}"
        px[$i]=$x
        py[$i]=$y
      fi
    else
      px[$i]=-1
    fi
  done

  # A thaw, so a terminal left locked overnight isn't just a solid block.
  if [ "$total" -ge "$limit" ]; then
    frame="$frame\e[2J"
    for (( c = 0; c <= cols + 1; c++ )); do ground[$c]=0; done
    total=0
    for (( i = 0; i < n; i++ )); do px[$i]=-1; done
    # The wipe took the panel with it. Ask for it back rather than leaving a
    # hole until its next scheduled redraw — sb_overlay_frame is only defined
    # in a composite, hence the guard.
    [ "$(type -t sb_overlay_dirty 2>/dev/null)" = function ] && sb_overlay_dirty
  fi
}
