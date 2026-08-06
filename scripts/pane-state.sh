#!/bin/bash
# pane-state.sh <state> — Claude Code hook → per-pane grid state.
#
# Records what the Claude session in *this* pane is doing, so the grid can be
# read as a dashboard instead of four scrollbacks. Wire one line per event
# into each profile's settings.json (see README):
#
#   SessionStart     pane-state.sh idle
#   UserPromptSubmit pane-state.sh working
#   PreToolUse       pane-state.sh working
#   Notification     pane-state.sh waiting
#   Stop             pane-state.sh done
#   SessionEnd       pane-state.sh gone
#
# The state is passed as argv rather than parsed from the hook's stdin JSON:
# PreToolUse fires constantly, and skipping the read + jq keeps this to a
# single tmux call. Nothing is read from stdin at all, which is normal for
# command hooks.
#
# Which pane? $TMUX_PANE, inherited down the process chain tmux → shell →
# claude → hook. Outside tmux (or outside a grid pane) this is a no-op.
#
# State lands in pane options read by pane-border.sh / grid-next.sh /
# grid-rollup.sh:
#   @state        idle | working | waiting | done | gone
#   @state_since  epoch seconds of the last transition
#
# Hook contract: never block, never fail — always exit 0.

state="${1:-idle}"

[ -n "${TMUX_PANE:-}" ] || exit 0
command -v tmux >/dev/null 2>&1 || exit 0

# Only grid panes carry @repo; leave ordinary tmux panes alone so a stray
# hook in a non-grid session can't start restyling borders.
repo=$(tmux display-message -p -t "$TMUX_PANE" '#{@repo}' 2>/dev/null) || exit 0
[ -n "$repo" ] || exit 0

prev=$(tmux display-message -p -t "$TMUX_PANE" '#{@state}' 2>/dev/null)

# Don't reset the clock on repeated same-state events — PreToolUse fires once
# per tool call, and "working 4m" is only useful if it measures the whole
# stretch of work rather than the gap since the last Bash command.
changed=0
if [ "$prev" != "$state" ]; then
  changed=1
  tmux set-option -p -t "$TMUX_PANE" @state "$state" 2>/dev/null
  tmux set-option -p -t "$TMUX_PANE" @state_since "$(date +%s)" 2>/dev/null
fi

# Tint the pane's frame so a pane that wants you is obvious from across the
# room, without having to read the label. Set on every event (not just
# transitions) so a manually-cleared style heals itself.
case "$state" in
  waiting) style="fg=colour203,bold" ;;   # red — blocked on you
  done)    style="fg=colour114" ;;        # green — turn finished
  working) style="fg=colour240" ;;        # dim — busy, leave it alone
  *)       style="fg=colour238" ;;        # idle
esac
tmux set-option -p -t "$TMUX_PANE" pane-border-style "$style" 2>/dev/null

# Repaint immediately rather than waiting up to status-interval for the next
# border refresh — the whole point is that the change is instant. Only on an
# actual transition, though: PreToolUse fires once per tool call, and forcing
# a redraw on every one of those across four busy panes is a lot of screen
# churn to communicate nothing new.
[ "$changed" = "1" ] && tmux refresh-client -S 2>/dev/null

exit 0
