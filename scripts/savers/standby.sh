# savers/standby.sh — the status screen: what the grid knew when you walked away.
#
# Sourced by grid-saver.sh, which has already set rows, cols, accent and sess.
#
# Every other saver hides the dashboard. This one enlarges it: a block clock,
# the rollup counts at size, and every pane with its state and how long it has
# been in it — readable from across the room, without touching a key. It is
# also what the blocked-pane gate in grid-saver.sh falls back to, so an idle
# grid with a pane sitting on ▲ ends up showing that pane bigger rather than
# painting over it.
#
# Panes are ordered the way prefix+n walks them: blocked first, then finished,
# then working, then idle. The glyphs and colours are the same language as the
# pane borders and the status bar — ▲ is red in all three places.
#
# ── Two modes ────────────────────────────────────────────────────────────────
# Alone, this owns the screen: it drifts a few cells a minute (a static block
# of bright glyphs on a terminal that may sit untouched for hours is exactly
# what burn-in is) and clears to end-of-line as it goes.
#
# Under a backdrop — @grid_saver_backdrop — it becomes a panel floating on the
# effect, and three things change. It stops drifting, because the moving rain
# behind it is already the burn-in defence and a panel that wanders would leave
# residue the backdrop is under orders not to repaint. It stops clearing to
# end-of-line and to end-of-screen, because both would carve black rectangles
# out of the backdrop. And it publishes its own bounds as the host's keep-out
# rectangle, so the backdrop skips those cells entirely and the panel only has
# to redraw when its content changes rather than once per backdrop frame.
#
# Every name here is SB_- or sb_-prefixed, down to the loop counters, for one
# blunt reason: in a composite this file and the backdrop are sourced into the
# SAME shell, so the invariant is that they share NO globals at all.
#
# It is not a hypothetical. bounce.sh defines its own BIG array of logo art.
# starfield kept star radii in r[] while the clock loop below walked a scalar
# r, which assigns element zero and teleports one star a second. pipes counted
# its pipes in np while this file counts PANES in np. None of those three fail
# loudly — they render *slightly* wrong, occasionally, in a screensaver nobody
# is watching closely. A whitelist of "benign" shared counters would have to be
# re-reasoned on every edit; no overlap at all is a property that can just be
# checked.

# 4 columns wide, 5 rows tall, indexed digit*5 + row. Widths are hardcoded
# below rather than measured: █ is three bytes, and ${#s} counts bytes rather
# than columns unless the locale cooperates, which under a lock-command is not
# a thing worth betting the layout on.
SB_BIG=(
'████' '█  █' '█  █' '█  █' '████'
'   █' '   █' '   █' '   █' '   █'
'████' '   █' '████' '█   ' '████'
'████' '   █' '████' '   █' '████'
'█  █' '█  █' '████' '   █' '   █'
'████' '█   ' '████' '   █' '████'
'████' '█   ' '████' '█  █' '████'
'████' '   █' '   █' '   █' '   █'
'████' '█  █' '████' '█  █' '████'
'████' '█  █' '████' '   █' '████'
)
SB_COLON=('  ' '██' '  ' '██' '  ')
SB_CLOCK_W=22      # 4+1 +4+1 +2+1 +4+1 +4
SB_LEDGER_W=58     # glyph + repo 22 + state 8 + elapsed 5 + context meter 10 + %
SB_PAD=2           # quiet cells between the content and the weather

# ── the renderer ─────────────────────────────────────────────────────────────
# Appends one full panel to $frame. sb_comp decides which of the two modes
# above applies; everything else is shared, because the layout arithmetic is
# the part worth having exactly one copy of.
sb_build() {
  # One date call, not four: this runs every second for as long as the
  # terminal stays locked.
  set -- $(date '+%s %H:%M %a %d %b')
  now=$1 hm=$2 dow=$3 dd=$4 mon=$5

  # ── the panes, attention order ──
  rep=() sta=() sin=() ctx=()
  np=0 n_block=0 n_work=0 n_done=0
  while IFS='|' read -r a b c d; do
    [ -n "$a" ] || continue
    rep[$np]=$a sta[$np]=$b sin[$np]=$c ctx[$np]=$d
    case "$b" in
      waiting) n_block=$(( n_block + 1 )) ;;
      working) n_work=$(( n_work + 1 )) ;;
      'done')  n_done=$(( n_done + 1 )) ;;
    esac
    np=$(( np + 1 ))
  done <<EOF
$(tmux list-panes -t "$sess" -F '#{@repo}|#{@state}|#{@state_since}|#{@cl_ctx}' 2>/dev/null \
  | awk -F'|' '$1 != "" {
      o = ($2 == "waiting") ? 0 : ($2 == "done") ? 1 : ($2 == "working") ? 2 : 3
      print o "|" $0
    }' | sort -t'|' -k1,1n | cut -d'|' -f2-)
EOF

  # ── geometry ──
  # 5 clock rows, blank, date, blank, rollup, blank, then the ledger.
  #
  # How many panes are LISTED depends on the terminal, not a fixed number: a
  # tall terminal should show all of them, and a short one has to stop
  # somewhere and say so rather than pretending the grid ends there. Every
  # pane is still READ — the rollup counts above must describe the whole
  # session, not just the part that fits.
  shown=$np
  maxrows=$(( rows - 12 )); [ "$maxrows" -lt 1 ] && maxrows=1
  [ "$shown" -gt "$maxrows" ] && shown=$maxrows
  overflow=$(( np - shown ))

  block_h=$(( 10 + shown ))
  [ "$overflow" -gt 0 ] && block_h=$(( block_h + 1 ))
  if [ "$sb_comp" -eq 1 ]; then
    ox=0 oy=0
  else
    ox=$(( (now / 60) % 7 - 3 ))
    oy=$(( (now / 120) % 5 - 2 ))
  fi
  top=$(( (rows - block_h) / 2 + oy ))
  [ "$top" -lt 1 ] && top=1

  cl=$(( (cols - SB_CLOCK_W) / 2 + 1 + ox ))
  [ "$cl" -lt 1 ] && cl=1
  lc=$(( (cols - SB_LEDGER_W) / 2 + 1 + ox ))
  [ "$lc" -lt 1 ] && lc=1

  if [ "$sb_comp" -eq 1 ]; then
    sb_composite_wipe
  else
    # Only wipe when the block MOVES. Every line below clears to end-of-line
    # and the last one clears to end-of-screen, so a redraw in place needs no
    # wipe — and wiping every second is a visible flicker at this rate.
    if [ "$ox" -ne "$sb_last_ox" ] || [ "$oy" -ne "$sb_last_oy" ] || [ "$np" -ne "$sb_last_np" ]; then
      frame="$frame\e[2J"
      sb_last_ox=$ox sb_last_oy=$oy sb_last_np=$np
    fi
  fi

  # ── clock ──
  for (( sb_i = 0; sb_i < 5; sb_i++ )); do
    line=''
    for (( sb_j = 0; sb_j < 5; sb_j++ )); do
      ch=${hm:$sb_j:1}
      if [ "$ch" = ':' ]; then
        # The colon blinks, the way every digital clock has always blinked.
        if [ $(( now % 2 )) -eq 0 ]; then line="$line${SB_COLON[$sb_i]}"; else line="$line  "; fi
      else
        line="$line${SB_BIG[$(( ch * 5 + sb_i ))]}"
      fi
      [ "$sb_j" -lt 4 ] && line="$line "
    done
    frame="$frame\e[$(( top + sb_i ));${cl}H\e[1;38;5;${accent}m${line}\e[0m${sb_eol}"
  done

  # ── date · session ──
  sub="$dow $dd $mon · ${sess:-grid}"
  sc=$(( (cols - ${#sub}) / 2 + 1 + ox ))
  [ "$sc" -lt 1 ] && sc=1
  frame="$frame\e[$(( top + 6 ));${sc}H\e[2;38;5;${accent}m${sub}\e[0m${sb_eol}"

  # ── rollup ──
  # Built with a parallel width counter: the string carries colour escapes,
  # so ${#rtxt} would measure the escapes too and throw the centring off by
  # thirty-odd columns.
  # Each width below counts the glyph, a space, the digits, the word, and the
  # three-space gap that follows — the gap on the last segment is taken back
  # once, after the chain.
  rtxt='' rw=0
  if [ "$n_block" -gt 0 ]; then
    rtxt="$rtxt\e[1;38;5;203m▲ $n_block blocked\e[0m   "
    rw=$(( rw + 13 + ${#n_block} ))
  fi
  if [ "$n_done" -gt 0 ]; then
    rtxt="$rtxt\e[38;5;114m✔ $n_done done\e[0m   "
    rw=$(( rw + 10 + ${#n_done} ))
  fi
  if [ "$n_work" -gt 0 ]; then
    rtxt="$rtxt\e[38;5;81m▶ $n_work working\e[0m   "
    rw=$(( rw + 13 + ${#n_work} ))
  fi
  if [ "$rw" -eq 0 ]; then
    rtxt="\e[2;38;5;${accent}mall quiet\e[0m"
    rw=9
  else
    rw=$(( rw - 3 ))
  fi
  rc=$(( (cols - rw) / 2 + 1 + ox ))
  [ "$rc" -lt 1 ] && rc=1
  frame="$frame\e[$(( top + 8 ));${rc}H${rtxt}${sb_eol}"

  # ── ledger ──
  for (( sb_i = 0; sb_i < shown; sb_i++ )); do
    case "${sta[$sb_i]}" in
      waiting) gl='▲' co=203 lbl='blocked' ;;
      working) gl='▶' co=81  lbl='working' ;;
      'done')  gl='✔' co=114 lbl='done' ;;
      *)       gl='·' co=240 lbl='idle' ;;
    esac
    s=$(( now - ${sin[$sb_i]:-$now} ))
    [ "$s" -lt 0 ] && s=0
    if [ "$s" -lt 60 ]; then
      el="${s}s"
    elif [ "$s" -lt 3600 ]; then
      el="$(( s / 60 ))m"
    else
      mm=$(( (s % 3600) / 60 ))
      [ "$mm" -lt 10 ] && mm="0$mm"
      el="$(( s / 3600 ))h$mm"
    fi
    # printf -v, not $(printf ...): a fork per pane per second, for as long
    # as the lock holds, for a string.
    printf -v line '%-22.22s  %-8s %5s' "${rep[$sb_i]}" "$lbl" "$el"

    # Context pressure, as a meter rather than a number. @cl_ctx is percent
    # REMAINING — the title bar blinks amber at <=15 — so the bar EMPTIES as
    # a pane fills up, and its colour is a warning rather than a reading.
    # A pane about to compact is then visible from the doorway, which a
    # two-digit number never was.
    meter=''
    case "${ctx[$sb_i]}" in
      (''|*[!0-9]*) ;;
      (*)
        v=${ctx[$sb_i]}
        fill=$(( (v + 5) / 10 )); [ "$fill" -gt 10 ] && fill=10
        if   [ "$v" -gt 50 ]; then mc=114
        elif [ "$v" -gt 15 ]; then mc=214
        else                       mc=203
        fi
        bar=''
        q=0
        while [ "$q" -lt 10 ]; do
          # Braced on purpose: "$bar█" makes bash read the block glyph as
          # part of the variable name, which under set -u is a fatal unbound
          # variable rather than a concatenation.
          if [ "$q" -lt "$fill" ]; then bar="${bar}█"; else bar="${bar}░"; fi
          q=$(( q + 1 ))
        done
        printf -v pct '%3d%%' "$v"
        meter="\e[38;5;${mc}m${bar}\e[0m\e[2m ${pct}\e[0m"
        ;;
    esac
    frame="$frame\e[$(( top + 10 + sb_i ));${lc}H\e[1;38;5;${co}m${gl}\e[0m \e[38;5;250m${line}\e[0m  ${meter}${sb_eol}"
  done

  # Say what was left out, rather than letting the list just stop.
  tail_row=$(( top + 10 + shown ))
  if [ "$overflow" -gt 0 ]; then
    printf -v more '… and %d more' "$overflow"
    frame="$frame\e[${tail_row};$(( lc + 2 ))H\e[2;38;5;${accent}m${more}\e[0m${sb_eol}"
    tail_row=$(( tail_row + 1 ))
  fi
  # Anything left below the ledger from a longer previous frame. The composite
  # has already wiped its whole rectangle and must not touch anything outside
  # it, so this is the solo mode's job only.
  [ "$sb_comp" -eq 0 ] && frame="$frame\e[${tail_row};1H\e[J"
}

# ── composite plumbing ───────────────────────────────────────────────────────
# Wipe the panel's rectangle and publish it as the host's keep-out. Wiping the
# whole rectangle every refresh rather than tracking which rows shrank is a
# deliberate trade: it is about 1.2KB once a second, it is correct by
# construction when a pane appears or disappears mid-lock, and it removes the
# entire class of bug where a stale ledger row survives under the new one.
sb_composite_wipe() {
  local w l t b r wt wb wl wr ww

  w=$(( SB_LEDGER_W + SB_PAD * 2 ))
  [ "$w" -gt "$cols" ] && w=$cols
  l=$(( lc - SB_PAD ))
  [ "$l" -lt 1 ] && l=1
  [ $(( l + w - 1 )) -gt "$cols" ] && l=$(( cols - w + 1 ))
  [ "$l" -lt 1 ] && l=1

  t=$(( top - 1 )); [ "$t" -lt 1 ] && t=1
  b=$(( top + block_h )); [ "$b" -gt "$rows" ] && b=$rows

  # Wipe the UNION of where the panel was and where it now is, not just where
  # it now is. A pane finishing mid-lock shrinks the ledger and re-centres the
  # whole block, and the rows the panel vacates are rows the backdrop has been
  # under orders not to repaint — so nothing else will ever clean them. They
  # sat there as a half-scrubbed ledger with rain falling through it.
  #
  # Normally the union is the new rectangle and this costs nothing.
  wt=$t wb=$b wl=$l wr=$(( l + w - 1 ))
  if [ "${sb_prev_b:-0}" -ge "${sb_prev_t:-1}" ]; then
    [ "$sb_prev_t" -lt "$wt" ] && wt=$sb_prev_t
    [ "$sb_prev_b" -gt "$wb" ] && wb=$sb_prev_b
    [ "$sb_prev_l" -lt "$wl" ] && wl=$sb_prev_l
    [ "$sb_prev_r" -gt "$wr" ] && wr=$sb_prev_r
  fi
  ww=$(( wr - wl + 1 ))

  # One row of spaces, rebuilt only when the width changes.
  if [ "${sb_blank_w:-0}" -ne "$ww" ]; then
    printf -v sb_blank '%*s' "$ww" ''
    sb_blank_w=$ww
  fi

  for (( r = wt; r <= wb; r++ )); do
    frame="$frame\e[${r};${wl}H\e[0m${sb_blank}"
  done

  sb_prev_t=$t sb_prev_b=$b sb_prev_l=$l sb_prev_r=$(( l + w - 1 ))
  KEEP_T=$t KEEP_B=$b KEEP_L=$l KEEP_R=$(( l + w - 1 ))
}

sb_overlay_begin() {
  sb_comp=1
  sb_eol=''
  sb_blank_w=0
  sb_blank=''
  # No previous rectangle yet: prev_b below prev_t is the "unset" that
  # sb_composite_wipe tests for.
  sb_prev_t=1 sb_prev_b=0 sb_prev_l=1 sb_prev_r=0
}

sb_overlay_frame() { sb_build; }

# Called by a backdrop that has just cleared the whole screen (snow's thaw,
# pipes' saturation reset). It renders into the SAME frame string the backdrop
# is mid-way through building, so the panel comes back in the same write that
# wiped it rather than a second later.
sb_overlay_dirty() { sb_build; }

# ── solo ─────────────────────────────────────────────────────────────────────
animate() {
  sb_comp=0
  sb_eol='\e[K'
  sb_last_ox=999
  sb_last_oy=999
  sb_last_np=-1
  while :; do
    frame=''
    sb_build
    printf '%b' "$frame"
    sleep 1
  done
}
