# savers/rain.sh — actual weather, as opposed to the katakana kind.
#
# Sourced by grid-saver.sh, which has already set rows, cols, accent and sess.
#
# Drops fall at two speeds — the fast ones are drawn brighter and read as
# nearer, which is the whole depth cue — and lean with a wind that swings
# slowly back and forth. Each drop that reaches the floor leaves a splash that
# fades over the next few frames, which is what stops the bottom row looking
# like a place drops simply vanish.
#
# ASCII / | \ rather than the box-drawing diagonals: this runs on whatever font
# the terminal happens to have, and ╱ ╲ are missing or badly aligned in enough
# of them to matter.
#
# Splash lifetimes live in one array indexed BY COLUMN rather than a list of
# splash objects — only the floor splashes, at most one splash per column is
# visible at a time, and a fresh drop landing on a wet column just resets it.

animate() {
  n=$(( cols / 2 + 10 ))
  [ "$n" -gt 120 ] && n=120

  for (( i = 0; i < n; i++ )); do
    dx[$i]=$(( RANDOM % cols + 1 ))
    dy[$i]=$(( RANDOM % rows + 1 ))
    ds[$i]=$(( RANDOM % 2 + 1 ))
    px[$i]=-1
  done
  for (( c = 1; c <= cols; c++ )); do sp[$c]=0; done

  # The wind walks this table, one step every 25 frames, so a gust builds and
  # dies over several seconds instead of flickering per frame.
  WINDTAB=(0 0 0 1 1 1 1 1 0 0 0 -1 -1 -1 -1 -1)
  tick=0

  printf '\e[2J'
  while :; do
    wind=${WINDTAB[$(( (tick / 25) % 16 ))]}
    tick=$(( tick + 1 ))
    if   [ "$wind" -gt 0 ]; then g='\\'
    elif [ "$wind" -lt 0 ]; then g='/'
    else                        g='|'
    fi

    frame=''
    for (( i = 0; i < n; i++ )); do
      [ "${px[$i]}" -ge 0 ] && frame="$frame\e[${py[$i]};${px[$i]}H "

      y=$(( dy[i] + ds[i] ))
      x=$(( dx[i] + wind ))
      [ "$x" -lt 1 ] && x=$cols
      [ "$x" -gt "$cols" ] && x=1

      if [ "$y" -ge "$rows" ]; then
        # Landed: wet the column and start again somewhere along the top.
        sp[$x]=3
        dx[$i]=$(( RANDOM % cols + 1 ))
        dy[$i]=$(( RANDOM % 3 - 3 ))
        ds[$i]=$(( RANDOM % 2 + 1 ))
        px[$i]=-1
        continue
      fi

      dx[$i]=$x
      dy[$i]=$y
      if [ "$y" -ge 1 ]; then
        if [ "${ds[$i]}" -eq 2 ]; then st="1;38;5;${accent}"; else st="2;38;5;${accent}"; fi
        frame="$frame\e[${y};${x}H\e[${st}m${g}"
        px[$i]=$x
        py[$i]=$y
      else
        px[$i]=-1
      fi
    done

    # The floor, one pass over the wet columns.
    for (( c = 1; c <= cols; c++ )); do
      l=${sp[$c]}
      [ "$l" -eq 0 ] && continue
      case "$l" in
        3) frame="$frame\e[${rows};${c}H\e[1;97m·" ;;
        2) frame="$frame\e[${rows};${c}H\e[0;38;5;${accent}m·" ;;
        1) frame="$frame\e[${rows};${c}H\e[2;38;5;${accent}m." ;;
      esac
      sp[$c]=$(( l - 1 ))
      [ "${sp[$c]}" -eq 0 ] && frame="$frame\e[${rows};${c}H "
    done

    printf '%b' "$frame"
    sleep 0.05
  done
}
