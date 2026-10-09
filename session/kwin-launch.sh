#!/usr/bin/env bash
# Started by plasma-kwin_wayland.service (see the drop-in in ~/.config/systemd/user).
# Runs the patched KWin from ~/kde/live when it is safe to, otherwise the system one.
source "${PT_HOME:-$HOME/kde}/session/common.sh"
STOCK="${PT_STOCK_KWIN:-/usr/bin/kwin_wayland_wrapper}"
# A patched KWin that goes away by itself sooner than this after starting, or that is
# cut off (power cycle) sooner than this, is not used again.
GRACE="${PT_GRACE:-300}"

stock() {
  rm -f "$PT_ACTIVE"
  exec "$STOCK" "$@"
}

# A newer build waiting to be switched to. Only done here, at login, when nothing is
# running from the old one. ~/kde/live is a symlink to the build in use.
if [[ -f "$PT_HOME/live-next" ]]; then
  next="$(<"$PT_HOME/live-next")"
  rm -f "$PT_HOME/live-next"
  if [[ -n "$next" && "$next" != */* && -x "$PT_HOME/$next/bin/kwin_wayland_wrapper" && -x "$PT_HOME/$next/bin/kwin_wayland" \
        && -f "$PT_HOME/$next/host-versions.stamp" && -d "$PT_HOME/$next/plasma-overlay/lib64" ]]; then
    if [[ -d "$PT_LIVE" && ! -L "$PT_LIVE" ]]; then
      mv -T "$PT_LIVE" "$PT_HOME/live-old-$(date +%Y%m%d-%H%M%S)"
    fi
    if [[ ! -e "$PT_LIVE" || -L "$PT_LIVE" ]] && ln -sfn "$next" "$PT_LIVE"; then
      # What the old build did says nothing about the new one.
      rm -f "$PT_STATE/FAILED" "$PT_STATE/STARTING" "$PT_STATE/SHELL_FAILED"
      pt_log "kwin: switched the live build to $next"
    else
      pt_log "kwin: could not switch the live build to $next"
    fi
  else
    pt_log "kwin: ignoring live-next, no complete build in '$next'"
  fi
fi

if ! pt_usable; then
  pt_log "kwin: using system KWin — $PT_REASON"
  stock "$@"
fi

# Still there from the last time: that start neither lasted $GRACE seconds nor was it
# stopped in the normal way (a hang ended with the power button, for example).
if [[ -e "$PT_STATE/STARTING" ]]; then
  pt_log "kwin: the previous patched start did not survive — using system KWin"
  mv "$PT_STATE/STARTING" "$PT_STATE/FAILED"
  stock "$@"
fi

if ! pt_preflight_kwin; then
  pt_log "kwin: using system KWin — $PT_REASON"
  touch "$PT_STATE/FAILED"
  stock "$@"
fi

touch "$PT_STATE/STARTING"
( sleep "$GRACE"; rm -f "$PT_STATE/STARTING" ) &
sleeper=$!

# Logging out, rebooting and "systemctl stop" all end this service with SIGTERM. That
# is a normal end, however soon it comes. bash runs the handler once the wrapper is gone.
stopped=0
trap 'stopped=1' TERM INT HUP

pt_log "kwin: starting patched KWin from $PT_LIVE"
touch "$PT_ACTIVE"
started=$SECONDS
(
  trap - TERM INT HUP
  # The wrapper starts "kwin_wayland" from PATH, so the patched one has to come first.
  export PATH="$PT_LIVE/bin:$PATH"
  export LD_LIBRARY_PATH="$PT_LIVE/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  export QT_PLUGIN_PATH="$PT_LIVE/lib64/plugins${QT_PLUGIN_PATH:+:$QT_PLUGIN_PATH}"
  export QML_IMPORT_PATH="$PT_LIVE/lib64/qml${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}"
  export XDG_DATA_DIRS="$PT_LIVE/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
  exec "$PT_LIVE/bin/kwin_wayland_wrapper" "$@"
)
status=$?
ran=$((SECONDS - started))
kill "$sleeper" 2>/dev/null

if (( stopped )); then
  rm -f "$PT_STATE/STARTING"
  pt_log "kwin: patched KWin stopped with the session after ${ran}s"
  exit 0
fi

# Nobody asked it to stop. The wrapper restarts a crashing KWin a number of times and
# then gives up with exit status 0, so the status says little; going away this soon
# does. Remember it, and try to bring up the system KWin so the login still works
# (systemd may end the session anyway if the wrapper already had its D-Bus name; the
# next login then uses the system KWin).
if (( ran < GRACE )); then
  touch "$PT_STATE/FAILED"
  rm -f "$PT_STATE/STARTING"
  pt_log "kwin: patched KWin went away by itself after ${ran}s (status $status) — falling back to system KWin"
  stock "$@"
fi
rm -f "$PT_STATE/STARTING"
pt_log "kwin: patched KWin exited with status $status after ${ran}s"
exit $status
