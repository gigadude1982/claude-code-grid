#!/bin/bash
# grid-add.sh [repo-rel-path] — add a repo to the running grid.
#
# Bound to prefix+a (opens the picker in a popup). Without an argument it
# fzf-picks from the grid's root, hiding repos that already have a pane.
# Entries ending in '/' are folders of repos (grid_repo_list) — picking one
# gives the parent a pane; the slash is display only and is stripped below.
#
# Exists because the alternative was killing the whole session and re-picking
# — which throws away three healthy conversations to start a fourth. The new
# pane is dressed by grid-pane.sh, so it's indistinguishable from one built
# at launch, and the selection is written back to <session>.repos so the next
# `pdev` comes up with it too.
#
# The split direction is deliberately not a choice: grid_apply_layout below
# re-arranges the whole window a line later, so any geometry a split produced
# is gone before it's drawn. Orientation is a per-grid setting instead
# (prefix+Space / the ▦ chip / grid-layout.sh). What the split target DOES
# decide is order — select-layout arranges panes by index — which is why the
# target is chosen carefully below and mirrored into <session>.repos.
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
  # The present list arrives as a first input file, not `awk -v`: macOS's awk
  # (BWK 20200816) rejects a literal newline inside a -v assignment, so the
  # filter died — silently emptying the picker — the moment a grid had two
  # panes to exclude.
  rel=$(grid_repo_list "$root" \
    | awk 'NR == FNR { seen[$0] = 1; next }
           { label = $0; sub("/$", "", label); gsub("/", "-", label)
             if (!(label in seen)) print }' <(printf '%s\n' "$present") - \
    | fzf --prompt="add to $session> " \
          --header='enter = add a pane · a trailing / is a folder of repos, opened as one')
fi
[ -n "$rel" ] || exit 0

# The trailing slash is picker notation for "this is a parent folder", not
# part of the path. Drop it before it reaches the label or the .repos file.
rel="${rel%/}"

repo="$root/$rel"
[ -d "$repo" ] || { echo "grid-add: no such directory: $repo" >&2; exit 1; }

# Color by pane count so a new pane picks up where the palette left off
# rather than colliding with pane 0.
count=$(tmux list-panes -t "$session:0" -F x 2>/dev/null | wc -l | tr -d ' ')

# Which pane gets split — i.e. where the new one lands in the layout.
#
# It used to be the window's active pane, which meant the repo appeared
# wherever the cursor happened to be while the .repos file appended it to the
# end: the live grid and the next `pdev` disagreed about the order. The last
# pane is what "add a repo" implies, and it's what the file already said.
#
# Exactly one marked pane (prefix+m) overrides that — the ⦿ gesture already
# means "this one", so a repo can be placed next to the one it relates to.
# Several marked panes is a broadcast set, not a placement hint, so it's
# ignored rather than guessed at.
target=$(tmux list-panes -t "$session:0" -F '#{pane_id} #{@marked}' 2>/dev/null \
  | awk '$2 == 1 { m[++n] = $1 } END { if (n == 1) print m[1] }')
[ -n "$target" ] || \
  target=$(tmux list-panes -t "$session:0" -F '#{pane_id}' 2>/dev/null | tail -1)

pane=$(tmux split-window -t "${target:-$session:0}" -c "$root" -P -F '#{pane_id}')
grid_apply_layout "$session"

"$SCRIPT_DIR/grid-pane.sh" "$pane" "$repo" "$(grid_label "$rel")" \
  "$(grid_color "$count")" "$state" "$profile"

# Remember it for next launch, in the position it actually occupies: right
# after the repo it was split off, not blindly at the end. Appending was fine
# while the target was always the last pane, but a marked-pane placement would
# come back somewhere else after a restart — and "the grid looks different
# than I left it" is exactly the drift this is meant to close.
#
# Lines are root-relative ("a/b") and pane labels are flattened ("a-b"), so
# the match is on the flattened line — the same trick grid-drop.sh uses.
f="$GRID_CONFIG/$session.repos"
after=$(tmux display-message -p -t "$target" '#{@repo}' 2>/dev/null)
if [ ! -f "$f" ]; then
  printf '%s\n' "$rel" > "$f"
elif ! grep -qxF "$rel" "$f"; then
  awk -v rel="$rel" -v after="$after" '
    { print
      l = $0; gsub("/", "-", l)
      if (!placed && after != "" && l == after) { print rel; placed = 1 } }
    END { if (!placed) print rel }' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
fi

tmux select-pane -t "$pane"
