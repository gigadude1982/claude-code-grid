# claude-code-grid

One command to launch a tiled tmux grid of [Claude Code](https://claude.com/claude-code)
sessions — one pane per repo — with colored borders, git status at a glance,
account usage in the status bar, desktop + phone notifications, safe
auto-cleanup of Claude's git worktrees, and layouts that survive reboots.

```
┌─ shipvane-engine (main) ✓ ──────┬─ lazy-creator-engine (dev) ● ───┐
│                                 │                                 │
│   Claude Code                   │   Claude Code                   │
│                                 │                                 │
├─ punch-pwa (dev) ✓ ─────────────┼─ pitchvault (main) ✓ ───────────┤
│                                 │                                 │
│   Claude Code                   │   Claude Code                   │
│                                 │                                 │
└─────────────────────────────────┴─────────────────⚡61% ↻12:40am──┘
```

## Commands

Two grids out of the box, each tied to a repo root and a Claude account
profile (`CLAUDE_CONFIG_DIR=~/.claude-<profile>`):

| command                           | what it does                                                                                             |
| --------------------------------- | -------------------------------------------------------------------------------------------------------- |
| `pdev` / `wdev`                   | launch (or reattach) the personal / work grid with your last-picked repos; opens the picker on first run |
| `pdev-pick` / `wdev-pick`         | fzf multi-select which repos get panes (tab = toggle, enter = launch); remembered for next time          |
| `pdev-stop` / `wdev-stop`         | tear down + safe-prune Claude's auto-created worktrees                                                   |
| `prefix+b`                        | broadcast mode — type into ALL panes at once (status bar shows a red banner while on)                    |
| `prefix+z`                        | zoom a pane full-screen and back (tmux built-in)                                                         |
| `prefix+Ctrl-s` / `prefix+Ctrl-r` | manual layout save / restore (tmux-resurrect)                                                            |

## Install

```sh
git clone https://github.com/gigadude1982/claude-code-grid ~/dev/claude-code-grid
~/dev/claude-code-grid/install.sh
```

The installer: brew-installs missing deps (`tmux`, `fzf`, `jq`,
`terminal-notifier`), creates `~/.config/claude-code-grid/` with a fresh
random ntfy topic, clones **pinned** tmux-resurrect/continuum, and adds one
`source` line each to `~/.zshrc` and `~/.tmux.conf`. It prints the one
manual step: adding the notification hook to your Claude settings.json.

Configure roots/profiles in `~/.zshrc` _before_ the source line:

```zsh
export GRID_PERSONAL_ROOT=~/dev        # default
export GRID_WORK_ROOT=~/bounteous      # default ~/work
source ~/dev/claude-code-grid/zsh/grid.zsh
```

## Features

- **ASCII art splash screens** — each pane opens on a random full-pane art
  piece (rocket, skull, storm cloud, block-letter CLAUDE, …) tinted to match
  its border color, with the repo/branch line beneath. It fills Claude's
  startup delay and reappears whenever Claude exits, since Claude runs on
  the alternate screen. `GRID_SPLASH_ART=<name>` pins a favorite; panes too
  small for art get just the repo/branch line.
- **Pane borders that stay put** — repo name (per-repo color), current
  branch, and a live `●` dirty / `✓` clean git indicator. Claude Code
  overwrites tmux's `pane_title` via terminal escapes, so labels ride on
  `@repo` pane user-options instead.
- **Account usage in the status bar** — 5-hour and 7-day plan windows with
  reset time, colored by threshold, switching automatically between your
  personal/work accounts based on the attached session. Reads the cache
  maintained by [claude-status-line](https://github.com/gigadude1982/claude-status-line)
  — zero extra API calls.
- **Notifications** — macOS banner when any session finishes (silent) or
  needs input (sound), tagged with the repo. Optionally an
  [ntfy](https://ntfy.sh) push to your phone — but only when the Mac has
  been idle a while (`ioreg` HID idle time), so you're only pinged when
  you've actually walked away.
- **Worktree auto-cleanup** — if you run Claude through a `--worktree`
  wrapper, each pane's auto-created worktree is tracked the moment it
  appears and removed at teardown **only if** it has no uncommitted changes
  and no commits unreachable from other branches; everything else is kept
  and logged. Sweeps run at stop, on tmux session close, and at next
  launch — so kill-server and reboots can't leak worktrees.
- **Reboot persistence** — tmux-resurrect + continuum (auto-save every
  10 min, auto-restore on first server start). Panes come back as shells in
  their repo dirs; `claude --resume` picks conversations back up.

## Repo layout

```
scripts/         the engine + helpers (all standalone, no state in-repo)
zsh/grid.zsh     pdev/wdev command families, claude_tracked launcher
tmux/grid.tmux.conf
config/ntfy.conf.template
install.sh
```

Runtime state lives in `~/.config/claude-code-grid/`: `<session>.repos`
(last picker selection), `<session>.worktrees` (tracked worktrees),
`<session>.log` (prune decisions), `ntfy.conf` (your topic — keep private).

## Hard-won gotchas encoded here

- `tmux set-option -p` without `-t` targets the window's _active_ pane, not
  the pane running the command — always pass `-t "$TMUX_PANE"`.
- `git branch --contains` prefixes branches checked out in other worktrees
  with `+` (not `*`) — strip both or a worktree's own branch looks like
  "reachable elsewhere" and safe-prune isn't safe.
- tmux-continuum must load _after_ `status-right` is set (it injects its
  autosave trigger into it), and its master branch has shipped broken —
  stay on the pinned tags.
- zsh expands aliases inside function bodies at _definition_ time; the grid
  launches Claude via `CLAUDE_CONFIG_DIR=... claude` rather than profile
  aliases for exactly that reason.

## Requirements

macOS, zsh, tmux ≥ 3.2, Homebrew. Notifications need `terminal-notifier`;
usage readout needs claude-status-line's statusline (optional — degrades to
nothing). Linux would need light porting (`ioreg`, `terminal-notifier`,
`getconf DARWIN_USER_TEMP_DIR`).

## License

MIT
