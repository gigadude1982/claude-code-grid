#!/bin/bash
# grid-color.sh menu <pane_id> | set <pane_id> <colour> — per-repo border color.
#
# The palette deals colors by pane index — stable, but impersonal. A
# right-click on a pane's border (or "repo colour…" in the pane menu) picks
# from the same palette, and the choice lands in $GRID_CONFIG/<session>.colors
# ("<label> <colour>" lines) where grid-pane.sh deals it again on the next
# launch or restore, beating the index.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/grid-lib.sh"

mode="${1:-}" pane="${2:-}"

# Only grid panes carry @repo; anything else has no label to key the file on.
label=$(tmux display-message -p -t "$pane" '#{@repo}' 2>/dev/null)
[ -n "$label" ] || exit 0
session=$(tmux display-message -p -t "$pane" '#{session_name}' 2>/dev/null)

case "$mode" in
  set)
    colour="$3"
    tmux set-option -p -t "$pane" @repo_color "$colour"
    mkdir -p "$GRID_CONFIG"
    f="$GRID_CONFIG/$session.colors"
    tmp="$f.tmp.$$"
    { [ -f "$f" ] && awk -v l="$label" '$1 != l' "$f"; printf '%s %s\n' "$label" "$colour"; } > "$tmp"
    mv "$tmp" "$f"
    tmux refresh-client -S 2>/dev/null
    ;;
  menu)
    # Explicit client for the same reason as grid-theme.sh: run-shell has none.
    client=$(tmux list-clients -F '#{client_name}' 2>/dev/null | head -1)
    names="blue purple orange green red cyan gold violet"
    i=1
    cmd=(tmux display-menu ${client:+-c "$client"} -T "#[align=centre]$label")
    for c in $GRID_PALETTE; do
      n=$(echo "$names" | awk -v i="$i" '{ print $i }')
      cmd+=("#[fg=$c]■ $n" "$i" "run-shell '$SCRIPT_DIR/grid-color.sh set $pane $c'")
      i=$((i + 1))
    done
    "${cmd[@]}"
    ;;
esac
