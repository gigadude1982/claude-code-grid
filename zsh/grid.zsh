# claude-code-grid — zsh functions. Source this from ~/.zshrc:
#
#   export GRID_WORK_ROOT=~/bounteous   # optional overrides, BEFORE the source
#   source ~/dev/claude-code-grid/zsh/grid.zsh
#
# Commands (per grid: p* = personal account/repos, w* = work):
#   pdev / wdev            launch (or reattach) the grid with your last-picked
#                          repo set; opens the picker if you've never picked
#   pdev-pick / wdev-pick  fzf multi-select which repos get panes (tab =
#                          toggle, enter = launch); selection is remembered
#   pdev-stop / wdev-stop  tear down + safe-prune auto-created worktrees

: ${GRID_DIR:=$HOME/dev/claude-code-grid}
: ${GRID_CONFIG:=$HOME/.config/claude-code-grid}
: ${GRID_PERSONAL_ROOT:=$HOME/dev}
: ${GRID_PERSONAL_PROFILE:=personal}
: ${GRID_WORK_ROOT:=$HOME/work}
: ${GRID_WORK_PROFILE:=work}

# Startup banner printed at the top of each pane before claude launches, so
# it's obvious which repo/branch a pane is in even mid-scrollback.
claude_splash() {
  local label="$1" branch
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
claude_tracked() {
  local repo="$1" label="$2" state_file="$3" profile="${4:-personal}"
  claude_splash "$label"
  (zsh "$GRID_DIR/scripts/track-worktree.sh" "$repo" "$state_file" &>/dev/null &)
  CLAUDE_CONFIG_DIR="$HOME/.claude-$profile" claude
}

_grid_pick() {
  local session="$1" root="$2" profile="$3" repos
  repos=$(find "$root" -maxdepth 3 -name .git -not -path '*/worktrees/*' 2>/dev/null \
    | sed 's|/\.git$||' | sed "s|$root/||" | sort \
    | fzf -m --prompt="$session> " --header='tab = multi-select · enter = launch grid')
  [ -z "$repos" ] && return 0
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

pdev()      { _grid_launch personal "$GRID_PERSONAL_ROOT" "$GRID_PERSONAL_PROFILE"; }
pdev-pick() { _grid_pick   personal "$GRID_PERSONAL_ROOT" "$GRID_PERSONAL_PROFILE"; }
pdev-stop() { _grid_stop   personal; }
wdev()      { _grid_launch work "$GRID_WORK_ROOT" "$GRID_WORK_PROFILE"; }
wdev-pick() { _grid_pick   work "$GRID_WORK_ROOT" "$GRID_WORK_PROFILE"; }
wdev-stop() { _grid_stop   work; }
