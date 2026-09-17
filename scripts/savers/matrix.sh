# savers/matrix.sh — the original: matrix rain.
#
# Sourced by grid-saver.sh, which has already set rows, cols, accent and sess.
# Defines animate(); the host backgrounds it and reaps it on wake.
#
# The rain falls in the active theme's accent — matrix rains green, nosferatu
# red, ocean cyan — with bright white heads, and the glyph pool is half-width
# katakana plus digits, per the film.

# An array dodges bash 3.2's byte-vs-character substring ambiguity on
# multibyte strings — indexing glyphs is safe where slicing them isn't.
GLYPHS=(ｱ ｲ ｳ ｴ ｵ ｶ ｷ ｸ ｹ ｺ ｻ ｼ ｽ ｾ ｿ ﾀ ﾁ ﾂ ﾃ ﾄ ﾅ ﾆ ﾇ ﾈ ﾉ ﾊ ﾋ ﾌ ﾍ ﾎ ﾏ ﾐ ﾑ ﾒ ﾓ ﾔ ﾕ ﾖ ﾗ ﾘ ﾙ ﾚ ﾛ ﾜ ﾝ 0 1 2 3 4 5 6 7 8 9 Z X '$' '#' '%' '+' '=' '-')

TAIL=12

animate() {
  n=${#GLYPHS[@]}
  c=0
  while [ "$c" -lt "$cols" ]; do
    y[c]=$((RANDOM % (rows + TAIL)))
    c=$((c + 1))
  done
  while :; do
    frame=''
    # Advance ~a third of the columns per tick: cheaper than a full sweep,
    # and the desync is what reads as rain instead of a falling curtain.
    i=0
    while [ "$i" -lt $((cols / 3 + 1)) ]; do
      c=$((RANDOM % cols))
      h=${y[$c]}
      # bright head
      if [ "$h" -lt "$rows" ]; then
        frame="$frame\e[$((h + 1));$((c + 1))H\e[1;97m${GLYPHS[$((RANDOM % n))]}"
      fi
      # the head it just left cools into the trail colour
      if [ "$h" -ge 1 ] && [ "$h" -le "$rows" ]; then
        frame="$frame\e[${h};$((c + 1))H\e[0;38;5;${accent}m${GLYPHS[$((RANDOM % n))]}"
      fi
      # erase the tail end
      t=$((h - TAIL))
      if [ "$t" -ge 0 ] && [ "$t" -lt "$rows" ]; then
        frame="$frame\e[$((t + 1));$((c + 1))H "
      fi
      y[$c]=$((h + 1))
      [ "${y[$c]}" -gt $((rows + TAIL)) ] && y[$c]=0
      i=$((i + 1))
    done
    printf '%b' "$frame"
    sleep 0.06
  done
}
