#!/bin/bash
# grid-cost.sh [render|popup] [session] — the grid's Claude spend, summed.
#
# Sums the @cl_cost/@cl_rate pane options that claude-status-line's
# statusline.sh stamps on each grid pane. `render` (the default) emits the
# header chip — "Σ$203·$220/hr" — and prints nothing until at least one pane
# has stamped a cost, so the chip stays out of the way on a fresh grid.
# `popup` draws the per-repo breakdown table.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/grid-lib.sh"

mode="${1:-render}"
session="${2:-$(grid_current_session)}"
[ -n "$session" ] || exit 0

panes() {
  tmux list-panes -t "$session:0" \
    -F '#{@repo}	#{@cl_model}	#{@cl_cost}	#{@cl_rate}	#{@cl_ctx}' 2>/dev/null
}

case "$mode" in
  render)
    panes | awk -F'\t' '
      $1 != "" && $3 != "" { cost += $3; rate += $4; n++ }
      END {
        if (n > 0) printf "#[fg=colour178]Σ$%.0f#[fg=colour244]·$%.0f/hr", cost, rate
      }'
    ;;
  popup)
    esc=$'\033'
    b="${esc}[1m" d="${esc}[2m" r="${esc}[0m"
    hd="${esc}[38;5;45m" amt="${esc}[38;5;178m"
    printf '\n %s%s — claude spend%s\n\n' "$b" "$session" "$r"
    printf "   ${d}%-24s %-7s %9s %9s %6s${r}\n" "repo" "model" "cost" "burn" "ctx"
    panes | awk -F'\t' -v a="$amt" -v r="$r" -v d="$d" '
      $1 != "" {
        cost = ($3 == "") ? "—" : sprintf("$%s", $3)
        rate = ($4 == "") ? "—" : sprintf("$%s/hr", $4)
        ctx  = ($5 == "") ? "—" : sprintf("%s%%", $5)
        printf "   %-24s %-7s %s%9s%s %9s %6s\n", $1, ($2 == "" ? "—" : $2), a, cost, r, rate, ctx
        tc += $3; tr += $4; n++
      }
      END {
        if (n > 0) printf "\n   %s%-24s %-7s %s$%.2f%s %s$%.0f/hr%s\n", d, "total", "", a, tc, r, a, tr, r
      }'
    printf '\n %sctx = context window remaining · stats stamped by claude-status-line%s\n' "$d" "$r"
    printf '\n %spress any key%s' "$d" "$r"
    read -rsn1 || true
    ;;
esac
