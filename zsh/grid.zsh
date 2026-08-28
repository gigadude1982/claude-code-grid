# claude-code-grid — zsh functions. Source this from ~/.zshrc:
#
#   export GRID_WORK_ROOT=~/bounteous   # optional overrides, BEFORE the source
#   source ~/dev/claude-code-grid/zsh/grid.zsh
#
# Commands (per grid: p* = personal account/repos, w* = work):
#   pdev / wdev            launch (or reattach) the grid with your last-picked
#                          repo set; opens the picker if you've never picked
#   pdev-pick / wdev-pick  fzf multi-select which repos get panes (tab =
#                          toggle, enter = launch); selection is remembered.
#                          Entries ending in '/' are folders holding two or
#                          more repos — pick one to put a single pane at the
#                          parent (shipvane/ rather than shipvane/engine).
#                          With the grid already up, picks become panes right
#                          away rather than waiting for the next launch
#   pdev-stop / wdev-stop  tear down + safe-prune auto-created worktrees
#   pdev-sweep / wdev-sweep  safe-prune EVERY worktree sitting on disk for
#                          the grid's repos, tracked or not (run any time,
#                          session up or down — doesn't touch tmux)
#
# Inside a running grid (also bound to prefix keys — see tmux/grid.tmux.conf):
#   grid-add [repo]        give another repo a pane without rebuilding
#   grid-drop              close the current pane's repo
#   grid-layout [name]     tiled / columns / rows / main-left / main-top;
#                          bare cycles, and the choice sticks per session
#   grid-note "<text>"     leave a note the other panes' sessions will read
#   grid-board             show the shared board

: ${GRID_DIR:=$HOME/dev/claude-code-grid}
: ${GRID_CONFIG:=$HOME/.config/claude-code-grid}
: ${GRID_PERSONAL_ROOT:=$HOME/dev}
: ${GRID_PERSONAL_PROFILE:=personal}
: ${GRID_WORK_ROOT:=$HOME/work}
: ${GRID_WORK_PROFILE:=work}

# Splash rendered in each pane before claude launches: a full-pane ASCII art
# piece (scripts/splash.sh) chosen by hashing the repo name — so a repo keeps
# the same art across launches and becomes recognisable at a glance — tinted
# to match the pane's border color, with the repo/branch line beneath.
# Visible during claude's startup delay and again whenever claude exits
# (claude runs on the alternate screen). Falls back to just the repo/branch
# line if the script is missing.
claude_splash() {
  local label="$1" branch
  if [ -r "$GRID_DIR/scripts/splash.sh" ]; then
    zsh "$GRID_DIR/scripts/splash.sh" "$label" "${COLUMNS:-}" "${LINES:-}"
    return
  fi
  branch=$(git branch --show-current 2>/dev/null)
  printf '\033[1;36m▸ %s\033[0m' "$label"
  [ -n "$branch" ] && printf '  \033[2;37m(%s)\033[0m' "$branch"
  printf '\n'
}

# Runs Claude Code in $1 under ~/.claude-<profile>, tracking any git
# worktree it auto-creates (e.g. via a `claude --worktree` wrapper) so
# prune-worktrees.sh can safely clean it up later. The tracker records the
# worktree as soon as it appears rather than waiting for claude to exit — if
# the pane gets killed outright, teardown still knows what to check.
#
# $5 = "resume" launches with --continue (grid-restore.sh passes this after a
# reboot, and only when it has confirmed a stored conversation exists — bare
# --continue errors out when there isn't one).
claude_tracked() {
  local repo="$1" label="$2" state_file="$3" profile="${4:-personal}" resume="${5:-}"
  claude_splash "$label"
  (zsh "$GRID_DIR/scripts/track-worktree.sh" "$repo" "$state_file" &>/dev/null &)
  if [ "$resume" = resume ]; then
    CLAUDE_CONFIG_DIR="$HOME/.claude-$profile" claude --continue
  else
    CLAUDE_CONFIG_DIR="$HOME/.claude-$profile" claude
  fi
}

# Discovery lives in grid-lib.sh so this picker and the one in grid-add.sh
# (prefix+a, inside a running grid) offer the same list — repos, plus folders
# holding two or more of them. Sourced in a subshell rather than at file scope
# to keep the interactive shell's namespace to the p*/w* commands.
_grid_repo_list() { ( . "$GRID_DIR/scripts/grid-lib.sh"; grid_repo_list "$1" ) }

_grid_pick() {
  local session="$1" root="$2" profile="$3" repos
  repos=$(_grid_repo_list "$root" \
    | fzf -m --prompt="$session> " \
          --header='tab = multi-select · enter = launch · trailing / = folder of repos, one pane')
  [ -z "$repos" ] && return 0
  # Trailing slashes are the picker's parent-folder marker, not path segments.
  repos=$(print -r -- "$repos" | sed 's|/$||')

  # A pick against a *running* grid used to go nowhere: start-grid.sh won't
  # rebuild over a live session (it attaches instead), so the selection was
  # written to <session>.repos and only became panes on the next launch —
  # from the picker's seat, "I chose a repo and nothing happened". Hand the
  # new picks to the running grid instead, which is exactly what grid-add is
  # for, and leave the conversations already on screen alone.
  #
  # Deselecting doesn't close anything. A pane holds a live conversation, and
  # silently killing three of them because the fourth was what you came for
  # is not a trade a picker gets to make — prefix+X drops one deliberately.
  if tmux has-session -t "$session" 2>/dev/null; then
    local rel label present added=0 skipped=0
    present=$(tmux list-panes -t "$session:0" -F '#{@repo}' 2>/dev/null)
    for rel in ${(f)repos}; do
      label=${rel//\//-}
      if print -r -- "$present" | grep -qxF -- "$label"; then
        skipped=$((skipped + 1))
        continue
      fi
      GRID_SESSION="$session" "$GRID_DIR/scripts/grid-add.sh" "$rel" && added=$((added + 1))
    done
    print -r -- "$session is already running: added $added pane(s), $skipped already there; existing panes kept (prefix+X drops one)"
    if [ -z "${TMUX:-}" ]; then tmux attach -t "$session"; else tmux switch-client -t "$session"; fi
    return
  fi

  mkdir -p "$GRID_CONFIG"
  print -r -- "$repos" > "$GRID_CONFIG/$session.repos"
  "$GRID_DIR/scripts/start-grid.sh" --session "$session" --root "$root" --profile "$profile" ${=repos}
}

_grid_launch() {
  local session="$1" root="$2" profile="$3"
  if tmux has-session -t "$session" 2>/dev/null; then
    if [ -z "$TMUX" ]; then tmux attach -t "$session"; else tmux switch-client -t "$session"; fi
    return
  fi
  local f="$GRID_CONFIG/$session.repos"
  if [ -s "$f" ]; then
    "$GRID_DIR/scripts/start-grid.sh" --session "$session" --root "$root" --profile "$profile" ${=$(cat "$f")}
  else
    _grid_pick "$session" "$root" "$profile"
  fi
}

_grid_stop() {
  local session="$1"
  tmux kill-session -t "$session" 2>/dev/null
  sleep 1
  "$GRID_DIR/scripts/prune-worktrees.sh" "$GRID_CONFIG/$session.worktrees"
  echo "$session grid stopped; prune log: $GRID_CONFIG/$session.log"
}

pdev()       { _grid_launch personal "$GRID_PERSONAL_ROOT" "$GRID_PERSONAL_PROFILE"; }
pdev-pick()  { _grid_pick   personal "$GRID_PERSONAL_ROOT" "$GRID_PERSONAL_PROFILE"; }
pdev-stop()  { _grid_stop   personal; }
pdev-sweep() { "$GRID_DIR/scripts/grid-sweep.sh" personal; }
wdev()       { _grid_launch work "$GRID_WORK_ROOT" "$GRID_WORK_PROFILE"; }
wdev-pick()  { _grid_pick   work "$GRID_WORK_ROOT" "$GRID_WORK_PROFILE"; }
wdev-stop()  { _grid_stop   work; }
wdev-sweep() { "$GRID_DIR/scripts/grid-sweep.sh" work; }

# In-grid commands. These read the grid's configuration off the tmux session,
# so they only mean anything from inside a pane — which is also the only
# place you'd type them.
grid-add()   { "$GRID_DIR/scripts/grid-add.sh" "$@"; }
grid-drop()  { "$GRID_DIR/scripts/grid-drop.sh" "$@"; }
# No argument cycles, like prefix+Space; a name (tiled / columns / rows /
# main-left / main-top) goes straight there.
grid-layout() {
  if [ $# -eq 0 ]; then "$GRID_DIR/scripts/grid-layout.sh" next
  else "$GRID_DIR/scripts/grid-layout.sh" apply "$@"; fi
}
grid-note()  { "$GRID_DIR/scripts/grid-board.sh" note "$@"; }
grid-board() { "$GRID_DIR/scripts/grid-board.sh" show; }
