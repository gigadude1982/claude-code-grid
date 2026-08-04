#!/bin/bash
# pane-border.sh <@repo> <@repo_color> <pane_current_path> <pane_title>
#
# Renders one pane's border label. Called from pane-border-format in
# tmux/grid.tmux.conf via #() — tmux re-runs it every status-interval, and
# interprets #[...] style codes in the output.
#
#   ▸ repo-name (branch) ●        ● red = uncommitted changes
#   ▸ repo-name (branch) ✓        ✓ green = clean
#
# Falls back to the plain pane_title for panes without @repo set (i.e. any
# tmux session that isn't a claude grid).
repo="$1" color="$2" path="$3" title="$4"

if [ -z "$repo" ]; then
  printf ' %s ' "$title"
  exit 0
fi

branch="" state=""
if git -C "$path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git -C "$path" branch --show-current 2>/dev/null)
  if [ -n "$(git -C "$path" status --porcelain 2>/dev/null | head -1)" ]; then
    state="#[fg=colour203]●"
  else
    state="#[fg=colour114]✓"
  fi
fi

printf '#[fg=%s,bold] %s #[default]' "${color:-colour250}" "$repo"
[ -n "$branch" ] && printf '#[fg=colour244](%s) ' "$branch"
[ -n "$state" ] && printf '%s ' "$state"
