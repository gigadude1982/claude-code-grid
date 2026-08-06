#!/bin/bash
# grid-log.sh [session] — the worktree prune log, in a popup.
#
# Bound to prefix+L. This is where safe-prune records what it removed and,
# more usefully, what it *kept* and why — an unmerged commit or uncommitted
# change in an auto-created worktree is easy to forget about entirely once
# the pane is gone.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/grid-lib.sh"

session="${1:-}"
[ -n "$session" ] || session=$(grid_current_session)
log="$GRID_CONFIG/$session.log"

if [ ! -s "$log" ]; then
  printf '\033[2mno prune log yet for "%s" (%s)\033[0m\n\n' "$session" "$log"
  printf '\033[2mpress any key\033[0m'
  read -rsn1
  exit 0
fi

if command -v less >/dev/null 2>&1; then
  # +G opens at the end: the most recent teardown is the one you're asking about.
  less +G -R "$log"
else
  cat "$log"
  printf '\n\033[2mpress any key\033[0m'
  read -rsn1
fi
