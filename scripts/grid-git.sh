#!/bin/bash
# grid-git.sh [session] — every grid repo's git state, in one popup.
#
# Bound to prefix+g. Answers "where does everything actually stand?" without
# spending a pane on a control shell or interrupting four Claude sessions to
# run git in each of them.
#
#   ▸ shipvane-engine   main  ↑2  ● 3 changed
#     a1b2c3d  2 hours ago  fix: retry on 429
#
# Output is ANSI-colored rather than tmux #[...] markup: this runs inside a
# display-popup, which is a real terminal, not a status-line format context.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/grid-lib.sh"

session="${1:-}"
[ -n "$session" ] || session=$(grid_current_session)

esc=$'\033'
dim="${esc}[2m" bold="${esc}[1m" reset="${esc}[0m"
red="${esc}[38;5;203m" green="${esc}[38;5;114m" yellow="${esc}[38;5;221m" grey="${esc}[38;5;244m"

printf '%s\n' "${bold}grid: $session${reset}"
printf '%s\n' "${dim}$(printf '─%.0s' $(seq 1 60))${reset}"

while IFS=$'\t' read -r label color path; do
  [ -n "$label" ] || continue

  tint="${esc}[38;5;${color#colour}m"
  if ! git -C "$path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf '\n%s▸ %s%s  %s(not a git repo)%s\n' "$tint" "$label" "$reset" "$grey" "$reset"
    continue
  fi

  branch=$(git -C "$path" branch --show-current 2>/dev/null)
  [ -n "$branch" ] || branch=$(git -C "$path" rev-parse --short HEAD 2>/dev/null)

  # Ahead/behind the upstream, when there is one. A branch with no upstream
  # is worth calling out — it's the state where "I pushed it" is usually wrong.
  track=""
  if upstream=$(git -C "$path" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null); then
    counts=$(git -C "$path" rev-list --left-right --count "$upstream"...HEAD 2>/dev/null)
    behind=$(printf '%s' "$counts" | awk '{print $1}')
    ahead=$(printf '%s' "$counts" | awk '{print $2}')
    [ "${ahead:-0}"  -gt 0 ] 2>/dev/null && track="$track ${yellow}↑${ahead}${reset}"
    [ "${behind:-0}" -gt 0 ] 2>/dev/null && track="$track ${yellow}↓${behind}${reset}"
  else
    track=" ${grey}(no upstream)${reset}"
  fi

  changed=$(git -C "$path" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  if [ "${changed:-0}" -gt 0 ]; then
    state="${red}● ${changed} changed${reset}"
  else
    state="${green}✓ clean${reset}"
  fi

  printf '\n%s▸ %s%s  %s%s%s%s  %s\n' \
    "$tint" "$label" "$reset" "$grey" "$branch" "$reset" "$track" "$state"
  last=$(git -C "$path" log -1 --format='%h  %ar  %s' 2>/dev/null)
  [ -n "$last" ] && printf '  %s%s%s\n' "$dim" "$last" "$reset"
done < <(tmux list-panes -t "$session:0" -F '#{@repo}	#{@repo_color}	#{pane_current_path}' 2>/dev/null)

printf '\n%s' "${dim}press any key${reset}"
read -rsn1
