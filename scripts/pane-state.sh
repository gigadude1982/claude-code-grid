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

command -v tmux >/dev/null 2>&1 || exit 0

# ── the active pane's frame ──────────────────────────────────────────────────
# pane-border-style is per-pane, but tmux paints whichever pane is *active*
# from the window's pane-active-border-style — one option for the whole
# window. Left alone it stays tmux's stock green, so the pane you are
# actually sitting in ignored its own state and wore the colour this grid
# uses to mean "finished its turn". Recompute it for the active pane here,
# and again on after-select-pane (see grid.tmux.conf) when focus moves.
#
# Neutral states take the theme's accent rather than the frame tint the
# inactive panes get: the active border doubles as the "you are here" marker,
# and dropping it to the same grey as everything else throws that away.
# waiting and done keep their semantic colours — that is the entire point.
active_border() { # active_border <pane-in-the-window>
  _win=$(tmux display-message -p -t "$1" '#{window_id}' 2>/dev/null) || return 0
  [ -n "$_win" ] || return 0

  # -t <window> resolves to that window's active pane.
  _apane=$(tmux display-message -p -t "$_win" '#{pane_id}' 2>/dev/null)
  [ -n "$_apane" ] || return 0

  # Not a grid pane? Hand the option back rather than leaving an ordinary
  # tmux window wearing a colour this script picked.
  if [ -z "$(tmux display-message -p -t "$_apane" '#{@repo}' 2>/dev/null)" ]; then
    tmux set-option -wu -t "$_win" pane-active-border-style 2>/dev/null
    return 0
  fi

  _astate=$(tmux display-message -p -t "$_apane" '#{@state}' 2>/dev/null)
  _accent=$(tmux show-options -v -t "$_apane" @theme_accent 2>/dev/null)
  [ -n "$_accent" ] || _accent=$(tmux show-options -gv @theme_accent 2>/dev/null)
  [ -n "$_accent" ] || _accent=colour45

  case "$_astate" in
    waiting) _style="fg=colour203,bold" ;;
    done)    _style="fg=colour114,bold" ;;
    *)       _style="fg=$_accent,bold" ;;
  esac
  tmux set-option -w -t "$_win" pane-active-border-style "$_style" 2>/dev/null
}

# after-select-pane fires as a tmux hook, not as a Claude hook, so there is no
# $TMUX_PANE to inherit — the binding passes the pane in instead.
if [ "$state" = "--active" ]; then
  [ -n "${2:-}" ] && active_border "$2"
  exit 0
fi

[ -n "${TMUX_PANE:-}" ] || exit 0

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
#
# Neutral states (working/idle) take the theme's frame tint — matrix runs a
# white frame — while waiting/done keep their semantic colors in every theme.
tint=$(tmux show-options -v -t "$TMUX_PANE" @theme_border 2>/dev/null)
[ -n "$tint" ] || tint=$(tmux show-options -gv @theme_border 2>/dev/null)
[ -n "$tint" ] || tint=colour240
case "$state" in
  waiting) style="fg=colour203,bold" ;;   # red — blocked on you
  done)    style="fg=colour114" ;;        # green — turn finished
  *)       style="fg=$tint" ;;            # working/idle — the theme's frame
esac
tmux set-option -p -t "$TMUX_PANE" pane-border-style "$style" 2>/dev/null

# Only when this pane both changed state and is the one being looked at:
# a transition three panes away can't alter the active frame, and PreToolUse
# fires often enough that spending four tmux calls per tool call to prove
# that would be a poor trade.
if [ "$changed" = "1" ] \
   && [ "$(tmux display-message -p -t "$TMUX_PANE" '#{pane_active}' 2>/dev/null)" = "1" ]; then
  active_border "$TMUX_PANE"
fi

# Repaint immediately rather than waiting up to status-interval for the next
# border refresh — the whole point is that the change is instant. Only on an
# actual transition, though: PreToolUse fires once per tool call, and forcing
# a redraw on every one of those across four busy panes is a lot of screen
# churn to communicate nothing new.
[ "$changed" = "1" ] && tmux refresh-client -S 2>/dev/null

# A finished turn earns one flash in the status line — enough to catch the
# eye across the room without stealing focus. Transition only, so a repeated
# Stop event can't re-celebrate.
if [ "$changed" = "1" ] && [ "$state" = "done" ]; then
  tmux display-message -t "$TMUX_PANE" -d 2000 "#[fg=colour114] ✔ $repo finished ✨" 2>/dev/null
fi

exit 0
