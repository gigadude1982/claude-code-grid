#!/bin/bash
# tmux-usage.sh [session-name]
#
# Emits the Claude plan usage (5h session window + 7d window) into the tmux
# status bar, colored by threshold. Reads the rate-limit cache maintained by
# claude-status-line's statusline.sh (github.com/gigadude1982/claude-status-line)
# — no extra API calls. Limits are account-wide, so one readout covers every
# pane in the grid.
#
# Which account depends on the attached session ("work" grid → ~/.claude-work,
# everything else → ~/.claude-personal); grid.tmux.conf passes '#{session_name}'.
#
# Cache line format (tab-separated, written by statusline.sh):
#   five_hr_pct  five_reset_epoch  seven_day_pct  seven_reset_epoch  cached_ts

case "${1:-personal}" in
  work) profile=".claude-work" ;;
  *)    profile=".claude-personal" ;;
esac

tmpdir=$(getconf DARWIN_USER_TEMP_DIR 2>/dev/null || echo /tmp)
cache="${tmpdir%/}/.claude_rl_$(id -u)_${profile}"

[ -f "$cache" ] || exit 0
IFS=$'\t' read -r five_pct five_rst seven_pct seven_rst cached_ts <"$cache"
[ -n "$five_pct" ] || exit 0

color_for() {
  if [ "$1" -ge 85 ] 2>/dev/null; then echo "colour203"
  elif [ "$1" -ge 60 ] 2>/dev/null; then echo "colour221"
  else echo "colour114"; fi
}

now=$(date +%s)

# ── Burn-rate sparkline ──────────────────────────────────────────────────────
# One session-window sample per 5 minutes, last 12 kept: ▂▂▃▅▇ is the past
# hour of burn at a glance, not just the current number. Sampling happens
# here because this script already runs every status-interval — no extra
# process needed. LC_ALL=C so awk slices the 3-byte block glyphs by byte.
hist="${tmpdir%/}/.claude_rl_spark_$(id -u)_${profile}"
last=$(tail -1 "$hist" 2>/dev/null | cut -d' ' -f1)
if [ $((now - ${last:-0})) -ge 300 ]; then
  printf '%s %s\n' "$now" "$five_pct" >> "$hist"
  tail -12 "$hist" > "$hist.t" && mv "$hist.t" "$hist"
fi
spark=$(LC_ALL=C awk '{ i = int($2 / 12.6); if (i > 7) i = 7; if (i < 0) i = 0;
  printf "%s", substr("▁▂▃▄▅▆▇█", i * 3 + 1, 3) }' "$hist" 2>/dev/null)

out="#[fg=$(color_for "$five_pct")]⚡${five_pct}%"
[ "${#spark}" -ge 6 ] && out="#[fg=colour244]${spark} $out"
if [ -n "$five_rst" ]; then
  out="$out#[fg=colour244] ↻$(date -r "$five_rst" '+%l:%M%p' 2>/dev/null | tr -d ' ' | tr 'APM' 'apm')"
fi
if [ -n "$seven_pct" ]; then
  out="$out #[fg=$(color_for "$seven_pct")]7d:${seven_pct}%"
fi

# Dim the whole thing if the cache is >30min stale (no active claude session
# has refreshed it recently). Reassigning out also drops the sparkline —
# stale history isn't a trend worth drawing.
if [ -n "$cached_ts" ] && [ $((now - cached_ts)) -gt 1800 ]; then
  out="#[fg=colour240]⚡${five_pct}% (stale)"
fi

printf '%s#[default] ' "$out"
