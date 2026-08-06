#!/bin/bash
# grid-rollup.sh [session] — one-glance state summary for the status bar.
#
#   ▶2 ▲1 ✔1     2 working, 1 blocked on you, 1 finished its turn
#
# Glyphs and colors match the per-pane border markers in grid.tmux.conf, so
# the status bar and the frames read as the same language. Zero counts are
# omitted — the bar shares 80 columns with the usage meter and a clock, and
# "▲0" is not information. Emits nothing at all for non-grid sessions.
set -u

session="${1:-}"
[ -n "$session" ] || session=$(tmux display-message -p '#{session_name}' 2>/dev/null)
[ -n "$session" ] || exit 0
# No grid-lib here: this runs on every status refresh for every client, and
# the session name always arrives as an argument from the status-right format.

counts=$(tmux list-panes -t "$session" -F '#{@repo} #{@state}' 2>/dev/null \
  | awk '$1 != "" { n[$2]++ } END { printf "%d %d %d", n["working"], n["waiting"], n["done"] }')

read -r working waiting done <<< "$counts"
[ -n "${working:-}" ] || exit 0
[ $((working + waiting + done)) -gt 0 ] || exit 0

out=""
[ "$waiting" -gt 0 ] && out="$out#[fg=colour203,bold]▲${waiting} "
[ "$done"    -gt 0 ] && out="$out#[fg=colour114]✔${done} "
[ "$working" -gt 0 ] && out="$out#[fg=colour81]▶${working} "

printf '%s#[default]' "$out"
