#!/bin/bash
# claude-code-grid installer — idempotent; run it again any time.
#
# Expects the repo to live at ~/dev/claude-code-grid (configs reference that
# path directly, same convention as claude-code-cash-register).
set -u

GRID_DIR="$HOME/dev/claude-code-grid"
GRID_CONFIG="$HOME/.config/claude-code-grid"
say() { printf '\033[1;36m▸ %s\033[0m\n' "$*"; }

if [ "$(cd "$(dirname "$0")" && pwd)" != "$GRID_DIR" ]; then
  echo "⚠ repo should live at $GRID_DIR (configs reference that path)" >&2
fi

# 1. Dependencies ------------------------------------------------------------
missing=""
for dep in tmux fzf jq; do command -v "$dep" >/dev/null 2>&1 || missing="$missing $dep"; done
command -v terminal-notifier >/dev/null 2>&1 || missing="$missing terminal-notifier"
if [ -n "$missing" ]; then
  say "installing missing deps:$missing"
  brew install $missing
fi

# 2. Config home + ntfy template ---------------------------------------------
mkdir -p "$GRID_CONFIG"
if [ ! -f "$GRID_CONFIG/ntfy.conf" ]; then
  topic="claude-$(whoami | tr '[:upper:].' '[:lower:]-')-$(openssl rand -hex 6)"
  sed "s|^NTFY_URL=\"\"|NTFY_URL=\"https://ntfy.sh/$topic\"|" \
    "$GRID_DIR/config/ntfy.conf.template" > "$GRID_CONFIG/ntfy.conf"
  say "created $GRID_CONFIG/ntfy.conf with topic: $topic"
  say "→ subscribe to that topic in the ntfy app to get phone pushes"
fi

# 3. Pinned tmux plugins ------------------------------------------------------
mkdir -p "$HOME/.tmux/plugins"
if [ ! -d "$HOME/.tmux/plugins/tmux-resurrect" ]; then
  git clone -q --depth 50 https://github.com/tmux-plugins/tmux-resurrect "$HOME/.tmux/plugins/tmux-resurrect"
  git -C "$HOME/.tmux/plugins/tmux-resurrect" fetch -q --tags --depth 50
  git -C "$HOME/.tmux/plugins/tmux-resurrect" checkout -q v4.0.0
  say "installed tmux-resurrect v4.0.0"
fi
if [ ! -d "$HOME/.tmux/plugins/tmux-continuum" ]; then
  git clone -q --depth 50 https://github.com/tmux-plugins/tmux-continuum "$HOME/.tmux/plugins/tmux-continuum"
  git -C "$HOME/.tmux/plugins/tmux-continuum" fetch -q --tags --depth 50
  git -C "$HOME/.tmux/plugins/tmux-continuum" checkout -q v3.1.0
  say "installed tmux-continuum v3.1.0 (master has shipped broken; stay pinned)"
fi

# 4. Shell + tmux wiring ------------------------------------------------------
zline="source $GRID_DIR/zsh/grid.zsh"
if ! grep -qF "$zline" "$HOME/.zshrc" 2>/dev/null; then
  printf '\n# claude-code-grid (override GRID_*_ROOT/_PROFILE vars before this line)\n%s\n' "$zline" >> "$HOME/.zshrc"
  say "added grid.zsh source line to ~/.zshrc"
fi

tline="source-file $GRID_DIR/tmux/grid.tmux.conf"
touch "$HOME/.tmux.conf"
if ! grep -qF "$tline" "$HOME/.tmux.conf"; then
  printf '\n# claude-code-grid\n%s\n' "$tline" >> "$HOME/.tmux.conf"
  say "added grid.tmux.conf source line to ~/.tmux.conf"
fi

# 5. Seed the prompt library --------------------------------------------------
# prefix+p / prefix+P pick from these. Filename is what you see in the picker;
# contents are what gets sent. Only written if absent, so edits survive
# re-running the installer.
mkdir -p "$GRID_CONFIG/prompts"
seed_prompt() {
  [ -f "$GRID_CONFIG/prompts/$1" ] || printf '%s\n' "$2" > "$GRID_CONFIG/prompts/$1"
}
seed_prompt commit-and-push "Commit the current changes with a conventional-commit message, then push."
seed_prompt run-tests       "Run the test suite. If anything fails, fix it and re-run until it's green."
seed_prompt review-branch   "Review the diff on this branch against main for bugs, missing error handling, and anything that would fail in production. Don't fix anything yet — just report."
seed_prompt open-pr         "Push the branch and open a PR with a summary of what changed and why."
seed_prompt where-are-we    "Summarise what you've changed so far, what's still unfinished, and anything you're blocked on."

# 6. Claude Code hooks --------------------------------------------------------
# The grid needs seven hook events wired per profile — enough that hand-merging
# JSON is a reliable source of typos — so do it here with jq. Idempotent: an
# event already pointing at the same script is left alone, and every other
# hook in the file is preserved untouched.
# Tilde form, matching what the README documents and what an existing install
# already has in its settings.json — see the dedupe note in `ensure` below.
grid_hook() { printf '%s' "~/dev/claude-code-grid/scripts/$1"; }

wire_hooks() {
  profile="$1"
  dir="$HOME/.claude-$profile"
  [ -d "$dir" ] || return 0
  f="$dir/settings.json"
  [ -f "$f" ] || echo '{}' > "$f"

  cp "$f" "$f.bak-grid-$(date +%Y%m%d%H%M%S)"

  jq \
    --arg notify "$(grid_hook claude-notify.sh)" \
    --arg state  "$(grid_hook pane-state.sh)" \
    --arg board  "$(grid_hook grid-board.sh)" '
    # Dedupe on the repo-relative tail ("claude-code-grid/scripts/x.sh args")
    # rather than the whole string: an earlier install may have written the
    # tilde form while a hand-edit used the absolute one, and an exact-match
    # test would happily add the second copy — which means two notification
    # banners per event, forever.
    def ensure($event; $cmd):
      ($cmd | ltrimstr("~/dev/")) as $tail
      | .hooks //= {}
      | .hooks[$event] //= []
      | if [ .hooks[$event][]?.hooks[]?.command | select(contains($tail)) ] | length > 0
        then .
        else .hooks[$event] += [ { "hooks": [ { "type": "command", "command": $cmd } ] } ]
        end;

    # Pane state: what each pane is doing, drawn on its border.
      ensure("SessionStart";     $state + " idle")
    | ensure("UserPromptSubmit"; $state + " working")
    | ensure("PreToolUse";       $state + " working")
    | ensure("Notification";     $state + " waiting")
    | ensure("Stop";             $state + " done")
    | ensure("SessionEnd";       $state + " gone")

    # Desktop + phone notifications.
    | ensure("Notification";  $notify)
    | ensure("Stop";          $notify)
    | ensure("StopFailure";   $notify)

    # Shared cross-repo board, injected into every session at startup.
    | ensure("SessionStart"; $board + " inject")
  ' "$f" > "$f.tmp" && mv "$f.tmp" "$f" && say "wired grid hooks into $f"
}

for p in "${GRID_PERSONAL_PROFILE:-personal}" "${GRID_WORK_PROFILE:-work}"; do
  wire_hooks "$p"
done

cat <<'EOF'

── done ─────────────────────────────────────────────────────────────────────
  exec zsh && pdev        (or wdev)

Inside the grid:
  prefix+n  jump to the pane that wants you    prefix+g  git status, all repos
  prefix+m  mark panes    prefix+p/P  send a saved prompt
  prefix+a  add a repo    prefix+X  drop one   prefix+B  shared board
EOF
