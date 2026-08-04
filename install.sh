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

# 5. Claude Code hooks (manual — settings.json is personal) -------------------
cat <<'EOF'

── manual step: notification hooks ──────────────────────────────────────────
Add to each Claude profile's settings.json (e.g. ~/.claude-personal/settings.json)
under "hooks" — merge with whatever is already there:

  "Notification": [{ "hooks": [
    { "type": "command", "command": "~/dev/claude-code-grid/scripts/claude-notify.sh" }
  ]}],
  "Stop": [{ "hooks": [
    { "type": "command", "command": "~/dev/claude-code-grid/scripts/claude-notify.sh" }
  ]}]

Then: exec zsh && pdev  (or wdev). Enjoy the grid.
EOF
