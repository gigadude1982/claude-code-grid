#!/bin/bash
# grid-sweep.sh [session ...] — full-disk safe-prune of a grid's repos.
#
# prune-worktrees.sh only ever sees what's in <session>.worktrees, and that
# file only gets a line when a worktree is created *through* a tracked grid
# pane launch (track-worktree.sh). Anything else — a worktree that outlived
# a state-file reset, one made by `claude --worktree` outside the grid, one
# spun up by some other agent pipeline entirely — is invisible to it and
# just accumulates forever. grid-sweep.sh closes that gap: it walks every
# repo in <session>.repos, finds every worktree actually sitting in
# .claude/worktrees/ on disk (tracked or not), and runs the exact same
# safe-prune check (no uncommitted changes, HEAD reachable elsewhere) over
# all of them.
#
# Doesn't touch tmux at all — safe to run whether the session is up, down,
# or was never launched today. Survivors get folded back into
# <session>.worktrees so the ordinary teardown/launch sweeps know about them
# too, instead of this being the only thing that ever finds them again.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/grid-lib.sh"

sweep_session() {
  session="$1"
  repos_file="$GRID_CONFIG/$session.repos"
  env_file="$GRID_CONFIG/$session.env"
  state_file="$GRID_CONFIG/$session.worktrees"

  if [ ! -s "$repos_file" ]; then
    echo "grid-sweep: no $repos_file — skipping '$session'" >&2
    return 0
  fi

  root=""
  [ -f "$env_file" ] && root=$(awk -F= '$1 == "GRID_ROOT" { sub(/^[^=]*=/, ""); print }' "$env_file")
  if [ -z "$root" ]; then
    echo "grid-sweep: no GRID_ROOT for '$session' (launch it at least once first) — skipping" >&2
    return 0
  fi

  echo "== sweeping '$session' ($root) =="

  # Every other prune-worktrees.sh caller only ever fires with the session
  # down (pre-launch sweep, or after kill-session) — there's no live pane
  # sitting in the worktree it's about to judge. This one is explicitly meant
  # to run with the grid still up, so a worktree with no changes yet (a pane
  # just launched into a fresh branch) would look perfectly safe to remove
  # and vanish out from under that pane's cwd. Any pane's current path — or a
  # live pane's cwd inside it — is excluded from consideration, session-open
  # or not.
  live_paths=""
  if tmux has-session -t "$session" 2>/dev/null; then
    live_paths=$(tmux list-panes -t "$session:0" -F '#{pane_current_path}' 2>/dev/null)
  fi

  # Built in place — prune-worktrees.sh derives its log path from this
  # filename, so it has to actually be <session>.worktrees for the log to
  # land at <session>.log like every other caller. The script itself reads
  # this file then safely rewrites it (survivors only), same as any other
  # invocation, so building candidates here first and letting it take over
  # is no less safe than a temp file would be.
  mkdir -p "$GRID_CONFIG"
  candidates="$(mktemp)"
  [ -s "$state_file" ] && cat "$state_file" >> "$candidates"

  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    repo="$root/$rel"
    [ -d "$repo/.git" ] || [ -f "$repo/.git" ] || continue
    # Clear bookkeeping for worktrees whose directories are already gone —
    # safe, there's no data left to lose.
    git -C "$repo" worktree prune -v 2>&1 | sed "s|^|[git-prune $rel] |"
    for wt in "$repo"/.claude/worktrees/*/; do
      [ -d "$wt" ] || continue
      wt="${wt%/}"
      # Prefix match, not exact — a pane that cd'd into a subdirectory of
      # the worktree (e.g. `cd src/`) still counts as "live" here.
      if printf '%s\n' "$live_paths" | grep -qE "^${wt}(/|\$)"; then
        echo "[grid-sweep] $(date '+%F %T') skip (live pane cwd): $wt" >> "$GRID_CONFIG/$session.log"
        continue
      fi
      printf '%s|%s\n' "$repo" "$wt" >> "$candidates"
    done
  done < "$repos_file"

  sort -u "$candidates" -o "$candidates"

  if [ ! -s "$candidates" ]; then
    echo "grid-sweep: nothing to check for '$session'"
    rm -f "$candidates"
    return 0
  fi

  before=$(wc -l < "$candidates" | tr -d ' ')
  mv "$candidates" "$state_file"
  "$SCRIPT_DIR/prune-worktrees.sh" "$state_file"
  after=$(wc -l < "$state_file" | tr -d ' ')

  echo "grid-sweep: '$session' — removed $((before - after)), kept $after (see $GRID_CONFIG/$session.log)"
}

if [ $# -gt 0 ]; then
  for s in "$@"; do sweep_session "$s"; done
else
  for f in "$GRID_CONFIG"/*.repos; do
    [ -e "$f" ] || continue
    sweep_session "$(basename "$f" .repos)"
  done
fi

exit 0
