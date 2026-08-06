# grid-lib.sh — shared bits, sourced (not executed) by the grid scripts.
#
# Written to the POSIX subset on purpose: start-grid.sh runs under zsh while
# the helpers run under bash, and zsh's 1-based arrays vs bash's 0-based ones
# make a shared array a portability trap. A space-separated string plus awk
# indexing behaves identically in both.

GRID_CONFIG="${GRID_CONFIG:-$HOME/.config/claude-code-grid}"
GRID_PALETTE="colour45 colour141 colour214 colour114 colour203 colour81 colour178 colour135"

# grid_color <n> — the nth border color, wrapping around the palette.
grid_color() {
  echo "$GRID_PALETTE" | awk -v n="$1" '{ print $(n % NF + 1) }'
}

# grid_label <repo-rel-path> — pane label: nested paths flatten to a-b-c so
# the label survives being used in tmux formats and option values.
grid_label() {
  printf '%s' "$1" | tr '/' '-'
}

# grid_current_session — which grid are we acting on?
#
# Order matters. $GRID_SESSION is set explicitly by the key bindings, because
# a display-popup is not a pane: a script running inside one can't reliably
# ask "what pane am I in", and falling through to the attached client would
# make a popup opened over one grid act on whichever session the client
# happens to be showing. $TMUX_PANE covers scripts invoked from inside a pane
# (a shell, or a Claude session's Bash tool). The client is the last resort.
grid_current_session() {
  if [ -n "${GRID_SESSION:-}" ]; then
    printf '%s' "$GRID_SESSION"
  elif [ -n "${TMUX_PANE:-}" ]; then
    tmux display-message -p -t "$TMUX_PANE" '#{session_name}' 2>/dev/null
  else
    tmux display-message -p '#{session_name}' 2>/dev/null
  fi
}

# grid_current_pane — same reasoning, for the pane a command should act on.
grid_current_pane() {
  if [ -n "${GRID_PANE:-}" ]; then
    printf '%s' "$GRID_PANE"
  elif [ -n "${TMUX_PANE:-}" ]; then
    printf '%s' "$TMUX_PANE"
  else
    tmux display-message -p '#{pane_id}' 2>/dev/null
  fi
}

# grid_session_opt <session> <option> — read a session-scoped user option,
# empty if unset. start-grid.sh stashes the grid's root/profile/state file
# there so later commands (grid-add, grid-restore) can rebuild a pane without
# being told the configuration again.
grid_session_opt() {
  tmux show-options -v -t "$1" "$2" 2>/dev/null
}

# grid_has_conversation <repo-dir> <profile> — true when Claude has a stored
# conversation for this directory, i.e. `claude --continue` will work rather
# than erroring out. Claude encodes a project dir by replacing every
# non-alphanumeric run with '-', so /Users/x/dev/foo → -Users-x-dev-foo.
grid_has_conversation() {
  _dir=$(printf '%s' "$1" | sed 's/[^a-zA-Z0-9]/-/g')
  [ -d "$HOME/.claude-$2/projects/$_dir" ]
}
