# savers/heartbeat.sh — the last hour as a timeline: where the day actually went.
#
# Sourced by grid-saver.sh, which has already set rows, cols, accent and sess.
#
# standby answers "what is happening now". This answers "what has been
# happening", which the grid has never been able to say: pane options hold the
# current state and when it started, and forget every stretch before this one.
# pane-state.sh now appends each transition to $GRID_CONFIG/ledger/<session>.log,
# and this replays it into one row per pane, a cell per time bucket, coloured in
# the same language as the borders — so a red band IS the twenty minutes that
# pane spent blocked on you while you were at lunch.
#
# Two sources, merged. The ledger gives history. The live panes give the
# current state and its @state_since, which matters twice: it covers the
# stretch since the last recorded transition, and it means a grid whose ledger
# is empty (fresh install, or a session older than this feature) still draws
# something truthful rather than an empty screen.
#
# The frame is built by awk into a shell variable and printed by bash, rather
# than awk writing to the terminal: the host kills this loop on wake, and a
# captured frame that never gets printed is strictly better than a half-drawn
# one racing the screen restore.

animate() {
  ledger="$GRID_CONFIG/ledger/$sess.log"

  # Keep the ledger from growing without bound. Opportunistic and racy by
  # design: a transition landing inside the rename window loses one line, and
  # one line of a picture is not worth locking a hook that must never block.
  if [ -s "$ledger" ]; then
    lines=$(wc -l < "$ledger" 2>/dev/null)
    if [ "${lines:-0}" -gt 5000 ]; then
      tmp="$ledger.trim.$$"
      tail -n 3000 "$ledger" > "$tmp" 2>/dev/null && mv -f "$tmp" "$ledger" 2>/dev/null
      rm -f "$tmp" 2>/dev/null
    fi
  fi

  first=1
  while :; do
    now=$(date +%s)
    panes=$(tmux list-panes -t "$sess" -F '#{@repo}|#{@state}|#{@state_since}|#{@cl_ctx}' 2>/dev/null)

    frame=$(
      # Both streams are normalised to TAB-delimited before they are merged.
      # Repo names can contain spaces (grid_label only rewrites '/'), so a
      # space-split anywhere along this path would truncate the name and file a
      # pane's history under the wrong row. Tabs cannot occur in any field.
      {
        [ -s "$ledger" ] && awk -F'\t' -v OFS='\t' '{ print "L", $1, $2, $3 }' "$ledger"
        printf '%s\n' "$panes" | awk -F'|' -v OFS='\t' '$1 != "" { print "C", $1, $2, $3, $4 }'
      } | awk -F'\t' -v now="$now" -v rows="$rows" -v cols="$cols" -v accent="$accent" -v sess="$sess" '
      function scol(s) {
        if (s == "waiting") return 203
        if (s == "working") return 81
        if (s == "done")    return 114
        if (s == "idle")    return 240
        return 236
      }
      function pri(s) {
        if (s == "waiting") return 0
        if (s == "done")    return 1
        if (s == "working") return 2
        return 3
      }
      function dur(m) {
        if (m < 60) return sprintf("%dm", m)
        return sprintf("%dh%02d", int(m / 60), m % 60)
      }
      BEGIN {
        WIN = 3600
        start = now - WIN
        NAMEW = 20; CTXW = 16
        B = cols - NAMEW - CTXW - 6
        if (B > 100) B = 100
        if (B < 12)  B = 12
        bsec = WIN / B
      }
      $1 == "L" {
        t = $2 + 0; s = $3; r = $4
        if (r == "") next
        if (!(r in seen)) { seen[r] = 1; order[++nr] = r }
        if (t < start) { before[r] = s; next }
        k = ++ec[r]; evt[r, k] = t; evs[r, k] = s
        next
      }
      $1 == "C" {
        r = $2; s = $3; since = $4 + 0; ctx = $5
        if (r == "") next
        if (!(r in seen)) { seen[r] = 1; order[++nr] = r }
        live[r] = s; lctx[r] = ctx; alive[r] = 1
        # The current stretch as a synthetic event. Appended after every ledger
        # line, which keeps the per-repo sequence in order because @state_since
        # IS the most recent transition. A duplicate of one already in the
        # ledger is harmless — the fill below just sets the same state twice.
        if (since >= start) { k = ++ec[r]; evt[r, k] = since; evs[r, k] = s }
        else if (since > 0) before[r] = s
        next
      }
      END {
        # ── lay out ──
        n = 0
        for (p = 0; p <= 3; p++)
          for (i = 1; i <= nr; i++) {
            r = order[i]
            if (alive[r] && pri(live[r]) == p) show[++n] = r
          }
        # Rows are capped by the height of the terminal, but every pane is still
        # walked below. The cap decides what is DRAWN; the totals underneath
        # have to describe the whole session, not the part that happened to
        # fit, or "blocked 34m" quietly becomes a lie on a short terminal.
        total = n
        cap = rows - 11; if (cap < 1) cap = 1
        if (n > cap) n = cap
        hidden = total - n
        sh = (hidden > 0) ? 1 : 0

        top = int((rows - (n + 8 + sh)) / 2)
        if (top < 1) top = 1

        out = ""
        hd = "THE LAST HOUR · " sess
        hc = int((cols - length(hd)) / 2) + 1; if (hc < 1) hc = 1
        out = out sprintf("\033[%d;%dH\033[1;38;5;%dm%s\033[0m\033[K", top, hc, accent, hd)

        left = int((cols - (NAMEW + B + CTXW)) / 2) + 1; if (left < 1) left = 1

        for (i = 1; i <= total; i++) {
          r = show[i]
          draw = (i <= n)
          row = top + 2 + i - 1
          # Padded to NAMEW but truncated to NAMEW-2, so a long repo name can
          # never run straight into its own bar with no gap.
          if (draw)
            out = out sprintf("\033[%d;%dH\033[38;5;250m%-*.*s\033[0m", row, left, NAMEW, NAMEW - 2, r)

          c = before[r]; k = 1; last = ""
          bar = ""
          for (b = 0; b < B; b++) {
            bt = start + (b + 1) * bsec
            while (k <= ec[r] && evt[r, k] <= bt) { c = evs[r, k]; k++ }
            mins[c] += bsec / 60
            if (!draw) continue
            cc = scol(c)
            # Run-length: only emit an SGR when the colour actually changes,
            # or a full-width row costs 100 escape sequences per pane per tick.
            if (cc != last) { bar = bar sprintf("\033[38;5;%dm", cc); last = cc }
            bar = bar ((c == "") ? "░" : "█")
          }
          if (!draw) continue
          out = out bar "\033[0m"

          # ── context pressure ──
          # @cl_ctx is percent REMAINING (the title bar blinks amber at <=15),
          # so the bar empties as a pane fills up and the colour is a warning,
          # not a reading.
          cx = lctx[r]
          if (cx ~ /^[0-9]+$/) {
            v = cx + 0
            fill = int(v / 10 + 0.5); if (fill > 10) fill = 10; if (fill < 0) fill = 0
            bc = (v > 50) ? 114 : ((v > 15) ? 214 : 203)
            meter = ""
            for (q = 0; q < 10; q++) meter = meter ((q < fill) ? "█" : "░")
            out = out sprintf("\033[%d;%dH\033[38;5;%dm%s\033[0m\033[2m %3d%%\033[0m\033[K",
                              row, left + NAMEW + B + 1, bc, meter, v)
          } else {
            out = out sprintf("\033[%d;%dH\033[K", row, left + NAMEW + B + 1)
          }
        }

        # ── what did not fit ──
        # (no apostrophes in here: this awk program is a single-quoted shell
        # word, and one would end it mid-flight)
        if (hidden > 0)
          out = out sprintf("\033[%d;%dH\033[2;38;5;%dm… and %d more\033[0m\033[K",
                            top + n + 2, left + 2, accent, hidden)

        # ── axis ──
        ax = sprintf("%-*s", NAMEW, "")
        lbl = "-60m"; ax = ax lbl
        for (q = length(lbl); q < int(B / 2) - 2; q++) ax = ax " "
        lbl = "-30m"; ax = ax lbl
        for (q = length(ax) - NAMEW; q < B - 3; q++) ax = ax " "
        ax = ax "now"
        out = out sprintf("\033[%d;%dH\033[2;38;5;%dm%s\033[0m\033[K", top + n + 3 + sh, left, accent, substr(ax, 1, NAMEW + B))

        # ── totals ──
        tt = ""; tw = 0
        if (mins["waiting"] >= 1) { tt = tt sprintf("\033[1;38;5;203m▲ blocked %s\033[0m   ", dur(int(mins["waiting"]))); tw += 13 + length(dur(int(mins["waiting"]))) }
        if (mins["working"] >= 1) { tt = tt sprintf("\033[38;5;81m▶ working %s\033[0m   ",   dur(int(mins["working"]))); tw += 13 + length(dur(int(mins["working"]))) }
        if (mins["done"]    >= 1) { tt = tt sprintf("\033[38;5;114m✔ done %s\033[0m   ",     dur(int(mins["done"])));    tw += 10 + length(dur(int(mins["done"]))) }
        if (mins["idle"]    >= 1) { tt = tt sprintf("\033[38;5;240m· idle %s\033[0m   ",     dur(int(mins["idle"])));    tw += 10 + length(dur(int(mins["idle"]))) }
        if (tw == 0) { tt = sprintf("\033[2;38;5;%dmno activity recorded yet\033[0m", accent); tw = 24 } else tw -= 3
        tc = int((cols - tw) / 2) + 1; if (tc < 1) tc = 1
        out = out sprintf("\033[%d;%dH%s\033[K", top + n + 5 + sh, tc, tt)
        out = out sprintf("\033[%d;1H\033[J", top + n + 6 + sh)
        printf "%s", out
      }'
    )

    [ "$first" = 1 ] && { printf '\e[2J'; first=0; }
    printf '%b' "$frame"
    sleep 5
  done
}
