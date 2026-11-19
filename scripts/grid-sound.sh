#!/bin/bash
# grid-sound.sh — chiptune blips for the retro-game screensavers.
#
# Sourced by grid-saver.sh (bash 3.2) to get sav_sound; also runnable:
#
#   grid-sound.sh build          render the sound bank (idempotent)
#   grid-sound.sh test [level]   play every sound once, in order
#   grid-sound.sh play <name>    play one
#
# No sound files ship with the repo. The bank is SYNTHESISED on first use —
# square waves, sweeps and sample-and-hold noise, the same three things an
# 8-bit console's sound chip had — by a small perl program below, into
# $GRID_CONFIG/sounds. Perl because it ships with macOS and writes binary
# without a fight; bash can't emit a 0x00 byte and BSD awk mangles bytes over
# 0x7f in a UTF-8 locale. No perl, no sound — never an error.
#
# Playback is afplay on macOS, paplay or aplay on Linux, each fired in the
# background so a frame never waits on audio. Sound plays on the machine
# running tmux — which, through a VS Code tunnel from an iPad, is not the
# machine in front of you. That is what the `bell` level is for: the lock
# command writes straight to the CLIENT's tty, so a BEL rings wherever you
# actually are. bell only rings for the big moments (a point, a life, a
# level), because a terminal bell per paddle hit is a migraine.
#
# Levels (@grid_saver_sound): off | low | med | high | bell. Off by default —
# a screensaver that starts beeping in an open-plan office ten minutes after
# you walk away is a surprise nobody asked for. @grid_mute (the 🔔 chip) wins
# over every level.

GRID_SOUND_VERSION=2
GRID_SOUND_LEVELS="off low med high bell"

: "${GRID_CONFIG:=$HOME/.config/claude-code-grid}"
GRID_SOUND_DIR="$GRID_CONFIG/sounds"

# grid_sound_player — the first player on this machine, or nothing.
grid_sound_player() {
  local p
  for p in afplay paplay aplay; do
    command -v "$p" >/dev/null 2>&1 && { echo "$p"; return; }
  done
}

# grid_sound_level_step <1|-1> <current> — the neighbour, wrapping.
grid_sound_level_step() {
  echo "$GRID_SOUND_LEVELS" | awk -v cur="$2" -v d="$1" '{
    for (i = 1; i <= NF; i++) if ($i == cur) {
      n = i + d; if (n < 1) n = NF; if (n > NF) n = 1; print $n; exit
    }
    print $1
  }'
}

# grid_sound_build — render the bank if it is missing or from an older
# version. A stamp file rather than a per-file check, so a bank half-written by
# an interrupted first run gets redone whole.
grid_sound_build() {
  [ "$(cat "$GRID_SOUND_DIR/.version" 2>/dev/null)" = "$GRID_SOUND_VERSION" ] && return 0
  command -v perl >/dev/null 2>&1 || return 1
  mkdir -p "$GRID_SOUND_DIR" 2>/dev/null || return 1
  perl - "$GRID_SOUND_DIR" <<'PERL' || return 1
use strict; use warnings;
my $dir = shift;
my $SR  = 22050;

# Each sound is a list of segments: [wave, f0, f1, seconds, volume, duty, curve]
#   wave  sq (square, duty 0..1) | tri | noise (f = sample-and-hold rate)
#   f0→f1 a linear pitch sweep across the segment
#   curve how hard the amplitude decays: 0 = held, 1 = linear, 3 = a pluck
my %S = (
  blip   => [['sq', 988, 988, .045, .55, .5, 1]],
  blop   => [['sq', 494, 494, .045, .55, .5, 1]],
  wall   => [['sq', 247, 247, .030, .45, .5, 1]],
  brick0 => [['sq', 1568,1568,.040, .45, .25,2]],
  brick1 => [['sq', 1319,1319,.040, .45, .25,2]],
  brick2 => [['sq', 1047,1047,.040, .45, .25,2]],
  brick3 => [['sq',  880, 880,.040, .45, .25,2]],
  brick4 => [['sq',  659, 659,.040, .45, .25,2]],
  point  => [['sq', 659, 659, .07, .5, .5, 0], ['sq', 880, 880, .07, .5, .5, 0],
             ['sq', 1319,1319,.16, .5, .5, 1]],
  miss   => [['sq', 440, 110, .40, .55, .5, .7], ['noise', 900, 300, .15, .4, 0, 2]],
  shoot  => [['sq', 1600, 400, .11, .35, .25, 1]],
  hit    => [['noise', 9000, 2500, .16, .55, 0, 2]],
  boom   => [['noise', 4000, 300, .55, .7, 0, 1.5]],
  march0 => [['sq',  98,  98, .075, .7, .5, .5]],
  march1 => [['sq',  92,  92, .075, .7, .5, .5]],
  march2 => [['sq',  87,  87, .075, .7, .5, .5]],
  march3 => [['sq',  82,  82, .075, .7, .5, .5]],
  saucer => [['vib', 1100, 14, .30, .30, .5, 0]],
  bonus  => [['sq', 1047,1047,.05, .45, .5, 0], ['sq', 1319,1319,.05, .45, .5, 0],
             ['sq', 1568,1568,.05, .45, .5, 0], ['sq', 2093,2093,.12, .45, .5, 1]],
  chomp  => [['sq', 700, 350, .045, .45, .5, 1], ['sq', 350, 700, .045, .45, .5, 1]],
  die    => [['sq', 880, 660, .12, .5, .5, 0], ['sq', 784, 587, .12, .5, .5, 0],
             ['sq', 698, 523, .12, .5, .5, 0], ['sq', 622, 220, .45, .5, .5, 1]],
  level  => [['sq', 523, 523, .07, .5, .5, 0], ['sq', 659, 659, .07, .5, .5, 0],
             ['sq', 784, 784, .07, .5, .5, 0], ['sq', 1047,1047,.07, .5, .5, 0],
             ['sq', 784, 784, .07, .5, .5, 0], ['sq', 1047,1047,.22, .5, .5, 1]],
  start  => [['tri', 392, 392, .09, .9, 0, 0], ['tri', 523, 523, .09, .9, 0, 0],
             ['tri', 659, 659, .09, .9, 0, 0], ['tri', 784, 784, .20, .9, 0, 1]],
);

srand(1977);
for my $name (sort keys %S) {
  my $pcm = '';
  for my $seg (@{ $S{$name} }) {
    my ($w, $f0, $f1, $dur, $vol, $duty, $curve) = @$seg;
    my $n = int($dur * $SR);
    my ($ph, $hold, $hph) = (0, 0, 1);
    for my $i (0 .. $n - 1) {
      my $t = $i / $n;
      my $v;
      if ($w eq 'vib') {               # the saucer: a square warbling at f1 Hz
        my $f = $f0 * (1 + .12 * sin(2 * 3.14159265 * $f1 * $i / $SR));
        $ph += $f / $SR; $ph -= int($ph);
        $v = $ph < .5 ? 1 : -1;
      } elsif ($w eq 'noise') {        # sample-and-hold: lower rate = crunchier
        my $f = $f0 + ($f1 - $f0) * $t;
        $hph += $f / $SR;
        if ($hph >= 1) { $hph -= int($hph); $hold = rand(2) - 1; }
        $v = $hold;
      } else {
        my $f = $f0 + ($f1 - $f0) * $t;
        $ph += $f / $SR; $ph -= int($ph);
        $v = $w eq 'tri' ? 4 * abs($ph - .5) - 1 : ($ph < $duty ? 1 : -1);
      }
      # 2ms attack and 4ms release on every segment: a square wave that starts
      # or stops at full height clicks, and the click is louder than the note.
      my $env = $curve ? (1 - $t) ** $curve : 1;
      my $a = $i / ($SR * .002); $env *= $a if $a < 1;
      my $r = ($n - $i) / ($SR * .004); $env *= $r if $r < 1;
      $pcm .= chr(128 + int(127 * $vol * $env * $v));
    }
  }
  open(my $fh, '>:raw', "$dir/$name.wav") or die "$dir/$name.wav: $!";
  print $fh 'RIFF', pack('V', 36 + length $pcm), 'WAVE',
            'fmt ', pack('VvvVVvv', 16, 1, 1, $SR, $SR, 1, 8),
            'data', pack('V', length $pcm), $pcm;
  close $fh;
}
PERL
  echo "$GRID_SOUND_VERSION" > "$GRID_SOUND_DIR/.version"
}

# grid_sound_play <name> <level> — fire one sound and return at once.
grid_sound_play() {
  local f="$GRID_SOUND_DIR/$1.wav" v
  [ -f "$f" ] || return 0
  case "$2" in low) v=15 ;; high) v=70 ;; *) v=35 ;; esac
  case "${GRID_SOUND_PLAYER:-}" in
    afplay) afplay -v "0.$v" "$f" >/dev/null 2>&1 & ;;
    paplay) paplay --volume=$(( 65536 * v / 100 )) "$f" >/dev/null 2>&1 & ;;
    aplay)  aplay -q "$f" >/dev/null 2>&1 & ;;
  esac
}

# ── The saver side ───────────────────────────────────────────────────────────
# sav_sound_init <session> — resolve the level the same way every saver option
# resolves (session option, then the file that survives a server restart, then
# the global) and get the bank ready. Leaves SAV_SOUND at off/low/med/high/bell.
sav_sound_init() {
  local s="$1" lvl='' m now
  [ -n "$s" ] && lvl=$(tmux show-options -v -t "$s" @grid_saver_sound 2>/dev/null)
  [ -n "$lvl" ] || [ -z "$s" ] || lvl=$(cat "$GRID_CONFIG/sound.$s" 2>/dev/null)
  [ -n "$lvl" ] || lvl=$(tmux show-options -gv @grid_saver_sound 2>/dev/null)
  case "$lvl" in low|med|high|bell) ;; *) lvl=off ;; esac

  # The mute chip means quiet, and a screensaver is not an exception to it.
  m=$(tmux show-options -gv @grid_mute 2>/dev/null)
  now=$(date +%s)
  if [ -n "$m" ] && [ "$m" -gt "$now" ] 2>/dev/null; then lvl=off; fi

  if [ "$lvl" != off ] && [ "$lvl" != bell ]; then
    GRID_SOUND_PLAYER=$(grid_sound_player)
    if [ -z "$GRID_SOUND_PLAYER" ] || ! grid_sound_build; then lvl=off; fi
  fi
  SAV_SOUND=$lvl
}

# sav_sound <name> — what a saver calls on an event. Cheap when off: one
# string comparison, no fork.
sav_sound() {
  case "$SAV_SOUND" in
    off) return 0 ;;
    bell)
      case "$1" in point|miss|die|level|bonus) printf '\a' ;; esac
      return 0 ;;
  esac
  grid_sound_play "$1" "$SAV_SOUND"
}
SAV_SOUND=off

# ── As a command ─────────────────────────────────────────────────────────────
if [ "${BASH_SOURCE[0]:-}" = "$0" ]; then
  GRID_SOUND_PLAYER=$(grid_sound_player)
  case "${1:-test}" in
    build) grid_sound_build && echo "sound bank: $GRID_SOUND_DIR" ;;
    play)  grid_sound_build && grid_sound_play "${2:?name}" "${3:-med}"; wait ;;
    test)
      grid_sound_build || { echo "no perl — can't synthesise the bank" >&2; exit 1; }
      [ -n "$GRID_SOUND_PLAYER" ] || { echo "no afplay/paplay/aplay on this machine" >&2; exit 1; }
      for f in "$GRID_SOUND_DIR"/*.wav; do
        n=$(basename "$f" .wav)
        printf '%s ' "$n"
        grid_sound_play "$n" "${2:-med}"; wait
      done
      echo ;;
    *) echo "usage: grid-sound.sh build | test [low|med|high] | play <name> [level]" >&2; exit 2 ;;
  esac
fi
