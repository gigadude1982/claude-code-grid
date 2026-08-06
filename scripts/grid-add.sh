#!/bin/bash
# grid-add.sh [repo-rel-path] — add a repo to the running grid.
#
# Bound to prefix+a (opens the picker in a popup). Without an argument it
# fzf-picks from the grid's root, hiding repos that already have a pane.
#
# Exists because the alternative was killing the whole session and re-picking
# — which throws away three healthy conversations to start a fourth. The new
# pane is dressed by grid-pane.sh, so it's indistinguishable from one built
# at launch, and the selection is written back to <session>.repos so the next
# `pdev` comes up with it too.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/grid-lib.sh"

session=$(grid_current_session)
[ -n "$session" ] || { echo "grid-add: not inside tmux" >&2; exit 1; }

root=$(grid_session_opt "$session" @grid_root)
profile=$(grid_session_opt "$session" @grid_profile)
state=$(grid_session_opt "$session" @grid_state)
if [ -z "$root" ]; then
  echo "grid-add: '$session' isn't a claude grid (no @grid_root)" >&2
  exit 1
fi

# Repos already on screen, so the picker only offers things you don't already
# have. Matched on the @repo label rather than pane_current_path: a pane that
# has cd'd into a worktree reports .../.claude/worktrees/foo, which wouldn't
# match its repo's relative path.
present=$(tmux list-panes -t "$session:0" -F '#{@repo}' 2>/dev/null | sort -u)

rel="${1:-}"
if [ -z "$rel" ]; then
  rel=$(find "$root" -maxdepth 3 -name .git -not -path '*/worktrees/*' 2>/dev/null \
    | sed 's|/\.git$||' | sed "s|^$root/||" | sort \
    | awk -v pres="$present" '
        BEGIN { n = split(pres, a, "\n"); for (i = 1; i <= n; i++) seen[a[i]] = 1 }
        { label = $0; gsub("/", "-", label); if (!(label in seen)) print }' \
    | fzf --prompt="add to $session> " --header='enter = add a pane for this repo')
fi
[ -n "$rel" ] || exit 0

repo="$root/$rel"
[ -d "$repo" ] || { echo "grid-add: no such directory: $repo" >&2; exit 1; }

# Color by pane count so a new pane picks up where the palette left off
# rather than colliding with pane 0.
count=$(tmux list-panes -t "$session:0" -F x 2>/dev/null | wc -l | tr -d ' ')

pane=$(tmux split-window -t "$session:0" -c "$root" -P -F '#{pane_id}')
tmux select-layout -t "$session:0" tiled

"$SCRIPT_DIR/grid-pane.sh" "$pane" "$repo" "$(grid_label "$rel")" \
  "$(grid_color "$count")" "$state" "$profile"

# Remember it for next launch. Appended rather than rewritten so the existing
# pane order is preserved.
f="$GRID_CONFIG/$session.repos"
if [ -f "$f" ] && ! grep -qxF "$rel" "$f"; then
  printf '%s\n' "$rel" >> "$f"
elif [ ! -f "$f" ]; then
  printf '%s\n' "$rel" > "$f"
fi

tmux select-pane -t "$pane"
