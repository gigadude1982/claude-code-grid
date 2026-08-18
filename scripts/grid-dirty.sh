#!/bin/bash
# grid-dirty.sh <session> — count of grid panes with uncommitted changes,
# rendered for the ⎇ header chip. Prints nothing when everything is clean so
# the chip stays quiet. Runs from status-format via #(), which tmux caches
# per status-interval — a handful of `git status` calls every 15s is cheap
# at grid sizes.
set -u
session="${1:-}"

n=0
while IFS=$'\t' read -r repo path; do
  [ -n "$repo" ] || continue
  if [ -n "$(git -C "$path" status --porcelain 2>/dev/null | head -1)" ]; then
    n=$((n + 1))
  fi
done <<EOF
$(tmux list-panes -t "$session:0" -F "#{@repo}	#{pane_current_path}" 2>/dev/null)
EOF

[ "$n" -gt 0 ] && printf '#[fg=colour203]%s●' "$n"
exit 0
