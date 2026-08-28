#!/bin/zsh
# start-grid.sh [--session S] [--root DIR] [--profile P] [--layout L]
#               <repo-rel-path>...
#
# The engine: builds a tmux session with one window, one pane per repo, each
# running Claude Code under ~/.claude-<profile>. The panes are laid out in the
# session's chosen arrangement — tiled, unless --layout or a previous choice
# says otherwise. Worktree tracking state goes to
# $GRID_CONFIG/<session>.worktrees so the prune machinery (prune-dispatch.sh
# on session close, plus the sweep below on start) applies per session.
#
# The grid's configuration (root, profile, state file) is stashed on the tmux
# session as user options, so grid-add.sh and grid-restore.sh can build a
# pane that matches the rest of the grid without being handed the arguments
# again — and so it survives this script exiting.
#
# GRID_CMD env override exists for tests only: replaces the claude_tracked
# launch line typed into each pane.
set -u

SCRIPT_DIR="${0:A:h}"
. "$SCRIPT_DIR/grid-lib.sh"

SESSION=personal
ROOT=~/dev
PROFILE=personal
LAYOUT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --session) SESSION="$2"; shift 2 ;;
    --root)    ROOT="${2/#\~/$HOME}"; shift 2 ;;
    --profile) PROFILE="$2"; shift 2 ;;
    # Takes either name: `columns` or tmux's own `even-horizontal`. Anything
    # else is rejected here rather than silently tiling later.
    --layout)
      LAYOUT=$(grid_layout_name "$2") || {
        echo "start-grid: unknown layout '$2' (try: $GRID_LAYOUTS)" >&2; exit 1; }
      shift 2 ;;
    *) break ;;
  esac
done

STATE="$GRID_CONFIG/$SESSION.worktrees"
BOARD="$GRID_CONFIG/$SESSION.board.md"

if [ $# -eq 0 ]; then
  echo "usage: start-grid.sh [--session S] [--root DIR] [--profile P] [--layout L] <repo-rel-path>..." >&2
  exit 1
fi

if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "session '$SESSION' already exists — attaching (kill it first to rebuild)" >&2
  if [ -z "${TMUX:-}" ]; then exec tmux attach-session -t "$SESSION"
  else exec tmux switch-client -t "$SESSION"; fi
fi

# Sweep any worktrees left over from an ungraceful exit (kill-server,
# terminal quit, reboot) before building the new grid.
"$SCRIPT_DIR/prune-worktrees.sh" "$STATE"

# Each launch starts the shared board fresh: it's a scratchpad for what the
# sessions are doing to each other *right now*, and yesterday's notes read as
# fact when they're actually stale.
mkdir -p "$GRID_CONFIG"
: > "$BOARD"

# The session options below are the fast path, but tmux user options don't
# survive a reboot — resurrect restores layout and paths, nothing else. This
# file is what grid-restore.sh reads to rebuild them.
{
  echo "GRID_ROOT=$ROOT"
  echo "GRID_PROFILE=$PROFILE"
} > "$GRID_CONFIG/$SESSION.env"

tmux new-session -d -s "$SESSION" -n repos -c "$ROOT"

tmux set-option -t "$SESSION" @grid_root    "$ROOT"
tmux set-option -t "$SESSION" @grid_profile "$PROFILE"
tmux set-option -t "$SESSION" @grid_state   "$STATE"
tmux set-option -t "$SESSION" @grid_board   "$BOARD"

# Pane arrangement: --layout wins and is remembered, otherwise the session
# picks up whatever it was last set to (grid_layout reads the saved file), and
# a grid that has never been told anything tiles as it always has.
if [ -n "$LAYOUT" ]; then
  mkdir -p "$GRID_CONFIG"
  printf '%s\n' "$LAYOUT" > "$GRID_CONFIG/layout.$SESSION"
else
  LAYOUT=$(grid_layout "$SESSION")
fi
tmux set-option -t "$SESSION" @grid_layout "$LAYOUT"

i=0
for rel in "$@"; do
  repo="$ROOT/$rel"
  if [ ! -d "$repo" ]; then
    echo "skipping $rel — no such directory" >&2
    continue
  fi
  if [ "$i" -gt 0 ]; then
    tmux split-window -t "$SESSION:0" -c "$ROOT"
    grid_apply_layout "$SESSION"
  fi
  "$SCRIPT_DIR/grid-pane.sh" "$SESSION:0.$i" "$repo" "$(grid_label "$rel")" \
    "$(grid_color "$i")" "$STATE" "$PROFILE"
  i=$((i + 1))
done

grid_apply_layout "$SESSION"
tmux select-pane -t "$SESSION:0.0"
if [ -z "${TMUX:-}" ]; then
  exec tmux -u attach-session -t "$SESSION"
else
  exec tmux -u switch-client -t "$SESSION"
fi
