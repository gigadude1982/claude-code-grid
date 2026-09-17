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
# The whole block drifts a few cells every minute. It's a screensaver running
# on a terminal that may sit untouched for hours, and a static block of bright
# glyphs is exactly what burn-in is.

# 4 columns wide, 5 rows tall, indexed digit*5 + row. Widths are hardcoded
# below rather than measured: █ is three bytes, and ${#s} counts bytes rather
# than columns unless the locale cooperates, which under a lock-command is not
# a thing worth betting the layout on.
BIG=(
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
COLON=('  ' '██' '  ' '██' '  ')
CLOCK_W=22      # 4+1 +4+1 +2+1 +4+1 +4
LEDGER_W=58     # glyph + repo 22 + state 8 + elapsed 5 + context meter 10 + %

animate() {
  last_ox=999
  last_oy=999
  last_np=-1

  while :; do
    # One date call, not four: this loop runs every second for as long as the
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
    ox=$(( (now / 60) % 7 - 3 ))
    oy=$(( (now / 120) % 5 - 2 ))
    top=$(( (rows - block_h) / 2 + oy ))
    [ "$top" -lt 1 ] && top=1

    frame=''
    # Only wipe when the block MOVES. Every line below clears to end-of-line
    # and the last one clears to end-of-screen, so a redraw in place needs no
    # wipe — and wiping every second is a visible flicker at this rate.
    if [ "$ox" -ne "$last_ox" ] || [ "$oy" -ne "$last_oy" ] || [ "$np" -ne "$last_np" ]; then
      frame='\e[2J'
      last_ox=$ox last_oy=$oy last_np=$np
    fi

    # ── clock ──
    cl=$(( (cols - CLOCK_W) / 2 + 1 + ox ))
    [ "$cl" -lt 1 ] && cl=1
    for (( r = 0; r < 5; r++ )); do
      line=''
      for (( i = 0; i < 5; i++ )); do
        ch=${hm:$i:1}
        if [ "$ch" = ':' ]; then
          # The colon blinks, the way every digital clock has always blinked.
          if [ $(( now % 2 )) -eq 0 ]; then line="$line${COLON[$r]}"; else line="$line  "; fi
        else
          line="$line${BIG[$(( ch * 5 + r ))]}"
        fi
        [ "$i" -lt 4 ] && line="$line "
      done
      frame="$frame\e[$(( top + r ));${cl}H\e[1;38;5;${accent}m${line}\e[0m\e[K"
    done

    # ── date · session ──
    sub="$dow $dd $mon · ${sess:-grid}"
    sc=$(( (cols - ${#sub}) / 2 + 1 + ox ))
    [ "$sc" -lt 1 ] && sc=1
    frame="$frame\e[$(( top + 6 ));${sc}H\e[2;38;5;${accent}m${sub}\e[0m\e[K"

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
    frame="$frame\e[$(( top + 8 ));${rc}H${rtxt}\e[K"

    # ── ledger ──
    lc=$(( (cols - LEDGER_W) / 2 + 1 + ox ))
    [ "$lc" -lt 1 ] && lc=1
    for (( i = 0; i < shown; i++ )); do
      case "${sta[$i]}" in
        waiting) gl='▲' co=203 lbl='blocked' ;;
        working) gl='▶' co=81  lbl='working' ;;
        'done')  gl='✔' co=114 lbl='done' ;;
        *)       gl='·' co=240 lbl='idle' ;;
      esac
      s=$(( now - ${sin[$i]:-$now} ))
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
      printf -v line '%-22.22s  %-8s %5s' "${rep[$i]}" "$lbl" "$el"

      # Context pressure, as a meter rather than a number. @cl_ctx is percent
      # REMAINING — the title bar blinks amber at <=15 — so the bar EMPTIES as
      # a pane fills up, and its colour is a warning rather than a reading.
      # A pane about to compact is then visible from the doorway, which a
      # two-digit number never was.
      meter=''
      case "${ctx[$i]}" in
        (''|*[!0-9]*) ;;
        (*)
          v=${ctx[$i]}
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
      frame="$frame\e[$(( top + 10 + i ));${lc}H\e[1;38;5;${co}m${gl}\e[0m \e[38;5;250m${line}\e[0m  ${meter}\e[K"
    done
    # Anything left below the ledger from a longer previous frame.
    # Say what was left out, rather than letting the list just stop.
    tail_row=$(( top + 10 + shown ))
    if [ "$overflow" -gt 0 ]; then
      printf -v more '… and %d more' "$overflow"
      frame="$frame\e[${tail_row};$(( lc + 2 ))H\e[2;38;5;${accent}m${more}\e[0m\e[K"
      tail_row=$(( tail_row + 1 ))
    fi
    frame="$frame\e[${tail_row};1H\e[J"

    printf '%b' "$frame"
    sleep 1
  done
}
