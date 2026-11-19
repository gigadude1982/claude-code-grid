# savers/serpent.sh — a snake that plays itself: it heads for the food, grows
# when it eats, and sooner or later ties itself in a knot it can't get out of.
# Then it flashes, plays its little dirge, and starts again. The longest it has
# ever got is kept on disk.
#
# Sourced by grid-saver.sh (rows, cols, accent, SAV_SGR, sav_sound,
# sav_hiscore). Composable in form, so @grid_saver_opacity applies; not a
# backdrop.
#
# A cell is two columns wide — a terminal cell is about twice as tall as it is
# wide, so a 2x1 cell is close to square and the snake turns corners rather
# than smearing sideways.
#
# The brain is greedy with one look ahead: of the three ways it can go, it
# takes the one nearest the food, but never into a cell with no way out, and
# reluctantly into a cell with only one. That's enough to survive a long time
# and not enough to survive forever, which is the point — the dying is half
# the show. A real path search would be immortal, and in bash, slow.
#
# The body lives in two arrays indexed by a counter that only ever grows; the
# tail is head - len + 1, and cells leaving the tail are unset. No modular
# arithmetic, no shifting arrays, O(1) per step.

SAVER_DELAY=0.05

SP_DX=(0 1 0 -1)
SP_DY=(-1 0 1 0)

saver_begin() {
  gw=$(( cols / 2 ))
  gh=$(( rows - 1 ))
  ox=$(( (cols - gw * 2) / 2 + 1 ))
  sav_sgr_idx 203; SP_FOOD=$SAV_OUT
  best=$(sav_hiscore serpent)
  frame=''
  sp_new
  printf '%b' "$frame"
  sav_sound start
}

sp_new() {
  local i
  printf '\e[2J'
  OCC=()
  SX=(); SY=()
  hk=0
  len=1
  grow=4
  dir=1
  eaten=0
  dying=0
  SX[0]=$(( gw / 4 )); SY[0]=$(( gh / 2 ))
  OCC[$(( SY[0] * gw + SX[0] ))]=1
  sp_food
}

# sp_cell <x> <y> — the screen position of a cell, into scr.
sp_cell() { scr="\e[$(( $2 + 2 ));$(( ox + $1 * 2 ))H"; }

sp_food() {
  local tries=0
  while [ "$tries" -lt 200 ]; do
    fx=$(( RANDOM % gw )); fy=$(( RANDOM % gh ))
    [ "${OCC[$(( fy * gw + fx ))]:-0}" = 0 ] && break
    tries=$(( tries + 1 ))
  done
  sp_cell "$fx" "$fy"
  frame="$frame$scr\e[${SP_FOOD}m▐▌\e[0m"
}

# sp_free <x> <y> — 1 if a cell is inside and empty.
sp_free() {
  [ "$1" -ge 0 ] && [ "$1" -lt "$gw" ] && [ "$2" -ge 0 ] && [ "$2" -lt "$gh" ] \
    && [ "${OCC[$(( $2 * gw + $1 ))]:-0}" = 0 ]
}

sp_hud() {
  local s b=$best
  [ "$len" -gt "$b" ] && b=$len
  s=$(printf 'LENGTH %3d   BEST %3d   EATEN %3d' "$len" "$b" "$eaten")
  frame="$frame\e[1;$(( (cols - ${#s}) / 2 + 1 ))H\e[${SAV_SGR[1]}m$s\e[0m"
}

saver_frame() {
  local d nd nx ny hx hy cost bestc k free n tx ty sty
  sp_hud

  if [ "$dying" -gt 0 ]; then
    dying=$(( dying - 1 ))
    if [ "$dying" -eq 0 ]; then sp_new; return; fi
    # Flash the whole body, tail to head.
    if [ $(( dying / 5 % 2 )) -eq 0 ]; then sty=${SAV_SGR[3]}; else sty=${SAV_SGR[0]}; fi
    [ $(( dying % 5 )) -eq 0 ] || return
    frame="$frame\e[${sty}m"
    k=$(( hk - len + 1 ))
    while [ "$k" -le "$hk" ]; do
      sp_cell "${SX[$k]}" "${SY[$k]}"
      frame="$frame${scr}██"
      k=$(( k + 1 ))
    done
    frame="$frame\e[0m"
    return
  fi

  hx=${SX[$hk]}; hy=${SY[$hk]}

  # Pick a way: nearest the food, not into a dead end, a slight preference for
  # going straight so it doesn't wiggle on the diagonal.
  nd=-1; bestc=99999
  for d in 0 1 2 3; do
    [ "$d" -eq $(( (dir + 2) % 4 )) ] && continue
    nx=$(( hx + SP_DX[d] )); ny=$(( hy + SP_DY[d] ))
    sp_free "$nx" "$ny" || continue
    cost=$(( (nx > fx ? nx - fx : fx - nx) + (ny > fy ? ny - fy : fy - ny) ))
    free=0
    for n in 0 1 2 3; do
      sp_free $(( nx + SP_DX[n] )) $(( ny + SP_DY[n] )) && free=$(( free + 1 ))
    done
    # A cell is "free" here even if the head is about to leave it; the head
    # itself is occupied, so this counts real exits.
    if [ "$free" -eq 0 ] && ! { [ "$nx" -eq "$fx" ] && [ "$ny" -eq "$fy" ]; }; then
      cost=$(( cost + 1000 ))
    elif [ "$free" -eq 1 ]; then
      cost=$(( cost + 6 ))
    fi
    [ "$d" -ne "$dir" ] && cost=$(( cost + 1 ))
    if [ "$cost" -lt "$bestc" ]; then bestc=$cost; nd=$d; fi
  done

  if [ "$nd" -lt 0 ]; then
    sav_sound die
    [ "$len" -gt "$best" ] && { best=$len; sav_hiscore_save serpent "$len"; }
    dying=60
    return
  fi
  dir=$nd
  nx=$(( hx + SP_DX[dir] )); ny=$(( hy + SP_DY[dir] ))

  # The old head becomes body, striped so the motion reads along its length.
  if [ $(( hk / 2 % 2 )) -eq 0 ]; then sty=${SAV_SGR[1]}; else sty=${SAV_SGR[2]}; fi
  sp_cell "$hx" "$hy"
  frame="$frame$scr\e[${sty}m██"

  hk=$(( hk + 1 ))
  SX[$hk]=$nx; SY[$hk]=$ny
  OCC[$(( ny * gw + nx ))]=1
  sp_cell "$nx" "$ny"
  frame="$frame$scr\e[${SAV_SGR[3]}m██\e[0m"

  if [ "$grow" -gt 0 ]; then
    grow=$(( grow - 1 ))
    len=$(( len + 1 ))
  else
    k=$(( hk - len ))
    tx=${SX[$k]}; ty=${SY[$k]}
    unset "SX[$k]" "SY[$k]"
    unset "OCC[$(( ty * gw + tx ))]"
    sp_cell "$tx" "$ty"
    frame="$frame$scr  "
  fi

  if [ "$nx" -eq "$fx" ] && [ "$ny" -eq "$fy" ]; then
    eaten=$(( eaten + 1 ))
    grow=$(( grow + 3 ))
    if [ $(( eaten % 10 )) -eq 0 ]; then sav_sound level; else sav_sound chomp; fi
    sp_food
  fi
}
