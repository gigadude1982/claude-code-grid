#!/bin/bash
# grid-notify-click.sh <pane_id> [term_program] — "click for more details"
# handler for a claude-notify.sh banner.
#
# terminal-notifier's -execute runs this when the user clicks the
# notification, long after the hook process (and its env) is gone — so
# claude-notify.sh bakes the pane id and $TERM_PROGRAM into the command at
# notify time and this script just acts on them: jump the tmux client to the
# pane that fired the notification and bring its terminal app forward. Since
# that pane is the live Claude Code session, "jump to it" already shows more
# detail than any static popup could.
#
# Best-effort like the rest of this hook: never blocks, never fails loudly.
set -u

pane="${1:-}"
term="${2:-}"

[ -n "$pane" ] && tmux switch-client -t "$pane" >/dev/null 2>&1

case "$term" in
  iTerm.app) app="iTerm2" ;;
  Apple_Terminal) app="Terminal" ;;
  vscode) app="Visual Studio Code" ;;
  *) app="Terminal" ;;
esac
osascript -e "tell application \"$app\" to activate" >/dev/null 2>&1

exit 0
