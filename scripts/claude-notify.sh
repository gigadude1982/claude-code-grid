#!/bin/bash
# claude-notify.sh — Claude Code hook → macOS banner + optional ntfy phone push.
#
# Wire into a profile's settings.json for three events (see README):
#   Notification — Claude needs input/permission/etc (banner, usually sound)
#   Stop         — Claude finished a turn normally (silent banner)
#   StopFailure  — the turn died on an API error (banner with sound)
#
# The icon, ntfy tag/priority, and whether the desktop banner plays a sound
# all come from classifying the event below — see the "classify" block —
# rather than one hardcoded look for every Notification/Stop.
#
# Clicking a desktop banner jumps straight to the pane that fired it
# (grid-notify-click.sh) and, for ntfy, tapping the push can open
# $NTFY_CLICK_URL if you've set one (e.g. a remote terminal URL).
#
# Phone push (ntfy) is configured in $GRID_CONFIG/ntfy.conf and only fires
# when the Mac has been idle past a threshold — at the desk, banners
# suffice; away, the phone tells you when to come back.
#
# Hook contract: never block, never fail — short work, always exit 0.

input=$(cat)
TN=/opt/homebrew/bin/terminal-notifier
GRID_CONFIG="${GRID_CONFIG:-$HOME/.config/claude-code-grid}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Quiet hours: the 🔔 header chip parks an expiry epoch in @grid_mute; while
# it's in the future every banner and push is swallowed. An expired value is
# cleared here, so the chip flips back to 🔔 on its own.
mute=$(tmux show-options -gv @grid_mute 2>/dev/null)
if [ -n "$mute" ]; then
  if [ "$(date +%s)" -lt "$mute" ] 2>/dev/null; then
    exit 0
  fi
  tmux set-option -gu @grid_mute 2>/dev/null
fi

event=$(printf '%s' "$input" | jq -r '.hook_event_name // ""' 2>/dev/null)
cwd=$(printf '%s' "$input" | jq -r '.cwd // ""' 2>/dev/null)
msg=$(printf '%s' "$input" | jq -r '.message // ""' 2>/dev/null)

# Squash to one line, drop markdown bold and any trailing <options> block
# (AskUserQuestion's raw markup), cap length. Used for both the Stop summary
# and (defensively) any other freeform text we show.
oneline() {
  local s
  s=$(printf '%s' "$1" | sed -E 's/<options>.*//; s/\*\*//g; s/[[:space:]]+/ /g; s/^ +//; s/ +$//')
  local maxlen=100
  if [ "${#s}" -gt "$maxlen" ]; then
    s="${s:0:$((maxlen - 1))}…"
  fi
  printf '%s' "$s"
}

# ── classify: which event/subtype this is, in plain terms ───────────────────
# Stop only ever means "finished normally" — Claude Code fires the separate
# StopFailure event for a turn that died on an API error, so that split (not
# message-sniffing) is what makes success vs error reliable here. Notification
# carries a real "notification_type" enum (see `docs/hooks.md`); the message
# field is populated too but isn't guaranteed, so notification_type drives the
# icon/urgency and $msg is only used to flesh out the body text.
icon="⚠️" kind="warning" ntfy_tag="rotating_light" ntfy_prio="high" want_sound=1

case "$event" in
  Stop)
    last_msg=$(printf '%s' "$input" | jq -r '.last_assistant_message // ""' 2>/dev/null)
    body="$(oneline "$last_msg")"
    body="${body:-Finished — ready for review}"
    icon="✅" kind="success" ntfy_tag="white_check_mark" ntfy_prio="default" want_sound=""
    ;;
  StopFailure)
    error_type=$(printf '%s' "$input" | jq -r '.error_type // "unknown"' 2>/dev/null)
    case "$error_type" in
      rate_limit)            body="API error — rate limited" ;;
      overloaded)            body="API error — overloaded, try again shortly" ;;
      authentication_failed) body="API error — authentication failed" ;;
      oauth_org_not_allowed) body="API error — org not allowed" ;;
      billing_error)         body="API error — billing issue" ;;
      invalid_request)       body="API error — invalid request" ;;
      model_not_found)       body="API error — model not found" ;;
      server_error)          body="API error — server error" ;;
      max_output_tokens)     body="Hit max output tokens" ;;
      *)                     body="API error — turn failed" ;;
    esac
    icon="❌" kind="error" ntfy_tag="x" ntfy_prio="urgent" want_sound=1
    ;;
  Notification)
    notification_type=$(printf '%s' "$input" | jq -r '.notification_type // ""' 2>/dev/null)
    case "$notification_type" in
      permission_prompt)
        icon="⚠️" kind="warning" ntfy_tag="warning" ntfy_prio="high" want_sound=1
        body="${msg:-Needs your permission}" ;;
      elicitation_dialog|elicitation_url_dialog)
        icon="❓" kind="warning" ntfy_tag="grey_question" ntfy_prio="high" want_sound=1
        body="${msg:-Needs a response}" ;;
      idle_prompt|agent_needs_input|elicitation_response)
        icon="💬" kind="info" ntfy_tag="speech_balloon" ntfy_prio="high" want_sound=1
        body="${msg:-Waiting for your input}" ;;
      auth_success|elicitation_complete)
        icon="✅" kind="info" ntfy_tag="white_check_mark" ntfy_prio="low" want_sound=""
        body="${msg:-Signed in}" ;;
      agent_completed)
        icon="✅" kind="info" ntfy_tag="white_check_mark" ntfy_prio="default" want_sound=""
        body="${msg:-Agent finished}" ;;
      *)
        # Unknown type (or an older Claude Code build with no notification_type
        # at all) — treat as attention-worthy, same as always.
        icon="⚠️" kind="warning" ntfy_tag="rotating_light" ntfy_prio="high" want_sound=1
        body="${msg:-Needs your attention}" ;;
    esac
    ;;
  *)
    body="${msg:-Needs your attention}"
    ;;
esac

# Label by repo. Worktree paths (repo/.claude/worktrees/name) collapse to the
# repo itself; nested checkouts (e.g. ~/dev/shipvane/engine) keep the parent
# for disambiguation, but common root dirs don't.
repo_path="$cwd"
case "$repo_path" in
  */.claude/worktrees/*) repo_path="${repo_path%%/.claude/worktrees/*}" ;;
esac
repo=$(basename "$repo_path")
parent=$(basename "$(dirname "$repo_path")")
case "$parent" in dev|bounteous|work|src|code|projects|"$USER"|"") ;; *) repo="$parent/$repo" ;; esac

# "Click for more details" — jump straight to the pane that fired this and
# raise its terminal app. $TMUX_PANE/$TERM_PROGRAM only exist right now, in
# the hook's own env, so bake them into the -execute command; by click time
# the hook process (and its env) is long gone. No pane → no -execute, and
# terminal-notifier just does its default (dismiss) on click.
click_cmd=""
if [ -n "${TMUX_PANE:-}" ]; then
  click_cmd="$SCRIPT_DIR/grid-notify-click.sh $(printf '%q' "$TMUX_PANE") $(printf '%q' "${TERM_PROGRAM:-}")"
fi

if [ -x "$TN" ]; then
  execute_args=()
  [ -n "$click_cmd" ] && execute_args=(-execute "$click_cmd")
  sound_args=()
  [ -n "$want_sound" ] && sound_args=(-sound default)
  "$TN" -title "Claude · ${repo:-?}" -message "$icon $body" \
    -group "claude-$kind-$repo" "${sound_args[@]}" "${execute_args[@]}" >/dev/null 2>&1 &
fi

# ── ntfy phone push ──────────────────────────────────────────────────────────
# Config absent/empty → off with zero network calls; short timeout; never
# fatal.
NTFY_URL="" NTFY_TOKEN="" NTFY_IDLE_THRESHOLD=120 NTFY_CLICK_URL=""
[ -f "$GRID_CONFIG/ntfy.conf" ] && . "$GRID_CONFIG/ntfy.conf"

if [ -n "$NTFY_URL" ]; then
  idle_s=$(ioreg -c IOHIDSystem 2>/dev/null | awk '/HIDIdleTime/ {print int($NF/1000000000); exit}')
  if [ "${idle_s:-0}" -ge "${NTFY_IDLE_THRESHOLD:-120}" ] 2>/dev/null; then
    title="Claude · ${repo:-?}"
    auth=()
    [ -n "$NTFY_TOKEN" ] && auth=(-H "Authorization: Bearer $NTFY_TOKEN")
    click_hdr=()
    [ -n "$NTFY_CLICK_URL" ] && click_hdr=(-H "Click: $NTFY_CLICK_URL")
    curl -s -m 5 -X POST "$NTFY_URL" \
      -H "Title: $title" -H "Tags: $ntfy_tag" -H "Priority: $ntfy_prio" \
      "${auth[@]}" "${click_hdr[@]}" --data-binary "$body" >/dev/null 2>&1 &
  fi
fi

exit 0
