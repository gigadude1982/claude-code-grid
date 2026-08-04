#!/bin/bash
# prune-dispatch.sh <closed-session-name>
#
# tmux session-closed hook target (see tmux/grid.tmux.conf). Any closed
# session that has a worktree state file (personal, work, ...) gets its safe
# prune; everything else is a no-op.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GRID_CONFIG="${GRID_CONFIG:-$HOME/.config/claude-code-grid}"

name="$1"
[ -n "$name" ] || exit 0
state="$GRID_CONFIG/$name.worktrees"
[ -f "$state" ] && exec "$SCRIPT_DIR/prune-worktrees.sh" "$state"
exit 0
