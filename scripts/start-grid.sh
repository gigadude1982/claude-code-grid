#!/bin/zsh
# start-grid.sh [--session S] [--root DIR] [--profile P] <repo-rel-path>...
#
# The engine: builds a tmux session with one window, tiled layout, one pane
# per repo, each running Claude Code under ~/.claude-<profile>. Worktree
# tracking state goes to $GRID_CONFIG/<session>.worktrees so the prune
# machinery (prune-dispatch.sh on session close, plus the sweep below on
# start) applies per session.
#
# GRID_CMD env override exists for tests only: replaces the claude_tracked
# launch line typed into each pane.
set -u

SCRIPT_DIR="${0:A:h}"
GRID_CONFIG="${GRID_CONFIG:-$HOME/.config/claude-code-grid}"

SESSION=personal
ROOT=~/dev
PROFILE=personal
PALETTE=(colour45 colour141 colour214 colour114 colour203 colour81 colour178 colour135)

while [ $# -gt 0 ]; do
  case "$1" in
    --session) SESSION="$2"; shift 2 ;;
    --root)    ROOT="${2/#\~/$HOME}"; shift 2 ;;
    --profile) PROFILE="$2"; shift 2 ;;
    *) break ;;
  esac
done

STATE="$GRID_CONFIG/$SESSION.worktrees"

if [ $# -eq 0 ]; then
  echo "usage: start-grid.sh [--session S] [--root DIR] [--profile P] <repo-rel-path>..." >&2
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

tmux new-session -d -s "$SESSION" -n repos -c "$ROOT"

i=0
for rel in "$@"; do
  repo="$ROOT/$rel"
  label="${rel//\//-}"
  color="${PALETTE[$((i % ${#PALETTE[@]} + 1))]}"
  if [ ! -d "$repo" ]; then
    echo "skipping $rel — no such directory" >&2
    continue
  fi
  if [ "$i" -gt 0 ]; then
    tmux split-window -t "$SESSION:0" -c "$ROOT"
    tmux select-layout -t "$SESSION:0" tiled
  fi
  pane="$SESSION:0.$i"
  tmux set-option -p -t "$pane" @repo "$label"
  tmux set-option -p -t "$pane" @repo_color "$color"
  tmux send-keys -t "$pane" "clear" C-m
  tmux send-keys -t "$pane" "cd $repo" C-m
  tmux send-keys -t "$pane" "${GRID_CMD:-claude_tracked $repo \"$label\" $STATE $PROFILE}" C-m
  i=$((i + 1))
done

tmux select-layout -t "$SESSION:0" tiled
tmux select-pane -t "$SESSION:0.0"
if [ -z "${TMUX:-}" ]; then
  exec tmux -u attach-session -t "$SESSION"
else
  exec tmux -u switch-client -t "$SESSION"
fi
