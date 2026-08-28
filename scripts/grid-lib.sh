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

# ── Pane arrangement ─────────────────────────────────────────────────────────
# The grid is tiled by default, but a two-pane grid tiles into stacked rows —
# fine for reading one long reply, wrong when you want two conversations side
# by side. @grid_layout (session-scoped, saved to $GRID_CONFIG/layout.<session>)
# is the choice, and every place that reshapes the window applies it instead of
# hardcoding `tiled`.
#
# The names are tmux's, and they are a trap worth naming: "even-horizontal"
# arranges panes ALONG a horizontal axis — side-by-side columns, which is what
# everyone else calls a *vertical* split. The friendly labels below exist so
# nothing in the UI has to say "horizontal" and mean the opposite.
GRID_LAYOUTS="tiled even-horizontal even-vertical main-vertical main-horizontal"

# grid_layout_label <tmux-layout> — what the menus and options screen call it.
grid_layout_label() {
  case "$1" in
    even-horizontal) printf 'columns' ;;
    even-vertical)   printf 'rows' ;;
    main-vertical)   printf 'main-left' ;;
    main-horizontal) printf 'main-top' ;;
    *)               printf '%s' "$1" ;;
  esac
}

# grid_layout_desc <tmux-layout> — the one-line "what this will look like".
grid_layout_desc() {
  case "$1" in
    tiled)           printf 'an even grid' ;;
    even-horizontal) printf 'side by side' ;;
    even-vertical)   printf 'stacked top to bottom' ;;
    main-vertical)   printf 'one big pane left, the rest stacked right' ;;
    main-horizontal) printf 'one big pane on top, the rest in a row below' ;;
    *)               printf '' ;;
  esac
}

# grid_layout_name <word> — friendly label OR tmux name → tmux name. Fails on
# anything else, so a typo in a saved file or a --layout flag falls back to
# tiled instead of handing tmux a layout string it will reject.
grid_layout_name() {
  case "$1" in
    tiled)                    printf 'tiled' ;;
    columns|even-horizontal)  printf 'even-horizontal' ;;
    rows|even-vertical)       printf 'even-vertical' ;;
    main-left|main-vertical)  printf 'main-vertical' ;;
    main-top|main-horizontal) printf 'main-horizontal' ;;
    *) return 1 ;;
  esac
}

# grid_layout <session> — the session's layout, as tmux spells it.
#
# The option is the fast path; the file behind it is what carries the choice
# across a server restart, and reading it here is why no load hook is needed —
# whatever asks first gets the saved answer.
grid_layout() {
  _l=$(tmux show-options -v -t "$1" @grid_layout 2>/dev/null)
  [ -n "$_l" ] || _l=$(cat "$GRID_CONFIG/layout.$1" 2>/dev/null)
  grid_layout_name "${_l:-tiled}" || printf 'tiled'
}

# grid_apply_layout <session> — re-arrange the grid's window to that layout.
grid_apply_layout() {
  tmux select-layout -t "$1:0" "$(grid_layout "$1")" 2>/dev/null
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

# grid_repo_list <root> — everything the pickers can offer, one relative path
# per line: every git repo under <root>, plus any parent folder holding two or
# more of them, marked with a trailing '/'.
#
# The parent entries exist because a repo isn't always the unit of work. A
# folder like shipvane/ holding capstan, bridge and engine is one system worth
# one conversation's context; picking the three separately gives you three
# Claudes that each see a third of it. Selecting `shipvane/` puts a single
# pane at the parent instead, and everything downstream already copes — a
# non-repo pane just reports "(not a git repo)" in the prefix+g rollup and
# never grows a tracked worktree.
#
# Two is the threshold on purpose: a folder wrapping one repo is that repo
# with a directory in the way, and offering it would near-double the picker
# for nothing. A parent that is itself a repo is already listed as one, so
# it's never re-offered.
#
# Callers strip the trailing '/' before using the path — it's a display
# marker, and it would otherwise ride into the pane's @repo label as a dash.
grid_repo_list() {
  find "$1" -maxdepth 3 -name .git -not -path '*/worktrees/*' 2>/dev/null \
    | sed 's|/\.git$||' | sed "s|^$1/||" \
    | awk '
        { repo[++n] = $0; isrepo[$0] = 1
          p = $0
          while (sub("/[^/]+$", "", p)) kids[p]++ }
        END {
          for (i = 1; i <= n; i++) print repo[i]
          for (p in kids) if (kids[p] >= 2 && !(p in isrepo)) print p "/"
        }' \
    | sort
}
