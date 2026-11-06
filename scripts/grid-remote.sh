#!/bin/bash
# grid-remote.sh — can this Mac's grid be reached from a phone or iPad, and
# if so, exactly how do you connect?
#
# The remote setup is Tailscale (reach the Mac from anywhere, no open ports)
# + mosh (the session survives wifi drops and wifi↔cellular handoffs, which
# plain SSH from Termius does not) + the grid's own mouse layer, so a tap
# does what ctrl+b 1 used to.
#
# Every link in that chain fails silently from the phone's side — you just
# get "connection refused" or a spinner — so this walks the chain on the Mac
# and says which link is missing:
#
#   ✓ Tailscale     connected as my-mac (100.x.y.z)
#   ✗ Remote Login  sshd isn't listening on :22
#       → System Settings → General → Sharing → Remote Login
#
# It changes nothing. The fixes all need sudo or a GUI click, and on a
# managed machine some of them are policy decisions, so it prints the fix
# rather than applying it.
set -u

ok=0 bad=0 warn=0
pass() { printf '  \033[1;32m✓\033[0m %-13s %s\n' "$1" "$2"; ok=$((ok + 1)); }
fail() { printf '  \033[1;31m✗\033[0m %-13s %s\n' "$1" "$2"; bad=$((bad + 1)); }
note() { printf '  \033[1;33m!\033[0m %-13s %s\n' "$1" "$2"; warn=$((warn + 1)); }
fix()  { printf '      \033[2m→ %s\033[0m\n' "$*"; }

printf '\033[1;36m▸ grid-remote\033[0m  checking %s\n\n' "$(scutil --get LocalHostName 2>/dev/null || hostname -s)"

# 1. Tailscale ---------------------------------------------------------------
# The standalone/App Store app ships its CLI inside the bundle and doesn't
# put it on PATH, so look there too.
ts=""
for c in tailscale /Applications/Tailscale.app/Contents/MacOS/Tailscale; do
  if command -v "$c" >/dev/null 2>&1; then ts="$c"; break; fi
done
host="" ip=""
if [ -z "$ts" ]; then
  fail Tailscale "not installed"
  fix "install from tailscale.com/download (or: brew install --cask tailscale-app), sign in, then install it on the phone with the same account"
elif ! json=$("$ts" status --json 2>/dev/null) || [ "$(printf '%s' "$json" | jq -r '.BackendState')" != Running ]; then
  fail Tailscale "installed but not connected"
  fix "open the Tailscale menu-bar app and sign in / toggle it on"
else
  host=$(printf '%s' "$json" | jq -r '.Self.DNSName // empty' | sed 's/\.$//')
  ip=$(printf '%s' "$json" | jq -r '.Self.TailscaleIPs[0] // empty')
  pass Tailscale "connected as ${host:-?} ($ip)"
fi

# 2. Remote Login (sshd) -----------------------------------------------------
# mosh bootstraps over SSH: it logs in, starts mosh-server, then hands off to
# UDP. No sshd, no mosh.
if nc -z -G 2 127.0.0.1 22 >/dev/null 2>&1; then
  pass "Remote Login" "sshd is listening on :22"
else
  fail "Remote Login" "sshd isn't listening on :22"
  fix "System Settings → General → Sharing → Remote Login (limit it to your user)"
fi

# 3. mosh-server -------------------------------------------------------------
# A non-interactive SSH login on macOS gets a bare PATH without
# /opt/homebrew/bin, so the phone's mosh client can't find mosh-server by
# name. The connect recipe below passes the full path rather than relying on
# PATH, so it doesn't matter what the login shell does.
moshd=$(command -v mosh-server 2>/dev/null || true)
if [ -z "$moshd" ]; then
  fail mosh "mosh-server not installed"
  fix "brew install mosh"
else
  pass mosh "$moshd ($(mosh-server --version 2>/dev/null | head -1 | sed -n 's/.*(mosh \([^)]*\)).*/\1/p'))"
fi

# 4. Application firewall ----------------------------------------------------
# mosh-server listens on a UDP port in 60000–61000. Homebrew binaries are only
# ad-hoc signed, so "automatically allow signed software" doesn't cover them.
# Instead the firewall raises an allow/deny prompt on the Mac's screen, nobody
# is there to click it, and the phone hangs on "mosh: Nothing received from
# server". Rules are keyed on the resolved Cellar path, so a `brew upgrade
# mosh` lands on a new path and silently needs the rule again.
fw=/usr/libexec/ApplicationFirewall/socketfilterfw
if [ -x "$fw" ] && "$fw" --getglobalstate 2>/dev/null | grep -q 'enabled'; then
  if [ -n "$moshd" ]; then
    real=$(realpath "$moshd")
    if "$fw" --listapps 2>/dev/null | grep -A1 -F "$real" | grep -q 'Allow incoming'; then
      pass Firewall "on, and mosh-server is allowed"
    else
      fail Firewall "on, and mosh-server has no allow rule (UDP will be dropped)"
      fix "sudo $fw --add $real && sudo $fw --unblockapp $real"
    fi
  else
    note Firewall "on; add a mosh-server rule once mosh is installed"
  fi
else
  pass Firewall "off"
fi

# 5. Sleep -------------------------------------------------------------------
# A sleeping Mac is unreachable however good the tunnel is. On a laptop,
# closing the lid sleeps it outright unless it's on power with an external
# display, and no pmset setting changes that.
if pmset -g batt 2>/dev/null | head -1 | grep -q 'Battery Power'; then
  note Power "on battery; it will sleep, and with the lid closed it's unreachable"
  fix "remote access needs it on the charger and awake: caffeinate -s keeps it up while on power"
else
  s=$(pmset -g 2>/dev/null | awk '$1 == "sleep" {print $2; exit}')
  if [ "${s:-0}" = 0 ]; then
    pass Power "on power, system sleep disabled"
  else
    note Power "on power, but system sleep is ${s} min"
    fix "sudo pmset -c sleep 0   (never sleep while on the charger), or caffeinate -s while you're away"
  fi
fi

# 6. The grid itself ---------------------------------------------------------
# window-size latest means the most recently active client sets the size:
# typing on the phone fits the grid to the phone, and the first keystroke back
# at the Mac re-expands it. smallest would pin the Mac to phone size for as
# long as the phone stays attached.
if sessions=$(tmux list-sessions -F '#{session_name}' 2>/dev/null) && [ -n "$sessions" ]; then
  pass Grid "running: $(printf '%s' "$sessions" | paste -sd, - | sed 's/,/, /g')"
  wsize=$(tmux show -gv window-size 2>/dev/null)
  if [ "$wsize" != latest ]; then
    note "Window size" "window-size is '$wsize', so a phone client can shrink the Mac's grid"
    fix "tmux set -g window-size latest"
  fi
else
  note Grid "no tmux sessions; pdev / wdev will start one from the phone too"
fi

# Verdict + how to connect --------------------------------------------------
echo
if [ "$bad" -gt 0 ]; then
  printf '\033[1;31m%d blocking, %d warning.\033[0m Fix the ✗ lines, then run grid-remote again.\n' "$bad" "$warn"
  exit 1
fi

target="$(whoami)@${host:-${ip:-<tailscale-name>}}"
cat <<EOF
$(printf '\033[1;32mReady.\033[0m')  From the phone or iPad (Blink Shell or Termius, both speak mosh):

  host        ${host:-${ip}}
  user        $(whoami)
  auth        an SSH key (put the phone's public key in ~/.ssh/authorized_keys)
  mosh server ${moshd}

  Blink:  mosh --server=${moshd} ${target}
          (or add a Host with "Mosh Server: ${moshd}", then: mosh <name>)

Then type pdev or wdev. It attaches to the running grid, and the toolbar
chips, ≡ menu, and ▲▼ page chips all take taps.
EOF
