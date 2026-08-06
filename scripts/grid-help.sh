#!/bin/bash
# grid-help.sh — the grid's keys and border glyphs, in one popup.
#
# Bound to prefix+?, shadowing tmux's default list-keys. That default dumps
# ~200 bindings, almost none of which are the grid's, so it's the wrong thing
# to land on when the question is "what was the key for the board again?".
# The pointer at the bottom gets you to the real list-keys.
#
# The prefix is read from tmux rather than hardcoded, so this stays honest if
# it's ever remapped off C-b.
set -u

p=$(tmux show-options -gv prefix 2>/dev/null)
[ -n "$p" ] || p="C-b"

esc=$'\033'
b="${esc}[1m" d="${esc}[2m" r="${esc}[0m"
key="${esc}[38;5;221m"                       # keys — amber
hd="${esc}[38;5;45m"                         # section headings — grid blue
red="${esc}[38;5;203m" grn="${esc}[38;5;114m" cyn="${esc}[38;5;81m" gry="${esc}[38;5;240m"

k() { printf "   ${key}%-3s${r} %s\n" "$1" "$2"; }

printf '\n %sclaude-code-grid%s   %spress %s then:%s\n' "$b" "$r" "$d" "$p" "$r"

printf '\n %sATTENTION%s\n' "$hd" "$r"
k n "jump to the pane that wants you — blocked first, longest waiting first"
k z "zoom this pane full-screen / back"

printf '\n %sSEND%s\n' "$hd" "$r"
k m "mark / unmark this pane for targeted broadcast"
k p "saved prompt → this pane"
k P "saved prompt → the marked panes (or all of them, if none are marked)"
k b "broadcast: type into ALL panes at once (toggle)"

printf '\n %sLOOK%s\n' "$hd" "$r"
k g "git status across every repo in the grid"
k B "shared cross-repo board"
k L "worktree prune log — what was kept, and why"

printf '\n %sRESHAPE%s\n' "$hd" "$r"
k a "add a repo's pane"
k X "drop this pane's repo (asks first)"

printf '\n %sBORDERS%s\n' "$hd" "$r"
printf "   %s▲%s blocked on you   %s▶%s working   %s✔%s finished   %s·%s idle\n" \
  "$red" "$r" "$cyn" "$r" "$grn" "$r" "$gry" "$r"
printf "   %s⦿%s marked          %s●%s uncommitted  %s✓%s clean       %s3m%s in that state\n" \
  "$key" "$r" "$red" "$r" "$grn" "$r" "$gry" "$r"

printf '\n %sFROM THE SHELL%s\n' "$hd" "$r"
printf "   %sgrid-add%s [repo]   %sgrid-drop%s   %sgrid-note%s \"…\"   %sgrid-board%s\n" \
  "$key" "$r" "$key" "$r" "$key" "$r" "$key" "$r"
printf "   %spdev%s / %spdev-pick%s / %spdev-stop%s      %s(wdev… for the work grid)%s\n" \
  "$key" "$r" "$key" "$r" "$key" "$r" "$d" "$r"

printf '\n %s%s : list-keys   for tmux'"'"'s own bindings%s\n' "$d" "$p" "$r"
printf '\n %spress any key%s' "$d" "$r"
# `|| true`: read returns non-zero on EOF, which happens whenever this is run
# with stdin redirected rather than in the popup's tty.
read -rsn1 || true
