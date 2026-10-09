#!/usr/bin/env bash
# Started by plasma-plasmashell.service. Runs the system plasmashell; when the patched
# KWin is in use it also lends it the patched task manager library and pager applet.
source "${PT_HOME:-$HOME/kde}/session/common.sh"
OVERLAY="$PT_LIVE/plasma-overlay"
SHELL_BIN="${PT_STOCK_SHELL:-/usr/bin/plasmashell}"
STARTS="$PT_RUNTIME/pager-thumbnails-shell-starts"

use_overlay() {
  [[ -e "$PT_ACTIVE" && -d "$OVERLAY/lib64" ]] || { PT_REASON=""; return 1; }
  if [[ -e "$PT_STATE/SHELL_FAILED" ]]; then
    PT_REASON="it kept crashing with the patched pager earlier (delete ~/kde/session/SHELL_FAILED to retry)"; return 1; fi
  pt_preflight_overlay || return 1
  # systemd restarts a crashed plasmashell, three times a minute at most. If this is
  # the third start with the patched pager in a short while, the pager is the suspect.
  local now recent
  now=$(date +%s)
  echo "$now" >> "$STARTS"
  recent=$(awk -v now="$now" 'now - $1 < 90' "$STARTS" | wc -l)
  if (( recent >= 3 )); then
    touch "$PT_STATE/SHELL_FAILED"
    PT_REASON="it was started $recent times within 90 seconds with the patched pager"; return 1
  fi
  return 0
}

if use_overlay; then
  # plasmashell isn't running yet, so this is the one safe moment to edit its config.
  if [[ -e "$PT_STATE/ENABLE_ON_NEXT_START" ]]; then
    rc="${XDG_CONFIG_HOME:-$HOME/.config}/plasma-org.kde.plasma.desktop-appletsrc"
    awk -F'[][]' '/^\[Containments\]\[[0-9]+\]\[Applets\]\[[0-9]+\]$/ {c=$4; a=$8} /^plugin=org.kde.plasma.pager$/ {print c, a}' "$rc" |
    while read -r c a; do
      kwriteconfig6 --file "$rc" --group Containments --group "$c" --group Applets --group "$a" \
        --group Configuration --group General --key showThumbnails true
      pt_log "plasmashell: switched on thumbnails for pager $a in containment $c"
    done
    rm -f "$PT_STATE/ENABLE_ON_NEXT_START"
  fi
  export LD_LIBRARY_PATH="$OVERLAY/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  export QT_PLUGIN_PATH="$OVERLAY/plugins${QT_PLUGIN_PATH:+:$QT_PLUGIN_PATH}"
  pt_log "plasmashell: starting with patched pager"
else
  pt_log "plasmashell: starting unmodified${PT_REASON:+ — $PT_REASON}"
fi
exec "$SHELL_BIN" "$@"
