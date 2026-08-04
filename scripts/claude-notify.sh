#!/bin/bash
# claude-notify.sh — Claude Code hook → macOS banner + optional ntfy phone push.
#
# Wire into a profile's settings.json for two events (see README):
#   Notification — Claude needs input/permission (banner with sound)
#   Stop         — Claude finished a response (silent banner)
#
# Phone push (ntfy) is configured in $GRID_CONFIG/ntfy.conf and only fires
# when the Mac has been idle past a threshold — at the desk, banners
# suffice; away, the phone tells you when to come back.
#
# Hook contract: never block, never fail — short work, always exit 0.

input=$(cat)
TN=/opt/homebrew/bin/terminal-notifier
GRID_CONFIG="${GRID_CONFIG:-$HOME/.config/claude-code-grid}"

event=$(printf '%s' "$input" | jq -r '.hook_event_name // ""' 2>/dev/null)
cwd=$(printf '%s' "$input" | jq -r '.cwd // ""' 2>/dev/null)
msg=$(printf '%s' "$input" | jq -r '.message // ""' 2>/dev/null)

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

if [ -x "$TN" ]; then
  if [ "$event" = "Stop" ]; then
    "$TN" -title "Claude · ${repo:-?}" -message "✅ Finished — ready for review" \
      -group "claude-stop-$repo" >/dev/null 2>&1 &
  else
    "$TN" -title "Claude · ${repo:-?}" -message "⚠️ ${msg:-Needs your attention}" \
      -sound default -group "claude-attn-$repo" >/dev/null 2>&1 &
  fi
fi

# ── ntfy phone push ──────────────────────────────────────────────────────────
# Config absent/empty → off with zero network calls; short timeout; never
# fatal.
NTFY_URL="" NTFY_TOKEN="" NTFY_IDLE_THRESHOLD=120
[ -f "$GRID_CONFIG/ntfy.conf" ] && . "$GRID_CONFIG/ntfy.conf"

if [ -n "$NTFY_URL" ]; then
  idle_s=$(ioreg -c IOHIDSystem 2>/dev/null | awk '/HIDIdleTime/ {print int($NF/1000000000); exit}')
  if [ "${idle_s:-0}" -ge "${NTFY_IDLE_THRESHOLD:-120}" ] 2>/dev/null; then
    if [ "$event" = "Stop" ]; then
      title="Claude · ${repo:-?}" body="Finished — ready for review" tag="white_check_mark" prio="default"
    else
      title="Claude · ${repo:-?}" body="${msg:-Needs your attention}" tag="rotating_light" prio="high"
    fi
    auth=()
    [ -n "$NTFY_TOKEN" ] && auth=(-H "Authorization: Bearer $NTFY_TOKEN")
    curl -s -m 5 -X POST "$NTFY_URL" \
      -H "Title: $title" -H "Tags: $tag" -H "Priority: $prio" \
      "${auth[@]}" --data-binary "$body" >/dev/null 2>&1 &
  fi
fi

exit 0
