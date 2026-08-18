#!/bin/bash
# pane-border.sh <@repo> <@repo_color> <pane_current_path> <pane_title>
#                [@state] [@state_since] [@cl_model] [@cl_cost] [@cl_rate]
#
# Renders one pane's border label. Called from pane-border-format in
# tmux/grid.tmux.conf via #() — tmux re-runs it every status-interval, and
# interprets #[...] style codes in the output.
#
#   ▸ repo-name (branch) ● 4m      ● red = uncommitted changes
#   ▸ repo-name (branch) ✓ 12s     ✓ green = clean
#
# The state *glyph* is deliberately NOT rendered here: tmux caches #() output
# and only re-runs it on the status interval, so a glyph drawn by this script
# would lag the actual transition by up to 15s. grid.tmux.conf draws it with
# native #{?...} format conditionals on @state instead, which repaint the
# instant pane-state.sh sets the option. What's left here is the elapsed
# time, which is a minutes-scale number where interval-fresh is fine.
#
# Falls back to the plain pane_title for panes without @repo set (i.e. any
# tmux session that isn't a claude grid).
repo="$1" color="$2" path="$3" title="$4" state="${5:-}" since="${6:-}"
model="${7:-}" cost="${8:-}" rate="${9:-}"

if [ -z "$repo" ]; then
  printf ' %s ' "$title"
  exit 0
fi

branch="" gitstate=""
if git -C "$path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git -C "$path" branch --show-current 2>/dev/null)
  if [ -n "$(git -C "$path" status --porcelain 2>/dev/null | head -1)" ]; then
    gitstate="#[fg=colour203]●"
  else
    gitstate="#[fg=colour114]✓"
  fi
fi

# How long this pane has been in its current state. Idle panes get nothing —
# "idle 3h" is noise, and the number only earns its space when it tells you
# how long something has been waiting on you.
elapsed=""
case "$state" in
  working|waiting|done)
    if [ -n "$since" ] && [ "$since" -gt 0 ] 2>/dev/null; then
      d=$(( $(date +%s) - since ))
      [ "$d" -lt 0 ] && d=0
      if   [ "$d" -lt 60 ];   then elapsed="${d}s"
      elif [ "$d" -lt 3600 ]; then elapsed="$((d / 60))m"
      else                         elapsed="$((d / 3600))h$(( (d % 3600) / 60 ))m"
      fi
    fi
    ;;
esac

printf '#[fg=%s,bold]%s #[default]' "${color:-colour250}" "$repo"
[ -n "$branch" ]   && printf '#[fg=colour244](%s) ' "$branch"
[ -n "$gitstate" ] && printf '%s ' "$gitstate"

# Claude session stats, stamped as @cl_* pane options by claude-status-line's
# statusline.sh: which model runs here, what it has cost, how fast it burns.
[ -n "$model" ] && printf '#[fg=colour244]◆%s ' "$model"
if [ -n "$cost" ]; then
  printf '#[fg=colour178]$%s' "$cost"
  [ -n "$rate" ] && printf '#[fg=colour244]·$%s/hr' "$rate"
  printf ' '
fi
if [ -n "$elapsed" ]; then
  # Match the glyph's urgency: a pane that's been blocked on you for 8
  # minutes should read louder than one that's been working for 8 minutes.
  case "$state" in
    waiting) printf '#[fg=colour203]%s ' "$elapsed" ;;
    done)    printf '#[fg=colour114]%s ' "$elapsed" ;;
    *)       printf '#[fg=colour240]%s ' "$elapsed" ;;
  esac
fi
