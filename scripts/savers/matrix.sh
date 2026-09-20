# savers/matrix.sh — the original: matrix rain.
#
# Sourced by grid-saver.sh, which has already set rows, cols, accent, sess and
# the SAV_SGR ramp. Defines the composable contract — SAVER_DELAY plus
# saver_begin/saver_frame — so it can run on its own or as the backdrop under
# the standby panel; the host supplies the loop either way.
#
# The rain falls in the active theme's accent — matrix rains green, nosferatu
# red, ocean cyan — with bright heads, and the glyph pool is half-width
# katakana plus digits, per the film. The four brightnesses come from the
# host's ramp rather than being spelled here, which is what lets
# @grid_saver_opacity fade the whole thing toward the session background
# without this file knowing that opacity exists.

# An array dodges bash 3.2's byte-vs-character substring ambiguity on
# multibyte strings — indexing glyphs is safe where slicing them isn't.
GLYPHS=(ｱ ｲ ｳ ｴ ｵ ｶ ｷ ｸ ｹ ｺ ｻ ｼ ｽ ｾ ｿ ﾀ ﾁ ﾂ ﾃ ﾄ ﾅ ﾆ ﾇ ﾈ ﾉ ﾊ ﾋ ﾌ ﾍ ﾎ ﾏ ﾐ ﾑ ﾒ ﾓ ﾔ ﾕ ﾖ ﾗ ﾘ ﾙ ﾚ ﾛ ﾜ ﾝ 0 1 2 3 4 5 6 7 8 9 Z X '$' '#' '%' '+' '=' '-')

TAIL=12
SAVER_DELAY=0.06

saver_begin() {
  n=${#GLYPHS[@]}
  c=0
  while [ "$c" -lt "$cols" ]; do
    y[c]=$((RANDOM % (rows + TAIL)))
    c=$((c + 1))
  done
}

saver_frame() {
  # Advance ~a third of the columns per tick: cheaper than a full sweep,
  # and the desync is what reads as rain instead of a falling curtain.
  i=0
  while [ "$i" -lt $((cols / 3 + 1)) ]; do
    c=$((RANDOM % cols))
    h=${y[$c]}
    x=$((c + 1))
    # Every write is guarded, erases included. An unguarded erase would punch a
    # space through the standby panel on the frame after its geometry changed,
    # and a single stray hole in a ledger row is more noticeable than anything
    # the rain does.
    if [ "$h" -lt "$rows" ]; then
      r=$((h + 1))
      sav_hidden "$r" "$x" || frame="$frame\e[${r};${x}H\e[${SAV_SGR[3]}m${GLYPHS[$((RANDOM % n))]}"
    fi
    # the head it just left cools into the trail colour
    if [ "$h" -ge 1 ] && [ "$h" -le "$rows" ]; then
      sav_hidden "$h" "$x" || frame="$frame\e[${h};${x}H\e[${SAV_SGR[1]}m${GLYPHS[$((RANDOM % n))]}"
    fi
    # erase the tail end
    t=$((h - TAIL))
    if [ "$t" -ge 0 ] && [ "$t" -lt "$rows" ]; then
      r=$((t + 1))
      sav_hidden "$r" "$x" || frame="$frame\e[${r};${x}H "
    fi
    y[$c]=$((h + 1))
    [ "${y[$c]}" -gt $((rows + TAIL)) ] && y[$c]=0
    i=$((i + 1))
  done
}
