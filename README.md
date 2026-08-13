# claude-code-grid

One command to launch a tiled tmux grid of [Claude Code](https://claude.com/claude-code)
sessions — one pane per repo — that reads as a **dashboard**: every border
shows what that session is doing and how long it's been doing it, so four
concurrent agents become a queue you work through instead of four scrollbacks
you keep re-scanning.

```
┌─ ▶ shipvane-engine (main) ✓ 3m ─┬─ ▲ lazy-creator-engine (dev) ● 6m ─┐
│                                 │                                    │
│   Claude Code — working         │   Claude Code — needs you           │
│                                 │                                    │
├─ ✔ punch-pwa (dev) ✓ 41s ───────┼─ ⦿ · pitchvault (main) ✓ ──────────┤
│                                 │                                    │
│   Claude Code — turn finished   │   Claude Code — idle, marked        │
│                                 │                                    │
└──────────────────── ▲1 ✔1 ▶1  ⚡61% ↻12:40am  7d:22%  12:40 ─────────┘
```

| marker | meaning                                             |
| ------ | --------------------------------------------------- |
| `▲`    | blocked on you — needs input or a permission answer |
| `▶`    | working                                             |
| `✔`    | finished its turn, ready for review                 |
| `·`    | idle                                                |
| `⦿`    | marked for targeted broadcast (`prefix+m`)          |
| `●/✓`  | uncommitted changes / clean                         |
| `3m`   | how long it's been in that state                    |

## Commands

Two grids out of the box, each tied to a repo root and a Claude account
profile (`CLAUDE_CONFIG_DIR=~/.claude-<profile>`):

| command                   | what it does                                                                                             |
| ------------------------- | -------------------------------------------------------------------------------------------------------- |
| `pdev` / `wdev`           | launch (or reattach) the personal / work grid with your last-picked repos; opens the picker on first run |
| `pdev-pick` / `wdev-pick` | fzf multi-select which repos get panes (tab = toggle, enter = launch); remembered for next time          |
| `pdev-stop` / `wdev-stop` | tear down + safe-prune Claude's auto-created worktrees                                                   |
| `grid-add [repo]`         | give another repo a pane without rebuilding the grid                                                     |
| `grid-drop`               | close the current pane's repo                                                                            |
| `grid-note "<text>"`      | leave a note the other panes' sessions will read                                                         |
| `grid-board`              | show the shared cross-repo board                                                                         |

## Keys

`prefix` is tmux's default `Ctrl-b` unless you've remapped it. **`prefix+?`
shows this table in a popup**, so it's one keypress away rather than a
README lookup.

| key                               | what it does                                                                     |
| --------------------------------- | -------------------------------------------------------------------------------- |
| `prefix+?`                        | cheatsheet popup — every key below, plus what the border glyphs mean             |
| `prefix+n`                        | **jump to the pane that most wants you** — blocked first, longest-waiting first; repeat to cycle |
| `prefix+m`                        | mark/unmark this pane for targeted broadcast (`⦿` in its border)                 |
| `prefix+p` / `prefix+P`           | pick a saved prompt → send to this pane / to the marked panes (all, if none marked) |
| `prefix+b`                        | broadcast mode — type into ALL panes at once (status bar shows a red banner)      |
| `prefix+g`                        | popup: every repo's branch, ahead/behind, dirty state, last commit                |
| `prefix+B`                        | popup: the shared cross-repo board                                                |
| `prefix+L`                        | popup: the worktree prune log — what was kept, and why                            |
| `prefix+a` / `prefix+X`           | add a repo's pane / drop this one (drop asks first)                               |
| `prefix+z`                        | zoom a pane full-screen and back (tmux built-in)                                  |
| `prefix+Ctrl-s` / `prefix+Ctrl-r` | manual layout save / restore (tmux-resurrect)                                     |

## Install

```sh
git clone https://github.com/gigadude1982/claude-code-grid ~/dev/claude-code-grid
~/dev/claude-code-grid/install.sh
```

The installer: brew-installs missing deps (`tmux`, `fzf`, `jq`,
`terminal-notifier`); creates `~/.config/claude-code-grid/` with a fresh
random ntfy topic; seeds a starter prompt library; clones **pinned**
tmux-resurrect/continuum; adds one `source` line each to `~/.zshrc` and
`~/.tmux.conf`; and merges the grid's hooks into each profile's
`settings.json` with `jq` — idempotently, backing the file up first and
leaving every other hook untouched. Re-run it any time.

Configure roots/profiles in `~/.zshrc` _before_ the source line:

```zsh
export GRID_PERSONAL_ROOT=~/dev        # default
export GRID_WORK_ROOT=~/bounteous      # default ~/work
source ~/dev/claude-code-grid/zsh/grid.zsh
```

## Features

- **The grid is a dashboard.** Claude Code hooks report each session's state
  into tmux pane options (`scripts/pane-state.sh`), and the border renders it:
  glyph, elapsed time, and a frame that turns red the moment a pane blocks on
  you. The status bar carries the rollup (`▲1 ✔1 ▶1`). With four sessions the
  scarce resource is your attention, not screen space — `prefix+n` turns that
  into a work queue.
- **Pane borders that stay put** — repo name (per-repo color), current branch,
  live git dirty/clean indicator. Claude Code overwrites tmux's `pane_title`
  via terminal escapes, so labels ride on `@repo` pane user-options instead.
- **Reshape a running grid** — `grid-add` / `grid-drop` add and remove repo
  panes in place, instead of killing the session and re-picking (which threw
  away three healthy conversations to change the fourth).
- **Targeted broadcast** — `prefix+b` still types into every pane, but
  `prefix+m` marks a subset first, because "commit and push" is usually right
  for three panes and actively wrong for the one mid-refactor. Saved prompts
  in `~/.config/claude-code-grid/prompts/` go to either, delivered as a
  bracketed paste so multi-line prompts arrive as one message.
- **Shared cross-repo board** — four sessions in four repos can't see each
  other, so the one that just changed an API contract can't warn the one that
  consumes it. `grid-note "…"` appends to a per-grid markdown file, and a
  `SessionStart` hook injects it into every pane's context at startup — no
  per-repo `CLAUDE.md` wiring needed.
- **Popups instead of pane-stealing** — cross-repo git status, the board, and
  the prune log are all one keypress away without spending grid real estate on
  a control shell.
- **Account usage in the status bar** — 5-hour and 7-day plan windows with
  reset time, colored by threshold, switching automatically between your
  personal/work accounts based on the attached session. Reads the cache
  maintained by [claude-status-line](https://github.com/gigadude1982/claude-status-line)
  — zero extra API calls.
- **Notifications** — a macOS banner (and optional [ntfy](https://ntfy.sh)
  phone push) for every session, tagged with the repo and classified by what
  actually happened: ✅ finished normally (silent, with a one-line summary of
  the last reply), 💬/⚠️/❓ waiting on you (sound — permission prompt, plain
  input, or an interactive dialog get distinct icons), ❌ the turn died on an
  API error (sound). The phone push only fires once the Mac's been idle a
  while (`ioreg` HID idle time), so you're only pinged when you've actually
  walked away. Click a banner (or tap the push, if you've set
  `NTFY_CLICK_URL`) to jump straight back to the pane that sent it.
- **ASCII art splash screens** — each pane opens on a full-pane art piece
  (rocket, skull, storm cloud, block-letter CLAUDE, …) tinted to match its
  border color. The piece is chosen by **hashing the repo name**, so a repo
  keeps the same art forever and becomes recognisable before you've read the
  label. `GRID_SPLASH_ART=<name>` pins one; panes too small for art get just
  the repo/branch line.
- **Worktree auto-cleanup** — if you run Claude through a `--worktree` wrapper,
  each pane's auto-created worktree is tracked the moment it appears and
  removed at teardown **only if** it has no uncommitted changes and no commits
  unreachable from other branches; everything else is kept and logged
  (`prefix+L`). Sweeps run at stop, on tmux session close, and at next launch —
  so kill-server and reboots can't leak worktrees.
- **Reboot persistence that actually resumes** — tmux-resurrect + continuum
  restore the layout and directories; a post-restore hook
  (`scripts/grid-restore.sh`) then rebuilds each pane's label and color and
  relaunches Claude with `--continue` wherever a stored conversation exists. A
  reboot picks up mid-conversation instead of leaving four anonymous shells.

## Repo layout

```
scripts/         the engine + helpers (all standalone, no state in-repo)
  start-grid.sh    builds the session; grid-pane.sh dresses each pane
  pane-state.sh    Claude hook → per-pane @state (the dashboard's input)
  pane-border.sh   border label; grid-rollup.sh → status bar
  claude-notify.sh Claude hook → macOS banner + ntfy push, classified by
                   event (Stop/StopFailure/Notification type)
  grid-notify-click.sh  "click for more details" — jump to the pane that
                   fired a banner (invoked by claude-notify.sh's -execute)
  grid-next.sh     prefix+n attention queue
  grid-add/drop    reshape a live grid
  grid-prompt/mark saved prompts + targeted broadcast
  grid-board.sh    shared cross-repo board (note / show / SessionStart inject)
  grid-git/log.sh  popups
  grid-help.sh     prefix+? cheatsheet
  grid-restore.sh  post-reboot relaunch with --continue
  grid-lib.sh      shared helpers (sourced, POSIX subset — see gotchas)
zsh/grid.zsh     pdev/wdev command families, claude_tracked launcher
tmux/grid.tmux.conf
config/ntfy.conf.template
install.sh
```

Runtime state lives in `~/.config/claude-code-grid/`: `<session>.repos` (last
picker selection), `<session>.env` (root/profile, for restore),
`<session>.worktrees` (tracked worktrees), `<session>.board.md` (shared
board), `<session>.log` (prune decisions), `prompts/` (prompt library),
`ntfy.conf` (your topic — keep private).

## Hard-won gotchas encoded here

- `tmux set-option -p` without `-t` targets the window's _active_ pane, not
  the pane running the command — always pass `-t "$TMUX_PANE"`.
- **`#()` in a format is cached** and only re-runs on `status-interval`, so a
  state glyph rendered by a shell script lags the actual transition by up to
  15s. The glyph is drawn with native `#{?...}` conditionals on `@state`
  (instant); only git and elapsed time go through the script.
- **A comma inside `#{?...}` is the argument separator**, so styles in a
  conditional must be written `#[fg=colour203]#[bold]`, never
  `#[fg=colour203,bold]` — the latter splits the conditional in the wrong place.
- **An unquoted `#{...}` in a tmux command argument starts a comment.**
  `-e GRID_SESSION=#{session_name}` is a syntax error that swallows the rest
  of the line; it must be `-e "GRID_SESSION=#{session_name}"`.
- **A `display-popup` is not a pane** — a script running in one can't ask tmux
  which pane it's in, and falling back to "the current client's session" makes
  a popup act on the wrong grid. The bindings capture `#{pane_id}` /
  `#{session_name}` at press time and pass them in via `-e`.
- `$TMUX_PANE` is inherited all the way down tmux → shell → claude → hook (and
  → Claude's Bash tool), which is what lets a hook address its own pane. But a
  hook that fires for *every* Claude session must verify it landed on a pane
  with `@repo` set — otherwise a session started in an ordinary terminal
  resolves to the most-recently-used tmux session and gets another grid's
  context injected as fact.
- Claude encodes a project directory by replacing every non-alphanumeric
  character with `-` (`/Users/x/dev/foo` → `-Users-x-dev-foo`). Checking for
  that directory is how `grid-restore.sh` knows whether `--continue` will work;
  bare `--continue` errors out when there's no stored conversation.
- `git branch --contains` prefixes branches checked out in other worktrees with
  `+` (not `*`) — strip both or a worktree's own branch looks like "reachable
  elsewhere" and safe-prune isn't safe.
- tmux-continuum must load _after_ `status-right` is set (it injects its
  autosave trigger into it), and its master branch has shipped broken — stay on
  the pinned tags.
- zsh expands aliases inside function bodies at _definition_ time; the grid
  launches Claude via `CLAUDE_CONFIG_DIR=... claude` rather than profile
  aliases for exactly that reason.
- zsh arrays are 1-indexed and bash's are 0-indexed, so `grid-lib.sh` — sourced
  by both — keeps to a space-separated string plus `awk` indexing.

## Requirements

macOS, zsh, tmux ≥ 3.2 (popups; developed on 3.7), Homebrew. Notifications
need `terminal-notifier`; usage readout needs claude-status-line's statusline
(optional — degrades to nothing). Linux would need light porting (`ioreg`,
`terminal-notifier`, `getconf DARWIN_USER_TEMP_DIR`).

## License

MIT
