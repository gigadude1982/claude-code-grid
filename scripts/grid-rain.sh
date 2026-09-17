#!/bin/bash
# grid-rain.sh — kept as an alias for grid-saver.sh.
#
# The matrix rain grew into a screensaver host with several effects, and the
# animation moved to scripts/savers/matrix.sh. This file stays because a
# running tmux server holds `lock-command` as a string: between `git pull` and
# `prefix+R`, the live server is still pointing here, and deleting it would
# mean the idle timer firing into a missing file — a client that locks and
# instantly unlocks, on every grid anyone hadn't reloaded yet.
#
# Safe to delete once no tmux server anywhere still names it.
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/grid-saver.sh" "$@"
