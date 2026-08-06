#!/bin/bash
# grid-prompt.sh <current|marked> [session] — send a saved prompt to panes.
#
#   prefix+p   pick a prompt, send it to the pane you're on
#   prefix+P   pick a prompt, send it to every *marked* pane (prefix+m),
#              or to all grid panes when nothing is marked
#
# Prompts are plain files in $GRID_CONFIG/prompts/. The ones you type into
# four panes a day ("run the tests and fix what fails", "commit and push with
# a conventional message") are exactly the ones worth not retyping.
#
# Text is delivered with paste-buffer -p — a *bracketed* paste — rather than
# send-keys. Without bracketing, a multi-line prompt's first newline submits
# the message and the remaining lines land as separate turns.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/grid-lib.sh"

scope="${1:-current}"
session="${2:-}"
[ -n "$session" ] || session=$(grid_current_session)

dir="$GRID_CONFIG/prompts"
if [ ! -d "$dir" ] || [ -z "$(ls -A "$dir" 2>/dev/null)" ]; then
  printf 'No saved prompts yet.\n\nDrop plain text files in:\n  %s\n\n' "$dir"
  printf 'The filename is what you pick from; the contents are what gets sent.\n\n'
  printf '\033[2mpress any key\033[0m'
  read -rsn1
  exit 0
fi

name=$(ls -1 "$dir" | fzf --prompt='prompt> ' \
  --header="enter = send to $scope pane(s)" \
  --preview="cat '$dir'/{}" --preview-window=right:60%:wrap)
[ -n "$name" ] || exit 0

text=$(cat "$dir/$name")
[ -n "$text" ] || exit 0

# Which panes? Marked set first; an empty mark set means "all of them",
# which matches how you'd say it out loud.
targets=""
case "$scope" in
  marked)
    targets=$(tmux list-panes -t "$session:0" -F '#{@marked} #{@repo} #{pane_id}' 2>/dev/null \
      | awk '$1 == "1" && $2 != "" { print $3 }')
    if [ -z "$targets" ]; then
      targets=$(tmux list-panes -t "$session:0" -F '#{@repo} #{pane_id}' 2>/dev/null \
        | awk '$1 != "" { print $2 }')
    fi
    ;;
  *)
    targets=$(grid_current_pane)
    ;;
esac
[ -n "$targets" ] || exit 0

n=0
for pane in $targets; do
  tmux set-buffer -b grid-prompt -- "$text"
  tmux paste-buffer -b grid-prompt -d -p -t "$pane"
  tmux send-keys -t "$pane" Enter
  n=$((n + 1))
done

tmux display-message "grid: sent '$name' to $n pane(s)"
