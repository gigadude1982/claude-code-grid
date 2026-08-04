#!/bin/bash
# prune-worktrees.sh <state-file> [session-name]
#
# Reads "repo|worktree_path" lines written by track-worktree.sh and removes
# each worktree ONLY if BOTH:
#   1. it has no uncommitted changes (git status --porcelain is empty), and
#   2. its HEAD commit is reachable from some other ref in the repo (i.e.
#      nothing unique/unmerged would be lost by deleting the branch).
# Anything that fails either check is left alone and logged instead
# (<session>.log next to the state file).
#
# Fired three ways so cleanup never depends on remembering a command:
#   - pdev-stop/wdev-stop run it synchronously (visible output)
#   - tmux's session-closed hook runs it via prune-dispatch.sh
#   - start-grid.sh sweeps at launch (catches kill-server/reboot leftovers)
set -u

state_file="${1:?usage: prune-worktrees.sh <state-file> [session-name]}"
session_name="${2:-}"

# Optional gate: if a session name is passed, only act when it matches the
# state file it's paired with (state files are named <session>.worktrees).
expected="$(basename "$state_file" .worktrees)"
if [ -n "$session_name" ] && [ "$session_name" != "$expected" ]; then
  exit 0
fi

[ -s "$state_file" ] || exit 0

log_file="${state_file%.worktrees}.log"
tmp_file="$(mktemp)"

while IFS='|' read -r repo wt; do
  [ -z "${repo:-}" ] && continue

  if [ ! -d "$wt" ]; then
    # Already gone (removed manually, or never really created) — drop it.
    continue
  fi

  if [ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ]; then
    echo "[prune-worktrees] $(date '+%F %T') skip (uncommitted changes): $wt" >>"$log_file"
    echo "$repo|$wt" >>"$tmp_file"
    continue
  fi

  head_sha="$(git -C "$wt" rev-parse HEAD 2>/dev/null)"
  branch="$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null)"

  if [ -z "$head_sha" ] || [ -z "$branch" ]; then
    echo "[prune-worktrees] $(date '+%F %T') skip (couldn't read git state): $wt" >>"$log_file"
    echo "$repo|$wt" >>"$tmp_file"
    continue
  fi

  # NB: `branch -a --contains` prefixes the current branch with '*' AND any
  # branch checked out in another worktree with '+' — strip both, or the
  # worktree's own branch masquerades as "reachable elsewhere".
  elsewhere="$(git -C "$repo" branch -a --contains "$head_sha" 2>/dev/null | sed 's/^[*+ ]*//' | grep -v "^${branch}\$")"

  if [ -z "$elsewhere" ]; then
    echo "[prune-worktrees] $(date '+%F %T') skip (unique commits, not reachable elsewhere): $wt" >>"$log_file"
    echo "$repo|$wt" >>"$tmp_file"
    continue
  fi

  git -C "$repo" worktree unlock "$wt" >/dev/null 2>&1
  if git -C "$repo" worktree remove "$wt" >>"$log_file" 2>&1; then
    git -C "$repo" branch -D "$branch" >>"$log_file" 2>&1
    echo "[prune-worktrees] $(date '+%F %T') removed: $wt" >>"$log_file"
  else
    echo "[prune-worktrees] $(date '+%F %T') FAILED to remove (left in place): $wt" >>"$log_file"
    echo "$repo|$wt" >>"$tmp_file"
  fi
done <"$state_file"

mv "$tmp_file" "$state_file"

cut -d'|' -f1 "$state_file" 2>/dev/null | sort -u | while read -r repo_dir; do
  [ -n "$repo_dir" ] && git -C "$repo_dir" worktree prune >/dev/null 2>&1
done

exit 0
