#!/bin/bash
# grid-saver.sh — the grid's screensaver host (tmux's lock-command).
#
# lock-after-time runs this against each client after the idle threshold, and
# tmux unlocks the client when it exits — so the contract is "animate until any
# key". bash 3.2's read -t can't do sub-second timeouts, so the animation runs
# as a background job while the foreground blocks on a single read; the EXIT
# trap reaps it either way.
#
# This file owns everything the effects shouldn't have to know: which session
# this client is looking at, that session's accent, the real terminal size, the
# alternate screen, mouse reporting, and the wake. It then sources
# scripts/savers/<name>.sh and calls the animate() that file defines. Adding a
# screensaver means adding a file there and a word to GRID_SAVERS — nothing in
# here changes.
#
# Which effect runs, in order: the blocked-pane gate (below), then @grid_saver
# on the session, then $GRID_CONFIG/saver.<session>, then the global
# @grid_saver, then matrix. Per-session because themes are per-session — the
# matrix grid can rain while the ocean grid runs starfield — and the file is
# what carries that choice across a tmux server restart, since options don't.
#
# Also runnable on demand, on one client only: the ☔ chip, C-\, or
# "screensaver" in the right-click pane menu (`tmux lock-client`);
# `tmux lock-server` still takes every terminal.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/grid-lib.sh"

# Rain in the accent of THIS terminal's session — themes are per-session,
# and the lock runs once per client. Our tty names the client: stdin is the
# client's terminal in the lock context.
#
# The session is read off `session_attached_list`, NOT `list-clients`.
# Locking a client sets its suspended flag, and list-clients hides
# suspended clients — so the tty match that used to live here could never
# fire from inside the lock command. It fell through every time to the
# untargeted `display-message`, which answers with the server's *current*
# session: whichever terminal you were last typing in when the idle one
# locked. That is the colour crossing terminals. session_attached_list
# applies no such filter and still names us. (`display-message -c` is no
# help either: -c steers #{client_*} only, and #{@theme_accent} resolves
# against the current session regardless.)
#
# `tty` runs BEFORE the pipeline, deliberately. Expanding it inside the
# awk argument puts the command substitution in the pipeline's second
# element, whose stdin is the pipe — `tty` answers "not a tty" there and
# the match never fires.
#
# Fallbacks, for when there is no tty or no such format (tmux < 3.1): the
# current session, then the global option — which on a themed grid only
# holds the conf's default and rains a colour no chip on screen is wearing.
mytty=$(tty 2>/dev/null)
case "$mytty" in (/dev/*) ;; (*) mytty='' ;; esac
sess=''
[ -n "$mytty" ] && sess=$(tmux list-sessions -F '#{session_name} #{session_attached_list}' 2>/dev/null \
  | awk -v t="$mytty" '{ n = split($2, a, ","); for (i = 1; i <= n; i++) if (a[i] == t) { print $1; exit } }')
[ -n "$sess" ] || sess=$(tmux display-message -p '#{session_name}' 2>/dev/null)
accent=''
[ -n "$sess" ] && accent=$(tmux show-options -v -t "$sess" @theme_accent 2>/dev/null)
[ -n "$accent" ] || accent=$(tmux show-options -gv @theme_accent 2>/dev/null)
accent=${accent#colour}
case "$accent" in (*[!0-9]*|'') accent=46 ;; esac

# The ground the effects fade toward. Same resolution order as the accent, and
# the same reason: @theme_bg is per session, so a dimmed matrix over the ocean
# grid fades into navy while the nosferatu grid fades into black. Falling back
# to 16 (true black) rather than "default" is deliberate — the blend needs a
# number to do arithmetic on, and no terminal's default background is far from
# one of the two extremes.
bg=''
[ -n "$sess" ] && bg=$(tmux show-options -v -t "$sess" @theme_bg 2>/dev/null)
[ -n "$bg" ] || bg=$(tmux show-options -gv @theme_bg 2>/dev/null)
bg=${bg#colour}
case "$bg" in (*[!0-9]*|'') bg=16 ;; esac

# Size from the tty on stdin — tput can't reach the client's tty in the
# lock-command context and quietly reports 80x24, which painted the rain
# into the screen's first quadrant. stty asks the fd the keys arrive on.
# The tmux fallback is last-ditch and unavoidably untargeted — it reports
# the *current* client, which on a multi-terminal grid may not be us.
size=$(stty size 2>/dev/null)
rows=${size%% *}
cols=${size##* }
if ! [ "$rows" -gt 0 ] 2>/dev/null || ! [ "$cols" -gt 0 ] 2>/dev/null; then
  size=$(tmux display-message -p '#{client_height} #{client_width}' 2>/dev/null)
  rows=${size%% *}
  cols=${size##* }
fi
[ "$rows" -gt 0 ] 2>/dev/null || rows=24
[ "$cols" -gt 0 ] 2>/dev/null || cols=80

# ── Which effect ─────────────────────────────────────────────────────────────
# An explicit argument wins over everything — that's how the options screen
# previews a pick, and how you test one without changing the saved choice.
saver="${1:-}"

if [ -z "$saver" ]; then
  [ -n "$sess" ] && saver=$(tmux show-options -v -t "$sess" @grid_saver 2>/dev/null)
  [ -n "$saver" ] || [ -z "$sess" ] || saver=$(cat "$GRID_CONFIG/saver.$sess" 2>/dev/null)
  [ -n "$saver" ] || saver=$(tmux show-options -gv @grid_saver 2>/dev/null)
  [ -n "$saver" ] || saver=matrix

  # The blocked-pane gate. Ten idle minutes used to dissolve the grid into
  # rain *even while a pane sat on ▲ waiting for an answer* — hiding the one
  # thing the dashboard exists to surface. The lock still fires (burn-in,
  # and a locked terminal is the point), but it renders the status screen
  # instead, so a blocked pane gets bigger rather than painted over.
  #
  # Only for the untargeted path: an explicit argument is someone asking for
  # a specific effect, and `@grid_saver_gate off` turns it off entirely.
  if [ -n "$sess" ] && [ "$(tmux show-options -gv @grid_saver_gate 2>/dev/null)" != off ]; then
    # Pipe-delimited, not space-delimited: grid_label only rewrites '/' to '-',
    # so a repo directory with a space in its name lands in @repo verbatim and
    # a space-split would read its second word as the state. The gate would
    # then fail exactly where it matters — silently not switching to standby
    # for the blocked pane it exists to surface.
    blocked=$(tmux list-panes -t "$sess" -F '#{@repo}|#{@state}' 2>/dev/null \
      | awk -F'|' '$1 != "" && $2 == "waiting" { n++ } END { print n + 0 }')
    [ "${blocked:-0}" -gt 0 ] 2>/dev/null && saver=standby
  fi
fi

# `random` rolls from the eye-candy list only (see grid-lib.sh).
if [ "$saver" = random ]; then
  saver=$(echo "$GRID_SAVERS_RANDOM" | awk -v r="$RANDOM" '{ print $((r % NF) + 1) }')
fi

# An unknown name — a typo in a saved file, or a saver deleted from disk while
# a session still names it — falls back rather than exiting, because exiting
# would unlock the client and make the screensaver look broken instead of
# misconfigured.
[ -f "$SCRIPT_DIR/savers/$saver.sh" ] || saver=matrix

# ── The backdrop ─────────────────────────────────────────────────────────────
# @grid_saver_backdrop names an effect to run UNDERNEATH the status screen, so
# the blocked-pane gate stops being a punishment: a blocked pane used to cost
# you whatever you had picked and replace it with a flat panel. Now the panel
# floats on the rain.
#
# Only standby composites. heartbeat draws a dense timeline across the whole
# width and has no free ground to show anything through; a backdrop there is
# noise behind data. Effects that can be a backdrop are listed in
# GRID_SAVERS_BACKDROP (grid-lib.sh) — the ones that draw one cell at a time
# and can therefore be told to keep out of the panel's rectangle.
backdrop=''
if [ "$saver" = standby ]; then
  [ -n "$sess" ] && backdrop=$(tmux show-options -v -t "$sess" @grid_saver_backdrop 2>/dev/null)
  [ -n "$backdrop" ] || [ -z "$sess" ] || backdrop=$(cat "$GRID_CONFIG/backdrop.$sess" 2>/dev/null)
  [ -n "$backdrop" ] || backdrop=$(tmux show-options -gv @grid_saver_backdrop 2>/dev/null)
  case "$backdrop" in
    ''|off|none) backdrop='' ;;
    random) backdrop=$(echo "$GRID_SAVERS_BACKDROP" | awk -v r="$RANDOM" '{ print $((r % NF) + 1) }') ;;
  esac
  # A name that isn't backdrop-capable is dropped rather than honoured: running
  # it as a full saver would hide the very panel the gate switched to.
  if [ -n "$backdrop" ]; then
    echo "$GRID_SAVERS_BACKDROP" | grep -qw -- "$backdrop" || backdrop=''
  fi
  [ -z "$backdrop" ] || [ -f "$SCRIPT_DIR/savers/$backdrop.sh" ] || backdrop=''
fi

# ── Opacity ──────────────────────────────────────────────────────────────────
# There is no alpha on a terminal: a cell holds one glyph in one colour and
# whatever was under it is gone. What opacity means here is how far the effect
# is faded toward the session's own background — 100 is exactly how the savers
# have always looked, 30 is a suggestion behind the panel, 0 is the background.
#
# It defaults lower when compositing because that is the case that needs it:
# full-brightness matrix behind a ledger is unreadable, and nobody should have
# to discover a second option to make the first one usable. An explicitly set
# value still wins — the test is on the option being empty, not on its value.
opacity=''
[ -n "$sess" ] && opacity=$(tmux show-options -v -t "$sess" @grid_saver_opacity 2>/dev/null)
[ -n "$opacity" ] || [ -z "$sess" ] || opacity=$(cat "$GRID_CONFIG/opacity.$sess" 2>/dev/null)
[ -n "$opacity" ] || opacity=$(tmux show-options -gv @grid_saver_opacity 2>/dev/null)
if [ -z "$opacity" ]; then
  if [ -n "$backdrop" ]; then opacity=35; else opacity=100; fi
fi
case "$opacity" in (*[!0-9]*|'') opacity=100 ;; esac
[ "$opacity" -gt 100 ] && opacity=100

# ── Colour ───────────────────────────────────────────────────────────────────
# Blending happens in RGB and comes back out as either a truecolor SGR or the
# nearest cell of the xterm 6x6x6 cube.
#
# The cube path is the default, and is not a consolation prize. The lock
# command writes its escapes STRAIGHT to the client's tty, so the conf's
# `terminal-features RGB` says nothing about whether truecolor will land here:
# that override describes tmux talking to the outer terminal, and in this
# context we are the one doing the talking. COLORTERM is the only thing that
# actually answers the question, and it is absent often enough to matter.
case "${COLORTERM:-}" in
  truecolor|24bit) SAV_TRUE=1 ;;
  *)               SAV_TRUE=0 ;;
esac
# COLORTERM is frequently not exported into the lock command's environment, and
# guessing "no" costs real fidelity: in 256 colours a 35%-opacity matrix
# quantizes its trail and its head onto the SAME cube cell, and the effect
# loses its depth entirely. So ask tmux what it was configured to believe. A
# grid whose conf sets `terminal-features RGB` is a grid whose owner has
# already decided their terminal does truecolor, and that is the same terminal
# this lock is writing to.
if [ "$SAV_TRUE" -eq 0 ]; then
  case "$(tmux show-options -gv terminal-features 2>/dev/null)$(tmux show-options -gv terminal-overrides 2>/dev/null)" in
    *RGB*|*Tc*) SAV_TRUE=1 ;;
  esac
fi

# The xterm defaults for 0-15, which have no formula.
SAV_ANSI16=(
  0,0,0       205,0,0     0,205,0     205,205,0
  0,0,238     205,0,205   0,205,205   229,229,229
  127,127,127 255,0,0     0,255,0     255,255,0
  92,92,255   255,0,255   0,255,255   255,255,255
)

# sav_rgb <0-255> — a 256-colour index to SAV_R/SAV_G/SAV_B.
sav_rgb() {
  local n=$1 c v t
  if [ "$n" -lt 16 ]; then
    t=${SAV_ANSI16[$n]}
    SAV_R=${t%%,*}; t=${t#*,}
    SAV_G=${t%%,*}; SAV_B=${t##*,}
  elif [ "$n" -lt 232 ]; then
    c=$(( n - 16 ))
    v=$(( c / 36 ));       SAV_R=$(( v == 0 ? 0 : 55 + v * 40 ))
    v=$(( (c % 36) / 6 )); SAV_G=$(( v == 0 ? 0 : 55 + v * 40 ))
    v=$(( c % 6 ));        SAV_B=$(( v == 0 ? 0 : 55 + v * 40 ))
  else
    v=$(( 8 + (n - 232) * 10 ))
    SAV_R=$v SAV_G=$v SAV_B=$v
  fi
}

# sav_level <0-255> — the cube axis nearest a channel value. Spelled out rather
# than derived: the cube's levels are 0,95,135,175,215,255, which is a 95-wide
# first step and 40 after it, and every closed form for that is wrong at one
# end or the other in a way that quietly darkens the whole ramp.
sav_level() {
  if   [ "$1" -lt 48 ];  then SAV_L=0
  elif [ "$1" -lt 116 ]; then SAV_L=1
  elif [ "$1" -lt 156 ]; then SAV_L=2
  elif [ "$1" -lt 196 ]; then SAV_L=3
  elif [ "$1" -lt 236 ]; then SAV_L=4
  else                        SAV_L=5
  fi
}

# sav_sgr — SAV_R/G/B as an SGR body (no ESC[, no m), into SAV_OUT.
sav_sgr() {
  local lr lg lb av gi gv cr cg cb dc dg
  if [ "$SAV_TRUE" -eq 1 ]; then
    SAV_OUT="38;2;${SAV_R};${SAV_G};${SAV_B}"
    return
  fi
  sav_level "$SAV_R"; lr=$SAV_L
  sav_level "$SAV_G"; lg=$SAV_L
  sav_level "$SAV_B"; lb=$SAV_L
  cr=$(( lr == 0 ? 0 : 55 + lr * 40 ))
  cg=$(( lg == 0 ? 0 : 55 + lg * 40 ))
  cb=$(( lb == 0 ? 0 : 55 + lb * 40 ))
  dc=$(( (SAV_R - cr) * (SAV_R - cr) + (SAV_G - cg) * (SAV_G - cg) + (SAV_B - cb) * (SAV_B - cb) ))

  # A dimmed accent spends most of its life near grey, and the 232-255 ramp has
  # twenty-four steps where the cube has six — so it is usually the better fit.
  # Usually, not always: pure white is a cube colour (231) and the nearest grey
  # is 238,238,238, so picking the ramp on "the three axes agree" alone turns
  # every hot head dirty. Measure both and take the closer.
  av=$(( (SAV_R + SAV_G + SAV_B) / 3 ))
  gi=$(( (av - 3) / 10 ))
  [ "$gi" -lt 0 ] && gi=0
  [ "$gi" -gt 23 ] && gi=23
  gv=$(( 8 + gi * 10 ))
  dg=$(( (SAV_R - gv) * (SAV_R - gv) + (SAV_G - gv) * (SAV_G - gv) + (SAV_B - gv) * (SAV_B - gv) ))

  if [ "$dg" -lt "$dc" ]; then
    SAV_OUT="38;5;$(( 232 + gi ))"
  else
    SAV_OUT="38;5;$(( 16 + lr * 36 + lg * 6 + lb ))"
  fi
}

# sav_blend <r g b> <r g b> <pct of the first> — into SAV_R/G/B.
sav_blend() {
  SAV_R=$(( ($1 * $7 + $4 * (100 - $7)) / 100 ))
  SAV_G=$(( ($2 * $7 + $5 * (100 - $7)) / 100 ))
  SAV_B=$(( ($3 * $7 + $6 * (100 - $7)) / 100 ))
}

# SAV_SGR[0..3] — the four intensities every composable effect draws with:
# 0 faint/far, 1 the body colour, 2 near, 3 the hot head. This replaces the
# "2;", "0;", "1;" and "1;97" the savers used to spell inline, so that one
# knob moves all four together and every effect dims the same way.
#
# Every level keeps the SGR attribute the savers used to spell by hand — faint,
# normal, bold, bold. The colour already carries the brightness, so this looks
# redundant, and on the truecolor path very nearly is. It is load-bearing on
# the 256-colour path: below about 50% opacity neighbouring levels quantize
# onto the SAME cube cell, and without the attribute a dimmed matrix would have
# a trail and a head in identical colour with nothing between them. Faint and
# bold keep the depth when the palette runs out of room to.
SAV_SGR=('' '' '' '')
sav_ramp() {
  local i br bgc bb ar ag ab pre
  sav_rgb "$bg";     br=$SAV_R bgc=$SAV_G bb=$SAV_B
  sav_rgb "$accent"; ar=$SAV_R ag=$SAV_G  ab=$SAV_B
  for i in 0 1 2 3; do
    pre=''
    case $i in
      0) sav_blend $ar $ag $ab $br $bgc $bb 45; pre='2;' ;;
      1) SAV_R=$ar SAV_G=$ag SAV_B=$ab ;;
      2) sav_blend 255 255 255 $ar $ag $ab 45;  pre='1;' ;;
      3) SAV_R=255 SAV_G=255 SAV_B=255;         pre='1;' ;;
    esac
    # Opacity applies to every level equally. Fading the trail but not the head
    # would only change the contrast within the effect; the point is to change
    # how present the whole thing is.
    if [ "$opacity" -lt 100 ]; then
      sav_blend $SAV_R $SAV_G $SAV_B $br $bgc $bb "$opacity"
    fi
    sav_sgr
    SAV_SGR[$i]="${pre}${SAV_OUT}"
  done
}

# sav_sgr_idx <0-255> — an arbitrary palette colour at the current opacity,
# into SAV_OUT. pipes and bounce draw in GRID_PALETTE rather than the accent,
# so they can't use the ramp; they call this once per colour at startup and
# index the results, which keeps the arithmetic out of the frame loop.
sav_sgr_idx() {
  local r g b
  sav_rgb "$1"
  if [ "$opacity" -lt 100 ]; then
    r=$SAV_R g=$SAV_G b=$SAV_B
    sav_rgb "$bg"
    sav_blend $r $g $b $SAV_R $SAV_G $SAV_B "$opacity"
  fi
  sav_sgr
}

sav_ramp

# ── The keep-out rectangle ───────────────────────────────────────────────────
# A composite could redraw the panel on top of the backdrop every frame, but
# that is 2.5KB of ledger sixteen times a second on a link that is sometimes a
# dev tunnel to an iPad. Instead the panel publishes its rectangle here, the
# backdrop skips any cell inside it, and the panel only has to redraw when its
# own content changes — once a second.
#
# KEEP_B below KEEP_T means "no rectangle", which is the solo case: the test
# then costs one failed integer comparison per glyph.
KEEP_T=0 KEEP_B=-1 KEEP_L=0 KEEP_R=-1

# sav_hidden <y> <x> — is this cell under the panel?
sav_hidden() {
  [ "$1" -ge "$KEEP_T" ] && [ "$1" -le "$KEEP_B" ] && [ "$2" -ge "$KEEP_L" ] && [ "$2" -le "$KEEP_R" ]
}

# ── The frame loop ───────────────────────────────────────────────────────────
# A saver defines EITHER saver_begin/saver_frame — set up state, then append
# one frame's worth of escapes to $frame — or its own animate(). Only the first
# kind can be composited, and the reason is not style: two animate() jobs
# writing to one tty interleave mid-escape-sequence, because each frame is a
# multi-KB printf that stdio splits across several write()s. The result is
# intermittent garbage that looks like a rendering bug. A composite therefore
# has to be one process calling two renderers in a known order.
#
# Savers that exec a non-bash worker (fire, life) or own the whole screen
# (heartbeat) stay animate()-only and are simply never offered as backdrops.
sav_solo() {
  saver_begin
  while :; do
    frame=''
    saver_frame
    printf '%b' "$frame"
    sleep "$SAVER_DELAY"
  done
}

# The panel renders first so that saver_frame sees this frame's keep-out
# rectangle rather than the last one's — which matters on the frame where the
# panel changes shape, since the backdrop must not paint into rows the panel is
# about to erase.
sav_composite() {
  local tickf=0 every
  saver_begin
  sb_overlay_begin
  every=$(awk -v d="$SAVER_DELAY" 'BEGIN { n = int(1 / d + 0.5); print (n < 1) ? 1 : n }')
  while :; do
    frame=''
    [ $(( tickf % every )) -eq 0 ] && sb_overlay_frame
    saver_frame
    printf '%b' "$frame"
    tickf=$(( tickf + 1 ))
    sleep "$SAVER_DELAY"
  done
}

if [ -n "$backdrop" ]; then
  . "$SCRIPT_DIR/savers/$backdrop.sh"
  . "$SCRIPT_DIR/savers/$saver.sh"
  runner=sav_composite
else
  . "$SCRIPT_DIR/savers/$saver.sh"
  # A saver that defines the contract gets the loop above; one that defines its
  # own animate() keeps it. Checked rather than declared so that adding a saver
  # is still "a file plus a word in GRID_SAVERS".
  if [ "$(type -t saver_frame 2>/dev/null)" = function ]; then
    runner=sav_solo
  else
    runner=animate
  fi
fi

cleanup() {
  [ -n "${anim:-}" ] && kill "$anim" 2>/dev/null
  wait 2>/dev/null
  printf '\e[?1000l\e[?1006l\e[0m\e[?25h\e[2J\e[H\e[?1049l'
}
trap cleanup EXIT INT TERM

# Mouse reporting (1000, SGR-encoded via 1006) is on for the duration: a
# click lands as an escape sequence on the same stdin the read below waits
# on, so mouse and keyboard both wake the grid.
printf '\e[?1049h\e[?25l\e[2J\e[?1000h\e[?1006h'

# What the grid looked like going in, for the wake summary below. Taken before
# the first frame so it measures the whole time the screen was away.
locked_at=$(date +%s)
snapshot=''
[ -n "$sess" ] && snapshot=$(tmux list-panes -t "$sess" -F '#{@repo}|#{@state}' 2>/dev/null \
  | awk -F'|' '$1 != "" { print "O", $1, $2 }')

$runner &
anim=$!

# Any key or mouse click — or EOF, when there's no tty to read — ends the
# show.
IFS= read -rsn1 || true

# ── the wake summary ─────────────────────────────────────────────────────────
# Coming back to the grid used to tell you nothing about the gap you just left.
# The screensaver knows exactly how long it held the screen and what every pane
# was doing when it took over, so on the way out it says what changed — as a
# status-line toast, which costs no time and needs no dismissing, rather than an
# overlay standing between the keypress and the work.
#
# Silent when nothing changed, and silent for a lock that barely happened: a
# stray keypress inside the first minute is not an absence worth reporting.
# @grid_saver_summary "off" turns it off.
away=$(( $(date +%s) - locked_at ))
if [ -n "$sess" ] && [ "$away" -ge 60 ] \
   && [ "$(tmux show-options -gv @grid_saver_summary 2>/dev/null)" != off ]; then
  summary=$(
    {
      printf '%s\n' "$snapshot"
      tmux list-panes -t "$sess" -F '#{@repo}|#{@state}|#{@state_since}' 2>/dev/null \
        | awk -F'|' '$1 != "" { print "N", $1, $2, $3 }'
    } | awk -v now="$(date +%s)" -v away="$away" '
      function dur(s) {
        if (s < 60)   return sprintf("%ds", s)
        if (s < 3600) return sprintf("%dm", int(s / 60))
        return sprintf("%dh%02d", int(s / 3600), int((s % 3600) / 60))
      }
      $1 == "O" { old[$2] = $3 }
      $1 == "N" { new[$2] = $3; since[$2] = $4 + 0 }
      END {
        for (r in new) {
          if (new[r] == old[r]) continue
          if (new[r] == "waiting") {
            nb++
            if (who == "" || since[r] < oldest) { oldest = since[r]; who = r }
          } else if (new[r] == "done") nd++
        }
        if (nb == 0 && nd == 0) exit
        out = sprintf("#[fg=colour245]away %s#[default]", dur(away))
        if (nd > 0) out = out sprintf("  #[fg=colour114]✔ %d finished#[default]", nd)
        if (nb > 0) {
          if (nb == 1) out = out sprintf("  #[fg=colour203,bold]▲ %s blocked %s#[default]", who, dur(now - oldest))
          else         out = out sprintf("  #[fg=colour203,bold]▲ %d blocked, longest %s %s#[default]", nb, who, dur(now - oldest))
        }
        print out
      }')
  # Shown on the client that actually woke, not "the current client". With two
  # terminals on one session — the normal case here — an untargeted toast lands
  # wherever you last typed, which may be the terminal that never locked.
  #
  # -c is right for this and does NOT contradict the rule that -c cannot
  # retarget option lookups: that rule is about FORMAT RESOLUTION (@user and
  # session options resolve against the server's current session regardless),
  # and this message is a literal string that was fully resolved above. -c only
  # has to decide which terminal draws it, which is exactly what it does.
  # client_name is the tty, which is what session_attached_list gave us.
  if [ -n "$summary" ]; then
    tmux display-message ${mytty:+-c "$mytty"} -d 5000 "$summary" 2>/dev/null \
      || tmux display-message -t "$sess" -d 5000 "$summary" 2>/dev/null
  fi
fi
