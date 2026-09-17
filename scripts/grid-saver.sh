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
. "$SCRIPT_DIR/savers/$saver.sh"

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

animate &
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
