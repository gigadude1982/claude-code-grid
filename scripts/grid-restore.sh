#!/bin/bash
# grid-restore.sh — bring grids back to life after a resurrect restore.
#
# Wired to @resurrect-hook-post-restore-all. tmux-resurrect brings back the
# session, its layout and each pane's working directory — but not user
# options and not the program that was running, so without this you get four
# anonymous shells in the right directories and have to rebuild by hand.
#
# What this adds: pane labels/colors are recovered by matching each restored
# pane's cwd against <session>.repos (positional matching would mislabel
# every pane if the layout came back in a different order), the grid's
# root/profile are re-read from <session>.env, and Claude is relaunched with
# --continue wherever a stored conversation exists — so a reboot picks up
# mid-conversation instead of cold.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/grid-lib.sh"

# Panes are freshly-spawned shells at this point; give them a moment to
# finish sourcing ~/.zshrc, or the keys we send land before claude_tracked
# is a defined function.
sleep 2

restore_session() {
  session="$1"
  repos_file="$GRID_CONFIG/$session.repos"
  env_file="$GRID_CONFIG/$session.env"
  [ -s "$repos_file" ] || return 0

  root="" profile=""
  if [ -f "$env_file" ]; then
    root=$(awk -F= '$1 == "GRID_ROOT" { sub(/^[^=]*=/, ""); print }' "$env_file")
    profile=$(awk -F= '$1 == "GRID_PROFILE" { sub(/^[^=]*=/, ""); print }' "$env_file")
  fi
  [ -n "$root" ] || return 0
  [ -n "$profile" ] || profile="$session"

  state="$GRID_CONFIG/$session.worktrees"
  board="$GRID_CONFIG/$session.board.md"
  tmux set-option -t "$session" @grid_root    "$root"
  tmux set-option -t "$session" @grid_profile "$profile"
  tmux set-option -t "$session" @grid_state   "$state"
  tmux set-option -t "$session" @grid_board   "$board"
  # The arrangement itself came back with resurrect (it saves geometry), so
  # this only re-stamps the option — deliberately without re-applying it,
  # since that would flatten any pane sizes you'd nudged by hand. It matters
  # for what happens NEXT: the first grid-add after a reboot should extend the
  # layout you chose, not silently tile the grid.
  tmux set-option -t "$session" @grid_layout  "$(grid_layout "$session")"

  while IFS=$'\t' read -r pane path cmd; do
    # Skip panes that already have something running — a restore can race
    # with resurrect's own process restoration, and relaunching over a live
    # claude would be worse than leaving the pane alone.
    case "$cmd" in
      bash|zsh|sh|fish) ;;
      *) continue ;;
    esac

    # Which repo is this pane sitting in? Worktree paths collapse to their
    # parent repo so a pane restored inside .claude/worktrees/foo still gets
    # its repo's label and color.
    base="${path%%/.claude/worktrees/*}"
    idx=0 rel=""
    while IFS= read -r candidate; do
      [ -n "$candidate" ] || continue
      if [ "$base" = "$root/$candidate" ]; then rel="$candidate"; break; fi
      idx=$((idx + 1))
    done < "$repos_file"
    [ -n "$rel" ] || continue

    resume=""
    grid_has_conversation "$base" "$profile" && resume="resume"

    "$SCRIPT_DIR/grid-pane.sh" "$pane" "$base" "$(grid_label "$rel")" \
      "$(grid_color "$idx")" "$state" "$profile" "$resume"
  done < <(tmux list-panes -t "$session:0" \
             -F '#{pane_id}	#{pane_current_path}	#{pane_current_command}' 2>/dev/null)
}

if [ $# -gt 0 ]; then
  for s in "$@"; do restore_session "$s"; done
else
  while IFS= read -r s; do restore_session "$s"; done < <(tmux list-sessions -F '#{session_name}' 2>/dev/null)
fi

exit 0
