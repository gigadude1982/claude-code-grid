# savers/fire.sh — the demoscene classic, burning in the theme's colour.
#
# Sourced by grid-saver.sh, which has already set rows, cols, accent and sess.
#
# Doom's fire algorithm: the bottom row is a constant heat source, and every
# cell above takes its value from the cell below minus a random decay, nudged
# sideways. The sideways nudge is the whole trick — without it you get rising
# stripes, with it you get flame.
#
# awk for the same reason as life: this is rows*cols of work per frame, which
# bash 3.2 cannot do at animation speed. `exec` so the host's kill lands on awk
# itself rather than a parent that would leave it orphaned and still painting.
#
# The palette is derived from the accent rather than hardcoded orange, so the
# matrix grid burns green and nosferatu burns red. xterm's 16–231 range is a
# 6x6x6 RGB cube — index = 16 + 36r + 6g + b — so an accent can be pulled apart
# into channels, scaled toward black for the cool tips and toward white for the
# hot base, and reassembled. Accents outside that range (the 0–15 system
# colours) have no such arithmetic, so they fall back to a literal fire.

animate() {
  exec awk -v rows="$rows" -v cols="$cols" -v accent="$accent" -v seed="$RANDOM" '
  BEGIN {
    srand(seed)
    n = rows * cols
    NH = 40                      # heat levels, and so ramp resolution
    GL[1] = "░"; GL[2] = "▒"; GL[3] = "▓"; GL[4] = "█"

    # ── build the ramp ──
    if (accent >= 16 && accent <= 231) {
      a = accent - 16
      ar = int(a / 36); ag = int((a % 36) / 6); ab = a % 6
      for (v = 0; v <= NH; v++) {
        t = v / NH
        if (t < 0.5) {           # cool tips: accent faded toward black
          k = t * 2
          r = ar * k; g = ag * k; b = ab * k
        } else {                 # hot base: accent blown out toward white
          k = (t - 0.5) * 2
          r = ar + (5 - ar) * k; g = ag + (5 - ag) * k; b = ab + (5 - ab) * k
        }
        r = int(r + 0.5); g = int(g + 0.5); b = int(b + 0.5)
        if (r > 5) r = 5; if (g > 5) g = 5; if (b > 5) b = 5
        if (r < 0) r = 0; if (g < 0) g = 0; if (b < 0) b = 0
        ramp[v] = 16 + 36 * r + 6 * g + b
      }
    } else {
      split("233 52 88 124 160 196 202 208 214 220 226 228 230 231", f, " ")
      for (v = 0; v <= NH; v++) {
        i = int(v / NH * 13) + 1
        ramp[v] = f[i]
      }
    }

    # What a heat level actually LOOKS like, precomputed once per level.
    #
    # ckey is the whole point: 40 heat levels collapse onto ~14 colours and 4
    # glyphs, so a cell flickering between heat 21 and 22 usually renders
    # identically. Diffing against raw heat redraws it anyway — diffing against
    # the rendered appearance skips it, and in a fire almost every cell wobbles
    # by a level or two every frame. This is the single biggest saving here.
    for (v = 0; v <= NH; v++) {
      if (v == 0) { ckey[v] = 0; continue }
      if      (v < NH / 8) gi = 1
      else if (v < NH / 4) gi = 2
      else if (v < NH / 2) gi = 3
      else                 gi = 4
      cglyph[v] = GL[gi]
      ccol[v] = ramp[v]
      ckey[v] = ramp[v] * 8 + gi
    }

    # Decay is tuned to the terminal, not fixed: the flame should reach about
    # three-quarters of the way up whether the pane is 20 rows or 60. A fixed
    # decay either fills a tall screen solid or dies in the bottom inch of a
    # short one.
    #
    # It is drawn from a WIDE uniform range rather than rounded to the nearest
    # integer, and that is the difference between fire and a gradient. Getting
    # the mean right but the variance low makes every column cool at the same
    # rate, which paints a smooth wall; the ragged tongues come from some cells
    # barely cooling while their neighbours die. Mean stays m, spread is 0..2m.
    m = NH / (rows * 0.75)
    dmax = 2 * m + 1

    for (i = 0; i < n; i++) { heat[i] = 0; prev[i] = -1 }
    for (x = 0; x < cols; x++) heat[(rows - 1) * cols + x] = NH

    tick = 0
    while (1) {
      # A slow wind biases the sideways nudge, so the flame leans and recovers
      # instead of shimmering evenly forever.
      wind = sin(tick / 40.0) * 1.6
      tick++

      for (y = rows - 2; y >= 0; y--) {
        below = (y + 1) * cols
        cur = y * cols
        for (x = 0; x < cols; x++) {
          sx = x + int(rand() * 3) - 1 + int(wind + (rand() - 0.5))
          if (sx < 0) sx = 0; if (sx >= cols) sx = cols - 1
          d = int(rand() * dmax)
          v = heat[below + sx] - d
          heat[cur + x] = (v > 0) ? v : 0
        }
      }

      # Paint only what changed, buffered a row at a time (see life.sh), and
      # run-length the escapes: fire is turbulent enough that almost every cell
      # differs every frame, so a naive "cursor-move + colour + glyph" per cell
      # costs ~15 bytes x the whole screen x 16fps — a quarter megabyte a
      # second, which is nothing on a local tty and a real problem down an SSH
      # or dev-tunnel link. Emitting a cursor-move only when the run breaks and
      # a colour only when it changes cuts that several-fold.
      for (y = 0; y < rows; y++) {
        base = y * cols
        out = ""
        lastx = -99; lastc = -1
        for (x = 0; x < cols; x++) {
          i = base + x
          k = ckey[heat[i]]
          if (k == prev[i]) continue
          prev[i] = k
          if (x != lastx + 1) { out = out sprintf("\033[%d;%dH", y + 1, x + 1); lastc = -1 }
          if (k == 0) {
            if (lastc != -2) { out = out "\033[0m"; lastc = -2 }
            out = out " "
          } else {
            v = heat[i]
            c = ccol[v]
            if (c != lastc) { out = out "\033[38;5;" c "m"; lastc = c }
            out = out cglyph[v]
          }
          lastx = x
        }
        if (out != "") printf "%s", out
      }
      fflush()
      system("sleep 0.06")
    }
  }'
}
