# savers/bricks.sh — a paddle, a ball and a wall of bricks, played by the
# machine. Clear the wall and it comes back faster; lose three balls and it's
# game over, a fresh wall, and the high score kept on disk.
#
# Sourced by grid-saver.sh (rows, cols, accent, SAV_SGR, sav_sound,
# sav_hiscore). Composable in form, so @grid_saver_opacity applies; not a
# backdrop.
#
# The bricks are coloured by row from GRID_PALETTE and each row has its own
# note, high at the top — clearing a column plays a little scale.
#
# The paddle tracks the ball to a point it has picked on itself, which sets
# the return angle. Now and then it dozes: half speed and a bad aim for one
# descent. That's where lives go; a paddle that never misses would clear every
# wall at the same pace forever.
#
# Fixed point, hundredths of a cell. The ball's vertical speed is half its
# horizontal (cells are tall), and it never moves more than one cell on either
# axis per frame, so a brick can't be tunnelled through.

SAVER_DELAY=0.035

saver_begin() {
  local c
  BR_SGR=()
  for c in $GRID_PALETTE; do
    sav_sgr_idx "${c#colour}"
    BR_SGR+=("$SAV_OUT")
  done

  bw=6                                  # 5 cells of brick and 1 of mortar
  nper=$(( (cols - 2) / bw )); [ "$nper" -lt 3 ] && nper=3
  bx0=$(( (cols - nper * bw) / 2 + 1 ))
  nbr=5
  [ "$rows" -lt 18 ] && nbr=3
  [ "$rows" -lt 12 ] && nbr=2
  btop=4
  [ "$rows" -lt 12 ] && btop=3
  py=$(( rows - 1 ))
  pw=9; [ "$cols" -lt 40 ] && pw=7
  pad_s=''
  c=0; while [ "$c" -lt "$pw" ]; do pad_s="${pad_s}▀"; c=$(( c + 1 )); done
  pad_b=''
  c=0; while [ "$c" -lt "$pw" ]; do pad_b="$pad_b "; c=$(( c + 1 )); done

  hi=$(sav_hiscore bricks)
  br_newgame
  sav_sound start
}

br_newgame() {
  score=0; lives=3; level=1
  SAVER_DELAY=0.035
  over=0
  br_wall
}

# br_wall — a full wall, drawn from scratch.
br_wall() {
  local r c x s
  printf '\e[2J'
  BRICK=()
  left=$(( nper * nbr ))
  s="█████"
  r=0
  while [ "$r" -lt "$nbr" ]; do
    printf '\e[%sm' "${BR_SGR[$(( r % ${#BR_SGR[@]} ))]}"
    c=0
    while [ "$c" -lt "$nper" ]; do
      BRICK[$(( r * nper + c ))]=1
      x=$(( bx0 + c * bw ))
      printf '\e[%d;%dH%s' $(( btop + r )) "$x" "$s"
      c=$(( c + 1 ))
    done
    r=$(( r + 1 ))
  done
  printf '\e[0m'
  px=$(( (cols - pw) / 2 + 1 )); opx=$px
  br_ball
}

# br_ball — a new ball, sitting on the paddle, launched after a beat.
br_ball() {
  bx=$(( (px + pw / 2) * 100 + 50 ))
  by=$(( (py - 1) * 100 + 50 ))
  vx=100; [ $(( RANDOM % 2 )) -eq 0 ] && vx=-100
  vy=-50
  obx=0; oby=0
  pause=35
  doze=0
  aim=0
}

# br_at <col> <row> — sets hit to the brick index under that cell, or -1.
br_at() {
  local r=$(( $2 - btop )) c
  hit=-1
  [ "$r" -ge 0 ] && [ "$r" -lt "$nbr" ] || return 0
  [ "$1" -ge "$bx0" ] || return 0
  c=$(( ($1 - bx0) / bw ))
  [ "$c" -lt "$nper" ] || return 0
  [ "${BRICK[$(( r * nper + c ))]:-0}" = 1 ] && hit=$(( r * nper + c ))
  return 0
}

br_hud() {
  local s l ls lv="" i=0 hs
  while [ "$i" -lt "$lives" ]; do lv="${lv}● "; i=$(( i + 1 )); done
  hs=$hi; [ "$score" -gt "$hs" ] && hs=$score
  printf -v s 'SCORE %05d' "$score"
  printf -v l 'HI %05d   LEVEL %d' "$hs" "$level"
  printf -v ls 'LV %d' "$level"
  sav_hud "$s" "$lv" 7 "$l" "$ls"
}

saver_frame() {
  local col row ocol orow nbx nby c target spd
  br_hud

  if [ "$over" -gt 0 ]; then
    over=$(( over - 1 ))
    if [ "$over" -eq 0 ]; then br_newgame; return; fi
    c=$(( (cols - 9) / 2 + 1 ))
    if [ $(( over / 8 % 2 )) -eq 0 ]; then
      frame="$frame\e[$(( rows / 2 + 2 ));${c}H\e[${SAV_SGR[3]}mGAME OVER\e[0m"
    else
      frame="$frame\e[$(( rows / 2 + 2 ));${c}H         "
    fi
    return
  fi

  [ "$obx" -gt 0 ] && frame="$frame\e[${oby};${obx}H "

  # The paddle. While the ball is coming down it chases its aim point; going
  # up, it wanders back toward the ball's column at a stroll.
  opx=$px
  spd=2; [ "$doze" -eq 1 ] && spd=1
  target=$(( bx / 100 - pw / 2 - aim ))
  if [ "$vy" -gt 0 ] || [ "$pause" -gt 0 ] || [ $(( RANDOM % 3 )) -eq 0 ]; then
    [ "$vy" -lt 0 ] && spd=1
    if [ "$px" -lt "$target" ]; then
      px=$(( px + spd )); [ "$px" -gt "$target" ] && px=$target
    elif [ "$px" -gt "$target" ]; then
      px=$(( px - spd )); [ "$px" -lt "$target" ] && px=$target
    fi
  fi
  [ "$px" -lt 1 ] && px=1
  [ "$px" -gt $(( cols - pw + 1 )) ] && px=$(( cols - pw + 1 ))
  frame="$frame\e[${py};${opx}H$pad_b\e[${SAV_SGR[1]}m\e[${py};${px}H$pad_s\e[0m"

  if [ "$pause" -gt 0 ]; then
    pause=$(( pause - 1 ))
    # The ball rides the paddle until it launches.
    bx=$(( (px + pw / 2) * 100 + 50 ))
    col=$(( bx / 100 )); row=$(( by / 100 ))
    frame="$frame\e[${SAV_SGR[3]}m\e[${row};${col}H●\e[0m"
    obx=$col; oby=$row
    return
  fi

  ocol=$(( bx / 100 )); orow=$(( by / 100 ))
  nbx=$(( bx + vx )); nby=$(( by + vy ))
  if [ "$nbx" -lt 100 ]; then nbx=$(( 200 - nbx )); vx=$(( -vx )); sav_sound wall; fi
  if [ "$nbx" -gt $(( cols * 100 + 99 )) ]; then nbx=$(( 2 * (cols * 100 + 99) - nbx )); vx=$(( -vx )); sav_sound wall; fi
  if [ "$nby" -lt 200 ]; then nby=$(( 400 - nby )); vy=$(( -vy )); sav_sound wall; fi

  # A brick in the way: knock it out and bounce off whichever face was hit —
  # the top or bottom if the move changed rows, a side if it didn't.
  br_at $(( nbx / 100 )) $(( nby / 100 ))
  if [ "$hit" -ge 0 ]; then
    BRICK[$hit]=0
    left=$(( left - 1 ))
    c=$(( hit / nper ))
    score=$(( score + (nbr - c) * 10 ))
    frame="$frame\e[$(( btop + c ));$(( bx0 + (hit % nper) * bw ))H     "
    sav_sound "brick$(( c % 5 ))"
    if [ $(( nby / 100 )) -ne "$orow" ]; then vy=$(( -vy )); nby=$by
    else vx=$(( -vx )); nbx=$bx; fi
  fi
  bx=$nbx; by=$nby
  col=$(( bx / 100 )); row=$(( by / 100 ))

  # The paddle: met on the way down, in the row above it. Where it lands on
  # the paddle picks the new angle — the edges send it out flat and fast.
  if [ "$vy" -gt 0 ] && [ "$row" -ge $(( py - 1 )) ] && [ "$orow" -lt $(( py - 1 )) ] \
     && [ "$col" -ge $(( px - 1 )) ] && [ "$col" -le $(( px + pw )) ]; then
    c=$(( (col - px) * 5 / pw ))
    case $c in
      -*|0) vx=-150 ;; 1) vx=-100 ;; 2) [ "$vx" -lt 0 ] && vx=-50 || vx=50 ;; 3) vx=100 ;; *) vx=150 ;;
    esac
    vy=-50
    by=$(( (py - 1) * 100 + 50 )); row=$(( py - 1 ))
    sav_sound blip
    aim=$(( RANDOM % pw - pw / 2 ))
    doze=0
    if [ $(( RANDOM % 100 )) -lt 12 ]; then
      doze=1; aim=$(( pw / 2 + 2 )); [ $(( RANDOM % 2 )) -eq 0 ] && aim=$(( -aim ))
    fi
  fi

  if [ "$row" -gt "$rows" ]; then
    lives=$(( lives - 1 ))
    obx=0
    if [ "$lives" -le 0 ]; then
      sav_sound die
      [ "$score" -gt "$hi" ] && { hi=$score; sav_hiscore_save bricks "$score"; }
      over=90
    else
      sav_sound miss
      br_ball
    fi
    return
  fi

  if [ "$left" -le 0 ]; then
    sav_sound level
    level=$(( level + 1 ))
    [ "$score" -gt "$hi" ] && { hi=$score; sav_hiscore_save bricks "$score"; }
    SAVER_DELAY=$(awk -v d="$SAVER_DELAY" 'BEGIN { d -= .004; if (d < .018) d = .018; print d }')
    br_wall
    return
  fi

  if [ "$row" -le "$rows" ] && [ "$row" -ge 2 ]; then
    frame="$frame\e[${SAV_SGR[3]}m\e[${row};${col}H●\e[0m"
    obx=$col; oby=$row
  else
    obx=0
  fi
}
