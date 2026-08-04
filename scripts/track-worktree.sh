#!/usr/bin/env zsh
# track-worktree.sh <repo> <state-file>
#
# Launched in the background by claude_tracked() (zsh/grid.zsh) right before
# Claude Code starts. Polls for up to 15s for a new git worktree to appear
# in <repo> and appends "repo|worktree" to <state-file> the moment it does —
# so even if the pane is killed abruptly later, the prune machinery knows
# what to safety-check. If Claude never creates a worktree (no auto-worktree
# wrapper in use), this simply times out silently.
repo="$1"
state_file="$2"
before=$(git -C "$repo" worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2}' | sort)
for i in {1..30}; do
  sleep 0.5
  after=$(git -C "$repo" worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2}' | sort)
  new_wt=$(comm -13 <(print -r -- "$before") <(print -r -- "$after"))
  if [ -n "$new_wt" ]; then
    mkdir -p "$(dirname "$state_file")"
    printf '%s|%s\n' "$repo" "$new_wt" >>"$state_file"
    exit 0
  fi
done
