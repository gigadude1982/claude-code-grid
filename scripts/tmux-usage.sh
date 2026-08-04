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

out="#[fg=$(color_for "$five_pct")]⚡${five_pct}%"
if [ -n "$five_rst" ]; then
  out="$out#[fg=colour244] ↻$(date -r "$five_rst" '+%l:%M%p' 2>/dev/null | tr -d ' ' | tr 'APM' 'apm')"
fi
if [ -n "$seven_pct" ]; then
  out="$out #[fg=$(color_for "$seven_pct")]7d:${seven_pct}%"
fi

# Dim the whole thing if the cache is >30min stale (no active claude session
# has refreshed it recently).
now=$(date +%s)
if [ -n "$cached_ts" ] && [ $((now - cached_ts)) -gt 1800 ]; then
  out="#[fg=colour240]⚡${five_pct}% (stale)"
fi

printf '%s#[default] ' "$out"
