# savers/bounce.sh — the DVD logo, except it's the CLAUDE logo.
#
# Sourced by grid-saver.sh, which has already set rows, cols, accent and sess.
#
# Recolours on every wall, and keeps a running count of exact corner hits —
# the thing everyone has actually been waiting for. A corner is both axes
# flipping on the SAME frame, which is rare enough to be worth a tally and a
# few frames of celebration.
#
# The art mirrors splash.sh's `art_claude`. It's duplicated rather than shared
# because splash.sh is a script that renders when sourced, not a library, and
# six lines of ASCII is a cheaper copy than the refactor to make it importable.
#
# Three sizes: the terminal may be a quarter of a grid rather than a full
# screen, and a logo wider than its box can't bounce. Widths are hardcoded —
# ${#s} counts bytes, not columns, on these glyphs unless the locale cooperates.

BIG=(
' ██████╗██╗      █████╗ ██╗   ██╗██████╗ ███████╗'
'██╔════╝██║     ██╔══██╗██║   ██║██╔══██╗██╔════╝'
'██║     ██║     ███████║██║   ██║██║  ██║█████╗'
'██║     ██║     ██╔══██║██║   ██║██║  ██║██╔══╝'
'╚██████╗███████╗██║  ██║╚██████╔╝██████╔╝███████╗'
' ╚═════╝╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚══════╝'
)
MID=(
'╔═╗╦  ╔═╗╦ ╦╔╦╗╔═╗'
'║  ║  ╠═╣║ ║ ║║║╣ '
'╚═╝╩═╝╩ ╩╚═╝═╩╝╚═╝'
)
SMALL=('CLAUDE')

animate() {
  BOUNCE_COLORS=("$accent")
  for c in $GRID_PALETTE; do BOUNCE_COLORS+=("${c#colour}"); done
  nc=${#BOUNCE_COLORS[@]}

  # Pick the largest logo with room left to actually travel — a sprite that
  # exactly fills its box just vibrates.
  if [ "$cols" -gt 60 ] && [ "$rows" -gt 12 ]; then
    ART=("${BIG[@]}");   w=49; h=6
  elif [ "$cols" -gt 26 ] && [ "$rows" -gt 7 ]; then
    ART=("${MID[@]}");   w=18; h=3
  else
    ART=("${SMALL[@]}"); w=6;  h=1
  fi

  blank=''
  i=0
  while [ "$i" -lt "$w" ]; do blank="$blank "; i=$((i + 1)); done

  # The bottom row belongs to the tally, so the sprite's floor is rows-h.
  maxx=$(( cols - w + 1 )); [ "$maxx" -lt 1 ] && maxx=1
  maxy=$(( rows - h ));     [ "$maxy" -lt 1 ] && maxy=1

  x=$(( RANDOM % maxx + 1 ))
  y=$(( RANDOM % maxy + 1 ))
  dx=1; dy=1
  yacc=0
  col=${BOUNCE_COLORS[$(( RANDOM % nc ))]}
  corners=0
  jackpot=0
  ox=$x; oy=$y

  printf '\e[2J'
  while :; do
    frame=''
    # Erase the whole previous footprint rather than just the trailing edge:
    # one extra w*h of spaces per frame buys immunity to every off-by-one in
    # the bounce arithmetic, and it all goes out in a single write anyway.
    r=0
    while [ "$r" -lt "$h" ]; do
      frame="$frame\e[$(( oy + r ));${ox}H${blank}"
      r=$(( r + 1 ))
    done

    if [ "$jackpot" -gt 0 ]; then
      col=${BOUNCE_COLORS[$(( RANDOM % nc ))]}
      jackpot=$(( jackpot - 1 ))
      sty="1;38;5;${col}"
    else
      sty="1;38;5;${col}"
    fi
    r=0
    while [ "$r" -lt "$h" ]; do
      frame="$frame\e[$(( y + r ));${x}H\e[${sty}m${ART[$r]}"
      r=$(( r + 1 ))
    done

    if [ "$corners" -gt 0 ]; then
      tally="corners: $corners"
      tc=$(( (cols - ${#tally}) / 2 + 1 )); [ "$tc" -lt 1 ] && tc=1
      frame="$frame\e[${rows};${tc}H\e[2;38;5;${accent}m${tally}\e[0m"
    fi

    printf '%b' "$frame"

    ox=$x; oy=$y
    hitx=0; hity=0

    x=$(( x + dx ))
    if [ "$x" -lt 1 ];        then x=1;    dx=1;  hitx=1; fi
    if [ "$x" -gt "$maxx" ];  then x=$maxx; dx=-1; hitx=1; fi

    # Vertical travel is halved: a cell is about twice as tall as it is wide,
    # so equal steps on both axes send the logo round at a permanent 63°
    # instead of the lazy 45° the original had.
    yacc=$(( yacc + 1 ))
    if [ "$yacc" -ge 2 ]; then
      yacc=0
      y=$(( y + dy ))
      if [ "$y" -lt 1 ];       then y=1;    dy=1;  hity=1; fi
      if [ "$y" -gt "$maxy" ]; then y=$maxy; dy=-1; hity=1; fi
    fi

    if [ "$hitx" -eq 1 ] || [ "$hity" -eq 1 ]; then
      col=${BOUNCE_COLORS[$(( RANDOM % nc ))]}
      if [ "$hitx" -eq 1 ] && [ "$hity" -eq 1 ]; then
        corners=$(( corners + 1 ))
        jackpot=24
      fi
    fi

    sleep 0.05
  done
}
