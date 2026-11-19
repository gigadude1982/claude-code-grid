# savers/volley.sh — paddle tennis: two machines rallying, first to 11.
#
# Sourced by grid-saver.sh, which has already set rows, cols, accent and the
# SAV_SGR ramp, and defined sav_sound. Composable in form (SAVER_DELAY plus
# saver_begin/saver_frame), so it honours @grid_saver_opacity — but it is not
# a backdrop: a game is a thing to watch, not a texture.
#
# Neither paddle is perfect. Each one, as the ball turns toward it, picks where
# on itself it MEANS to meet the ball; usually that's somewhere on the paddle
# (which also decides the return angle), and about one time in six it's just
# past the edge. That one miss is the whole game — a pair of perfect players
# rally forever, and a screensaver that never changes is a still image.
#
# Positions are fixed-point, hundredths of a cell. The ball moves one column a
# frame and well under a row: cells are about twice as tall as they are wide,
# so equal steps would look like a 63° slope and the court would feel narrow.
#
# Bash 3.2, like every saver: no associative arrays, no fractional read -t.

SAVER_DELAY=0.04

# A 3x5 digit face, '#' for lit. Defined in ASCII and translated once in
# saver_begin, because substring offsets on '█' count bytes on bash 3.2 in
# some locales and characters in others.
VOL_FONT='###''# #''# #''# #''###'\
' # ''## '' # '' # ''###'\
'###''  #''###''#  ''###'\
'###''  #'' ##''  #''###'\
'# #''# #''###''  #''  #'\
'###''#  ''###''  #''###'\
'###''#  ''###''# #''###'\
'###''  #''  #''  #''  #'\
'###''# #''###''# #''###'\
'###''# #''###''  #''###'

saver_begin() {
  local d r s
  VOL_DIG=()
  d=0
  while [ "$d" -lt 10 ]; do
    r=0
    while [ "$r" -lt 5 ]; do
      s=${VOL_FONT:$(( d * 15 + r * 3 )):3}
      VOL_DIG[$(( d * 5 + r ))]=${s//\#/█}
      r=$(( r + 1 ))
    done
    d=$(( d + 1 ))
  done

  ph=$(( rows / 6 )); [ "$ph" -lt 3 ] && ph=3
  half=$(( ph / 2 ))
  lx=3; rx=$(( cols - 2 ))
  ly=$(( (rows - ph) / 2 )); ry=$ly
  oly=$ly; ory=$ry
  net=$(( cols / 2 ))
  ymin=200; ymax=$(( (rows - 1) * 100 + 99 ))
  sl=0; sr=0
  rally=0
  big=0
  [ "$rows" -ge 16 ] && [ "$cols" -ge 44 ] && big=1
  tick=0

  wall_top='' wall_bot=''
  r=0
  while [ "$r" -lt "$cols" ]; do wall_top="${wall_top}▄"; wall_bot="${wall_bot}▀"; r=$(( r + 1 )); done

  printf '\e[2J\e[1;1H\e[%sm%s\e[%d;1H%s\e[0m' "${SAV_SGR[0]}" "$wall_top" "$rows" "$wall_bot"
  vol_serve $(( RANDOM % 2 ))
  sav_sound start
}

# vol_aim — where the paddle about to receive means to meet the ball,
# relative to its own centre. Mostly on the paddle, sometimes just off it.
vol_aim() {
  if [ $(( RANDOM % 100 )) -lt 84 ]; then
    aim=$(( RANDOM % ph - half ))
  else
    aim=$(( half + 1 + RANDOM % 3 ))
    [ $(( RANDOM % 2 )) -eq 0 ] && aim=$(( -aim ))
  fi
}

# vol_serve <0|1> — from the net, toward the left (0) or the right (1).
vol_serve() {
  bx=$(( net * 100 + 50 ))
  by=$(( (rows / 2) * 100 + 50 ))
  if [ "$1" -eq 0 ]; then vx=-100; else vx=100; fi
  vy=$(( 25 + RANDOM % 30 ))
  [ $(( RANDOM % 2 )) -eq 0 ] && vy=$(( -vy ))
  rally=0
  pause=25
  vol_aim
  obx=0; oby=0
}

# vol_digits <score> <first column> — one score, drawn big or small.
vol_digits() {
  local n=$1 c=$2 r t o
  if [ "$big" -eq 1 ]; then
    t=$(( n / 10 )); o=$(( n % 10 ))
    r=0
    while [ "$r" -lt 5 ]; do
      if [ "$t" -gt 0 ]; then
        frame="$frame\e[$(( 3 + r ));${c}H${VOL_DIG[$(( t * 5 + r ))]} ${VOL_DIG[$(( o * 5 + r ))]}"
      else
        frame="$frame\e[$(( 3 + r ));${c}H    ${VOL_DIG[$(( o * 5 + r ))]}"
      fi
      r=$(( r + 1 ))
    done
  else
    frame="$frame\e[2;${c}H$(printf '%2d' "$n")"
  fi
}

# vol_paddle <column> <old top> <new top> — clear what moved off, draw the rest.
vol_paddle() {
  local c=$1 o=$2 n=$3 r
  r=0
  while [ "$r" -lt "$ph" ]; do
    frame="$frame\e[$(( o + r ));${c}H "
    r=$(( r + 1 ))
  done
  frame="$frame\e[${SAV_SGR[1]}m"
  r=0
  while [ "$r" -lt "$ph" ]; do
    frame="$frame\e[$(( n + r ));${c}H█"
    r=$(( r + 1 ))
  done
}

saver_frame() {
  local col row ocol target c r
  tick=$(( tick + 1 ))

  # The old ball goes first, so the net and the scores can paint back over
  # whatever it was standing on.
  if [ "$obx" -gt 0 ]; then
    frame="$frame\e[0m\e[${oby};${obx}H "
  fi

  # The net: a dashed line, every other row.
  frame="$frame\e[${SAV_SGR[0]}m"
  r=2
  while [ "$r" -lt "$rows" ]; do
    [ $(( r % 2 )) -eq 0 ] && frame="$frame\e[${r};${net}H┃"
    r=$(( r + 1 ))
  done
  if [ "$big" -eq 1 ]; then
    vol_digits "$sl" $(( net - 10 ))
    vol_digits "$sr" $(( net + 3 ))
  else
    vol_digits "$sl" $(( net - 4 ))
    vol_digits "$sr" $(( net + 2 ))
  fi

  # The machines. The one the ball is heading for tracks it to its aim point;
  # the other drifts back to the middle, unhurried — every third frame.
  oly=$ly; ory=$ry
  if [ "$pause" -eq 0 ] && [ "$vx" -lt 0 ]; then
    target=$(( by / 100 - aim - half ))
    if [ "$ly" -lt "$target" ]; then ly=$(( ly + 1 )); elif [ "$ly" -gt "$target" ]; then ly=$(( ly - 1 )); fi
  elif [ $(( tick % 3 )) -eq 0 ]; then
    target=$(( (rows - ph) / 2 ))
    if [ "$ly" -lt "$target" ]; then ly=$(( ly + 1 )); elif [ "$ly" -gt "$target" ]; then ly=$(( ly - 1 )); fi
  fi
  if [ "$pause" -eq 0 ] && [ "$vx" -gt 0 ]; then
    target=$(( by / 100 - aim - half ))
    if [ "$ry" -lt "$target" ]; then ry=$(( ry + 1 )); elif [ "$ry" -gt "$target" ]; then ry=$(( ry - 1 )); fi
  elif [ $(( tick % 3 )) -eq 0 ]; then
    target=$(( (rows - ph) / 2 ))
    if [ "$ry" -lt "$target" ]; then ry=$(( ry + 1 )); elif [ "$ry" -gt "$target" ]; then ry=$(( ry - 1 )); fi
  fi
  [ "$ly" -lt 2 ] && ly=2; [ "$ly" -gt $(( rows - ph )) ] && ly=$(( rows - ph ))
  [ "$ry" -lt 2 ] && ry=2; [ "$ry" -gt $(( rows - ph )) ] && ry=$(( rows - ph ))
  vol_paddle "$lx" "$oly" "$ly"
  vol_paddle "$rx" "$ory" "$ry"

  # Between points the ball is off the table.
  if [ "$pause" -gt 0 ]; then
    pause=$(( pause - 1 ))
    if [ "$pause" -eq 0 ] && { [ "$sl" -ge 11 ] || [ "$sr" -ge 11 ]; }; then
      sl=0; sr=0
    fi
    obx=0
    frame="$frame\e[0m"
    return
  fi

  ocol=$(( bx / 100 ))
  bx=$(( bx + vx ))
  by=$(( by + vy ))
  if [ "$by" -lt "$ymin" ]; then by=$(( 2 * ymin - by )); vy=$(( -vy )); sav_sound wall; fi
  if [ "$by" -gt "$ymax" ]; then by=$(( 2 * ymax - by )); vy=$(( -vy )); sav_sound wall; fi
  col=$(( bx / 100 ))
  row=$(( by / 100 ))

  # A paddle is met when the ball CROSSES the column in front of it — tested
  # as a crossing rather than an arrival, so a fast ball can't step over it.
  if [ "$vx" -lt 0 ] && [ "$ocol" -gt $(( lx + 1 )) ] && [ "$col" -le $(( lx + 1 )) ] \
     && [ "$row" -ge "$ly" ] && [ "$row" -lt $(( ly + ph )) ]; then
    bx=$(( (lx + 1) * 100 + 50 )); col=$(( lx + 1 ))
    vol_return $(( row - ly - half ))
    vx=$(( -vx ))
  elif [ "$vx" -gt 0 ] && [ "$ocol" -lt $(( rx - 1 )) ] && [ "$col" -ge $(( rx - 1 )) ] \
     && [ "$row" -ge "$ry" ] && [ "$row" -lt $(( ry + ph )) ]; then
    bx=$(( (rx - 1) * 100 + 50 )); col=$(( rx - 1 ))
    vol_return $(( row - ry - half ))
    vx=$(( -vx ))
  fi

  if [ "$col" -lt 1 ]; then
    sr=$(( sr + 1 )); vol_point 1; return
  elif [ "$col" -gt "$cols" ]; then
    sl=$(( sl + 1 )); vol_point 0; return
  fi

  frame="$frame\e[${SAV_SGR[3]}m\e[${row};${col}H■\e[0m"
  obx=$col; oby=$row
}

# vol_return <offset from paddle centre> — the angle comes off where it hit,
# and every fourth return in a rally is a little quicker than the last.
vol_return() {
  vy=$(( $1 * 85 / (half + 1) ))
  [ "$vy" -gt 85 ] && vy=85
  [ "$vy" -lt -85 ] && vy=-85
  if [ "$vy" -gt -15 ] && [ "$vy" -lt 15 ]; then
    vy=$(( 15 + RANDOM % 15 )); [ $(( RANDOM % 2 )) -eq 0 ] && vy=$(( -vy ))
  fi
  rally=$(( rally + 1 ))
  if [ $(( rally % 4 )) -eq 0 ] && [ "$vx" -gt -150 ] && [ "$vx" -lt 150 ]; then
    if [ "$vx" -lt 0 ]; then vx=$(( vx - 10 )); else vx=$(( vx + 10 )); fi
  fi
  sav_sound blip
  vol_aim
}

# vol_point <winner 0=left 1=right> — the loser serves.
vol_point() {
  frame="$frame\e[0m"
  if [ "$sl" -ge 11 ] || [ "$sr" -ge 11 ]; then
    sav_sound level
    vol_serve $(( 1 - $1 ))
    pause=80
  else
    sav_sound point
    vol_serve $(( 1 - $1 ))
  fi
}
