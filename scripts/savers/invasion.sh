# savers/invasion.sh — a formation marching down the screen, a cannon at the
# bottom holding the line, bunkers between them wearing away. Played by the
# machine; the high score is kept on disk.
#
# Sourced by grid-saver.sh (rows, cols, accent, SAV_SGR, sav_sound,
# sav_hiscore). Composable in form, so @grid_saver_opacity applies; not a
# backdrop.
#
# The sound is most of it. Every step the formation takes plays the next note
# of a four-note bass line, and the formation steps faster as it thins out —
# so the march speeds up on its own as the wave nears its end, and you can
# hear how a wave is going from the next room. A saucer crosses the top now
# and then, warbling; hitting it is worth a guess between 50 and 300.
#
# Shapes are the grid's own — three block-glyph types, two frames each.
#
# The cannon's brain, in order: get out from under a bomb that's close; chase
# a saucer if there is one; otherwise line up under a living column and fire.
# It only ever has one shot in the air, which is what makes it beatable.
#
# Bash 3.2: the formation and the bunkers are flat indexed arrays, row-major.

SAVER_DELAY=0.035

# Alien sprites: [type * 2 + frame], 3 cells wide.
INV_SPR=('▟▀▙' '▜▀▛' '▛█▜' '▙█▟' '◢▅◣' '◥▅◤')
INV_BOOM='░▒░'
INV_GUN='▄█▄'
INV_SAUCER='-=●=-'
INV_BLANK='     '

saver_begin() {
  nrow=5
  [ "$rows" -lt 28 ] && nrow=4
  [ "$rows" -lt 20 ] && nrow=3
  ncol=$(( (cols - 12) / 5 )); [ "$ncol" -gt 10 ] && ncol=10; [ "$ncol" -lt 3 ] && ncol=3
  pr=$(( rows - 1 ))
  brow=$(( pr - 4 ))
  hi=$(sav_hiscore invasion)
  # The host only starts a frame buffer per frame; the first wave draws into
  # one of its own.
  frame=''
  inv_newgame
  printf '%b' "$frame"
  sav_sound start
}

inv_newgame() {
  score=0; lives=3; wave=0
  over=0
  inv_wave
}

inv_wave() {
  local i r c x b nb gap
  printf '\e[2J'
  wave=$(( wave + 1 ))
  ALIVE=()
  i=0
  while [ "$i" -lt $(( nrow * ncol )) ]; do ALIVE[$i]=1; i=$(( i + 1 )); done
  alive=$(( nrow * ncol ))
  total=$alive
  fx=$(( (cols - ncol * 5) / 2 + 1 ))
  fy=$(( 3 + (wave - 1) % 5 ))
  fd=1
  af=0
  note=0
  stepc=0
  EXPX=(); EXPY=(); EXPT=(); EXPW=()
  BX=(); BY=()
  shot=0
  ufo=0
  ppx=$(( cols / 2 - 1 )); oppx=$ppx
  dead=0
  tx=$ppx
  tick=0

  # The bunkers: two rows of five, as many as fit. 2 = whole, 1 = cracked.
  BK=()
  nb=4; [ "$cols" -lt 60 ] && nb=3; [ "$cols" -lt 36 ] && nb=2
  gap=$(( cols / nb ))
  b=0
  while [ "$b" -lt "$nb" ]; do
    x=$(( gap * b + gap / 2 - 1 ))
    r=0
    while [ "$r" -lt 2 ]; do
      c=0
      while [ "$c" -lt 5 ]; do
        BK[$(( (brow + r) * cols + x + c ))]=2
        c=$(( c + 1 ))
      done
      r=$(( r + 1 ))
    done
    b=$(( b + 1 ))
  done
  inv_draw_bunkers
  inv_draw_formation
}

inv_draw_bunkers() {
  local r c v
  printf '\e[%sm' "${SAV_SGR[1]}"
  r=$brow
  while [ "$r" -le $(( brow + 1 )) ]; do
    c=1
    while [ "$c" -le "$cols" ]; do
      v=${BK[$(( r * cols + c ))]:-0}
      if [ "$v" = 2 ]; then printf '\e[%d;%dH█' "$r" "$c"
      elif [ "$v" = 1 ]; then printf '\e[%d;%dH▒' "$r" "$c"; fi
      c=$(( c + 1 ))
    done
    r=$(( r + 1 ))
  done
  printf '\e[0m'
}

# inv_bk <col> <row> — chip a bunker cell if there is one there. Sets bk=1 if
# something was hit.
inv_bk() {
  local i=$(( $2 * cols + $1 )) v
  bk=0
  v=${BK[$i]:-0}
  [ "$v" = 0 ] && return 0
  bk=1
  v=$(( v - 1 ))
  BK[$i]=$v
  if [ "$v" -eq 1 ]; then frame="$frame\e[${SAV_SGR[0]}m\e[$2;$1H▒\e[0m"
  else frame="$frame\e[$2;$1H "; fi
}

# inv_draw_formation [erase-fx erase-fy] — every living alien at the current
# position, after blanking them at the previous one.
inv_draw_formation() {
  local r c t sty ex=${1:-} ey=${2:-}
  r=0
  while [ "$r" -lt "$nrow" ]; do
    t=2; [ "$r" -lt 3 ] && t=1; [ "$r" -lt 1 ] && t=0
    case $t in 0) sty=${SAV_SGR[3]} ;; 1) sty=${SAV_SGR[2]} ;; *) sty=${SAV_SGR[1]} ;; esac
    c=0
    while [ "$c" -lt "$ncol" ]; do
      if [ "${ALIVE[$(( r * ncol + c ))]}" = 1 ]; then
        [ -n "$ex" ] && frame="$frame\e[$(( ey + r * 2 ));$(( ex + c * 5 ))H   "
        frame="$frame\e[${sty}m\e[$(( fy + r * 2 ));$(( fx + c * 5 ))H${INV_SPR[$(( t * 2 + af ))]}\e[0m"
      fi
      c=$(( c + 1 ))
    done
    r=$(( r + 1 ))
  done
}

# inv_step — the formation moves one cell (or drops a row at an edge).
inv_step() {
  local r c cl=99 cr=-1 low=-1 ox=$fx oy=$fy
  c=0
  while [ "$c" -lt "$ncol" ]; do
    r=0
    while [ "$r" -lt "$nrow" ]; do
      if [ "${ALIVE[$(( r * ncol + c ))]}" = 1 ]; then
        [ "$c" -lt "$cl" ] && cl=$c
        [ "$c" -gt "$cr" ] && cr=$c
        [ "$r" -gt "$low" ] && low=$r
      fi
      r=$(( r + 1 ))
    done
    c=$(( c + 1 ))
  done
  if [ $(( fx + fd + cl * 5 )) -lt 1 ] || [ $(( fx + fd + cr * 5 + 2 )) -gt "$cols" ]; then
    fy=$(( fy + 1 )); fd=$(( -fd ))
  else
    fx=$(( fx + fd ))
  fi
  af=$(( 1 - af ))
  sav_sound "march$(( note % 4 ))"
  note=$(( note + 1 ))

  # Low enough to chew the bunkers: the whole row goes, erased BEFORE the
  # formation is drawn into it. Low enough to land is the end.
  r=$(( fy + low * 2 ))
  if [ "$r" -ge "$brow" ] && [ "$r" -le $(( brow + 1 )) ]; then
    c=1
    while [ "$c" -le "$cols" ]; do
      if [ "${BK[$(( r * cols + c ))]:-0}" != 0 ]; then
        BK[$(( r * cols + c ))]=0
        frame="$frame\e[${r};${c}H "
      fi
      c=$(( c + 1 ))
    done
  fi
  inv_draw_formation "$ox" "$oy"
  [ "$r" -ge $(( pr - 1 )) ] && inv_lose_all
}

inv_lose_all() {
  lives=0
  inv_gameover
}

inv_gameover() {
  sav_sound die
  [ "$score" -gt "$hi" ] && { hi=$score; sav_hiscore_save invasion "$score"; }
  over=110
}

inv_hud() {
  local s l lv="" i=0 hs
  while [ "$i" -lt "$lives" ]; do lv="${lv}▲ "; i=$(( i + 1 )); done
  hs=$hi; [ "$score" -gt "$hs" ] && hs=$score
  s=$(printf 'SCORE %05d' "$score")
  l=$(printf 'HI %05d   WAVE %d' "$hs" "$wave")
  frame="$frame\e[1;1H\e[2K\e[${SAV_SGR[1]}m $s\e[1;$(( (cols - ${#l}) / 2 + 1 ))H$l\e[1;$(( cols - 7 ))H$lv\e[0m"
}

# inv_hit_alien <col> <row> — is there a living alien under that cell? Sets
# kill to its index, or -1.
inv_hit_alien() {
  local dy=$(( $2 - fy )) dx=$(( $1 - fx )) r c
  kill=-1
  [ "$dy" -ge 0 ] && [ $(( dy % 2 )) -eq 0 ] && [ "$dx" -ge 0 ] || return 0
  r=$(( dy / 2 )); c=$(( dx / 5 ))
  [ "$r" -lt "$nrow" ] && [ "$c" -lt "$ncol" ] && [ $(( dx % 5 )) -lt 3 ] || return 0
  [ "${ALIVE[$(( r * ncol + c ))]}" = 1 ] && kill=$(( r * ncol + c ))
  return 0
}

saver_frame() {
  local i n r c x y t keep_x keep_y keep_t keep_w danger phit
  tick=$(( tick + 1 ))
  inv_hud

  if [ "$over" -gt 0 ]; then
    over=$(( over - 1 ))
    if [ "$over" -eq 0 ]; then inv_newgame; return; fi
    c=$(( (cols - 9) / 2 + 1 ))
    if [ $(( over / 8 % 2 )) -eq 0 ]; then
      frame="$frame\e[$(( rows / 2 ));${c}H\e[${SAV_SGR[3]}mGAME OVER\e[0m"
    else
      frame="$frame\e[$(( rows / 2 ));${c}H         "
    fi
    return
  fi

  # ── the formation ──
  stepc=$(( stepc + 1 ))
  if [ "$stepc" -ge $(( 2 + alive * 16 / total )) ]; then
    stepc=0
    inv_step
    [ "$over" -gt 0 ] && return
  fi

  # Explosions burn out.
  n=${#EXPT[@]}; i=0
  keep_x=(); keep_y=(); keep_t=(); keep_w=()
  while [ "$i" -lt "$n" ]; do
    if [ "${EXPT[$i]}" -le 1 ]; then
      frame="$frame\e[${EXPY[$i]};${EXPX[$i]}H${INV_BLANK:0:${EXPW[$i]}}"
    else
      keep_x+=("${EXPX[$i]}"); keep_y+=("${EXPY[$i]}")
      keep_t+=($(( ${EXPT[$i]} - 1 ))); keep_w+=("${EXPW[$i]}")
    fi
    i=$(( i + 1 ))
  done
  EXPX=("${keep_x[@]+"${keep_x[@]}"}"); EXPY=("${keep_y[@]+"${keep_y[@]}"}")
  EXPT=("${keep_t[@]+"${keep_t[@]}"}"); EXPW=("${keep_w[@]+"${keep_w[@]}"}")

  # ── the saucer ──
  if [ "$ufo" -eq 0 ] && [ "$tick" -gt 150 ] && [ $(( RANDOM % 500 )) -eq 0 ]; then
    ufo=1
    if [ $(( RANDOM % 2 )) -eq 0 ]; then ux=1; ud=1; else ux=$(( cols - 4 )); ud=-1; fi
  fi
  if [ "$ufo" -eq 1 ]; then
    frame="$frame\e[2;${ux}H     "
    ux=$(( ux + ud ))
    if [ "$ux" -lt 1 ] || [ "$ux" -gt $(( cols - 4 )) ]; then
      ufo=0
    else
      frame="$frame\e[${SAV_SGR[3]}m\e[2;${ux}H${INV_SAUCER}\e[0m"
      [ $(( tick % 8 )) -eq 0 ] && sav_sound saucer
    fi
  fi

  # ── bombs: dropped from the lowest alien of a random column ──
  if [ "${#BX[@]}" -lt $(( 2 + wave / 2 )) ] && [ $(( RANDOM % 100 )) -lt $(( 4 + wave )) ]; then
    c=$(( RANDOM % ncol )); r=$(( nrow - 1 ))
    while [ "$r" -ge 0 ] && [ "${ALIVE[$(( r * ncol + c ))]}" != 1 ]; do r=$(( r - 1 )); done
    if [ "$r" -ge 0 ]; then
      BX+=($(( fx + c * 5 + 1 ))); BY+=($(( fy + r * 2 + 1 )))
    fi
  fi
  if [ $(( tick % 2 )) -eq 0 ]; then
    n=${#BX[@]}; i=0
    keep_x=(); keep_y=(); phit=0
    while [ "$i" -lt "$n" ]; do
      x=${BX[$i]}; y=${BY[$i]}
      frame="$frame\e[${y};${x}H "
      y=$(( y + 1 ))
      inv_bk "$x" "$y"
      if [ "$bk" -eq 1 ] || [ "$y" -gt "$rows" ]; then
        :
      elif [ "$dead" -eq 0 ] && [ "$y" -eq "$pr" ] && [ "$x" -ge "$ppx" ] && [ "$x" -le $(( ppx + 2 )) ]; then
        phit=1
      else
        keep_x+=("$x"); keep_y+=("$y")
        frame="$frame\e[${SAV_SGR[2]}m\e[${y};${x}H╏\e[0m"
      fi
      i=$(( i + 1 ))
    done
    BX=("${keep_x[@]+"${keep_x[@]}"}"); BY=("${keep_y[@]+"${keep_y[@]}"}")
    [ "$phit" -eq 1 ] && inv_player_hit
  fi

  # ── the cannon ──
  oppx=$ppx
  if [ "$dead" -gt 0 ]; then
    dead=$(( dead - 1 ))
    if [ $(( dead % 4 )) -lt 2 ]; then frame="$frame\e[${SAV_SGR[3]}m\e[${pr};${ppx}H▓▒▓\e[0m"
    else frame="$frame\e[${SAV_SGR[0]}m\e[${pr};${ppx}H▒░▒\e[0m"; fi
    if [ "$dead" -eq 0 ]; then
      frame="$frame\e[${pr};${ppx}H   "
      if [ "$lives" -le 0 ]; then inv_gameover; return; fi
    fi
  else
    # Danger first: a bomb within two columns and closing.
    danger=0
    n=${#BX[@]}; i=0
    while [ "$i" -lt "$n" ]; do
      x=$(( BX[i] - ppx - 1 ))
      if [ "${BY[$i]}" -ge $(( pr - 7 )) ] && [ "$x" -ge -2 ] && [ "$x" -le 2 ]; then
        if [ "$x" -le 0 ]; then danger=1; else danger=-1; fi
        [ "$ppx" -le 2 ] && danger=1
        [ "$ppx" -ge $(( cols - 3 )) ] && danger=-1
        break
      fi
      i=$(( i + 1 ))
    done
    if [ "$danger" -ne 0 ]; then
      ppx=$(( ppx + danger ))
    else
      if [ "$ufo" -eq 1 ]; then
        tx=$(( ux + 2 + ud * 4 - 1 ))
      elif [ $(( tick % 40 )) -eq 0 ] || [ "$tx" -eq "$ppx" -a "$shot" -eq 1 ]; then
        # A fresh target: the centre of a living column.
        c=$(( RANDOM % ncol )); i=0
        while [ "$i" -lt "$ncol" ]; do
          r=0
          while [ "$r" -lt "$nrow" ] && [ "${ALIVE[$(( r * ncol + c ))]}" != 1 ]; do r=$(( r + 1 )); done
          [ "$r" -lt "$nrow" ] && break
          c=$(( (c + 1) % ncol )); i=$(( i + 1 ))
        done
        tx=$(( fx + c * 5 + fd ))
      fi
      if [ "$ppx" -lt "$tx" ]; then ppx=$(( ppx + 1 )); elif [ "$ppx" -gt "$tx" ]; then ppx=$(( ppx - 1 )); fi
    fi
    [ "$ppx" -lt 1 ] && ppx=1
    [ "$ppx" -gt $(( cols - 2 )) ] && ppx=$(( cols - 2 ))
    frame="$frame\e[${pr};${oppx}H   \e[${SAV_SGR[1]}m\e[${pr};${ppx}H${INV_GUN}\e[0m"

    # Fire when lined up under something worth hitting.
    if [ "$shot" -eq 0 ]; then
      x=$(( ppx + 1 ))
      c=$(( x - fx ))
      if { [ "$c" -ge 0 ] && [ $(( c % 5 )) -lt 3 ] && [ $(( c / 5 )) -lt "$ncol" ]; } \
         || { [ "$ufo" -eq 1 ] && [ $(( x - ux )) -ge -3 ] && [ $(( x - ux )) -le 7 ]; }; then
        shot=1; sx=$x; sy=$(( pr - 1 ))
        sav_sound shoot
      fi
    fi
  fi

  # ── the shot: two rows a frame, checked one row at a time ──
  if [ "$shot" -eq 1 ]; then
    frame="$frame\e[${sy};${sx}H "
    for i in 1 2; do
      sy=$(( sy - 1 ))
      if [ "$sy" -lt 2 ]; then shot=0; break; fi
      inv_bk "$sx" "$sy"
      if [ "$bk" -eq 1 ]; then shot=0; break; fi
      if [ "$ufo" -eq 1 ] && [ "$sy" -eq 2 ] && [ "$sx" -ge "$ux" ] && [ "$sx" -le $(( ux + 4 )) ]; then
        n=$(( (RANDOM % 6 + 1) * 50 ))
        score=$(( score + n ))
        frame="$frame\e[2;${ux}H\e[${SAV_SGR[3]}m $n \e[0m"
        EXPX+=("$ux"); EXPY+=(2); EXPT+=(25); EXPW+=(5)
        ufo=0; shot=0
        sav_sound bonus
        break
      fi
      inv_hit_alien "$sx" "$sy"
      if [ "$kill" -ge 0 ]; then
        ALIVE[$kill]=0
        alive=$(( alive - 1 ))
        r=$(( kill / ncol )); c=$(( kill % ncol ))
        t=10; [ "$r" -lt 3 ] && t=20; [ "$r" -lt 1 ] && t=30
        score=$(( score + t ))
        x=$(( fx + c * 5 )); y=$(( fy + r * 2 ))
        frame="$frame\e[${SAV_SGR[3]}m\e[${y};${x}H${INV_BOOM}\e[0m"
        EXPX+=("$x"); EXPY+=("$y"); EXPT+=(5); EXPW+=(3)
        shot=0
        sav_sound hit
        break
      fi
    done
    [ "$shot" -eq 1 ] && frame="$frame\e[${SAV_SGR[3]}m\e[${sy};${sx}H│\e[0m"
  fi

  if [ "$alive" -le 0 ]; then
    sav_sound level
    [ "$score" -gt "$hi" ] && { hi=$score; sav_hiscore_save invasion "$score"; }
    inv_wave
  fi
}

inv_player_hit() {
  lives=$(( lives - 1 ))
  dead=36
  sav_sound boom
  # Clear the air so the respawn isn't straight into the next bomb.
  local i=0 n=${#BX[@]}
  while [ "$i" -lt "$n" ]; do frame="$frame\e[${BY[$i]};${BX[$i]}H "; i=$(( i + 1 )); done
  BX=(); BY=()
}
