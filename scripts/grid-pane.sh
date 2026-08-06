#!/bin/bash
# grid-pane.sh <pane> <repo-dir> <label> <color> <state-file> <profile> [resume]
#
# Dresses one already-existing tmux pane as a grid pane and launches Claude in
# it. Shared by start-grid.sh (building the grid), grid-add.sh (appending a
# repo mid-session) and grid-restore.sh (rebuilding after a reboot), so all
# three produce panes that look and behave identically.
#
# `resume` as the 7th argument launches with --continue, picking the previous
# conversation back up instead of starting cold.
#
# GRID_CMD env override exists for tests only: replaces the claude_tracked
# launch line typed into the pane.
set -u

pane="$1" repo="$2" label="$3" color="$4" state_file="$5" profile="$6" resume="${7:-}"

# The README's first gotcha: `set-option -p` without `-t` targets the
# window's *active* pane, not the one we mean.
tmux set-option -p -t "$pane" @repo        "$label"
tmux set-option -p -t "$pane" @repo_color  "$color"
tmux set-option -p -t "$pane" @state       idle
tmux set-option -p -t "$pane" @state_since "$(date +%s)"
tmux set-option -p -t "$pane" pane-border-style "fg=colour238"

tmux send-keys -t "$pane" "clear" C-m
tmux send-keys -t "$pane" "cd $repo" C-m
tmux send-keys -t "$pane" \
  "${GRID_CMD:-claude_tracked $repo \"$label\" $state_file $profile $resume}" C-m
