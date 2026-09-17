# savers/life.sh — Conway's game of life across the whole terminal.
#
# Sourced by grid-saver.sh, which has already set rows, cols, accent and sess.
#
# This one is awk, not bash, and that's load-bearing. A generation is
# rows*cols*8 neighbour lookups — about 80,000 on a full-screen grid — and bash
# 3.2 needs seconds for that, which is a slideshow rather than an animation.
# awk does it in tens of milliseconds. The matrix and starfield savers stay in
# bash because their per-frame work is two orders of magnitude smaller.
#
# `exec` matters too: `animate &` runs the function in a subshell, and the host
# kills that subshell's pid on wake. Without exec, awk would be a *child* of it
# and survive the kill as an orphan still painting the terminal. exec makes awk
# itself the process the host is holding.
#
# Cells age into the theme: born white, accent while establishing, dim accent
# once they've settled. The board wraps as a torus (no dead borders), and
# reseeds itself when the population stops changing — life on a small torus
# settles into still lifes and blinkers within a minute or so, and a frozen
# screensaver looks like a crashed one.

animate() {
  exec awk -v rows="$rows" -v cols="$cols" -v accent="$accent" -v seed="$RANDOM" '
  function reseed(   i) {
    for (i = 0; i < n; i++) { a[i] = (rand() < 0.25) ? 1 : 0; age[i] = a[i] }
    stall = 0; last = -1; last2 = -2
  }
  BEGIN {
    srand(seed)
    n = rows * cols
    blk = "█"
    reseed()
    # prev holds what is currently ON SCREEN, so each frame writes only the
    # cells that changed. -1 is "nothing painted yet", which makes the first
    # frame a full repaint and every frame after it nearly free.
    for (i = 0; i < n; i++) prev[i] = -1

    while (1) {
      # ── paint the diff, one row at a time ──
      # Buffered per row rather than per frame on purpose: the first frame
      # touches every cell, and repeated concatenation onto one huge string is
      # quadratic in some awks. A row is a few KB and tearing between rows is
      # invisible at this frame rate.
      # Run-length encoded: a cursor-move only when the run of changed cells
      # breaks, an SGR only when the colour actually changes. Life changes in
      # clumps — gliders, blinkers, the edge of a blob — so consecutive cells
      # usually change together and share a state, which is exactly the case
      # this collapses. Matters on a remote link, where the naive form spends
      # ~15 bytes on every single cell.
      for (y = 0; y < rows; y++) {
        base = y * cols
        out = ""
        lastx = -99; lasts = -1
        for (x = 0; x < cols; x++) {
          i = base + x
          s = a[i] ? (age[i] < 2 ? 1 : (age[i] < 6 ? 2 : 3)) : 0
          if (s == prev[i]) continue
          prev[i] = s
          if (x != lastx + 1) { out = out sprintf("\033[%d;%dH", y + 1, x + 1); lasts = -1 }
          if (s != lasts) {
            if      (s == 0) out = out "\033[0m"
            else if (s == 1) out = out "\033[1;97m"
            else if (s == 2) out = out "\033[0;38;5;" accent "m"
            else             out = out "\033[2;38;5;" accent "m"
            lasts = s
          }
          out = out ((s == 0) ? " " : blk)
          lastx = x
        }
        if (out != "") printf "%s", out
      }
      fflush()
      system("sleep 0.1")

      # ── one generation, wrapping at every edge ──
      pop = 0
      for (y = 0; y < rows; y++) {
        up  = ((y - 1 + rows) % rows) * cols
        dn  = ((y + 1) % rows) * cols
        cur = y * cols
        for (x = 0; x < cols; x++) {
          xl = (x - 1 + cols) % cols
          xr = (x + 1) % cols
          c = a[up+xl] + a[up+x] + a[up+xr] + a[cur+xl] + a[cur+xr] \
            + a[dn+xl] + a[dn+x] + a[dn+xr]
          i = cur + x
          b[i] = a[i] ? (c == 2 || c == 3) : (c == 3)
          pop += b[i]
        }
      }
      for (i = 0; i < n; i++) {
        age[i] = b[i] ? (a[i] ? age[i] + 1 : 1) : 0
        a[i] = b[i]
      }

      # Compare against the last TWO populations, not just the last: still
      # lifes hold one number, but blinkers alternate between two and would
      # never look stalled by a single-step check.
      if (pop == last || pop == last2) stall++; else stall = 0
      last2 = last; last = pop
      if (stall > 40 || pop < n / 100) reseed()
    }
  }'
}
