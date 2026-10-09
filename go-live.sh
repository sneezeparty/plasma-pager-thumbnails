#!/usr/bin/env bash
# Makes the real session use the patched KWin + pager from the next login on.
# Undo with ~/kde/rollback.sh.
set -euo pipefail
source "$HOME/kde/session/common.sh"
U="$HOME/.config/systemd/user"

[[ -x "$PT_LIVE/bin/kwin_wayland_wrapper" ]] || { echo "No live build in $PT_LIVE — run build-live.sh first."; exit 1; }
# The stamp says which system packages the build was made for. A build that has one
# for other versions has to be rebuilt, not re-stamped (--restamp overrides, for a
# build known to have been made against the current packages).
if [[ -f "$PT_LIVE/host-versions.stamp" && "${1:-}" != "--restamp" ]]; then
  if [[ "$(pt_versions)" != "$(cat "$PT_LIVE/host-versions.stamp")" ]]; then
    echo "The build in $PT_LIVE was made for other package versions — rebuild it (see README.md)."; exit 1
  fi
else
  pt_versions > "$PT_LIVE/host-versions.stamp"
fi
pt_preflight_kwin || { echo "$PT_REASON"; exit 1; }
pt_preflight_overlay || { echo "$PT_REASON"; exit 1; }
rm -f "$PT_STATE/FAILED" "$PT_STATE/STARTING" "$PT_STATE/SHELL_FAILED" "$PT_HOME/DISABLE"
touch "$PT_STATE/ENABLE_ON_NEXT_START"

mkdir -p "$U/plasma-kwin_wayland.service.d" "$U/plasma-plasmashell.service.d"
cat > "$U/plasma-kwin_wayland.service.d/50-pager-thumbnails.conf" <<'UNIT'
# Pager thumbnails prototype — see ~/kde/README.md. Remove with ~/kde/rollback.sh.
# Falls back to the system KWin if ~/kde is gone.
[Service]
ExecStart=
ExecStart=/bin/sh -c 'if [ -x "%h/kde/session/kwin-launch.sh" ]; then exec "%h/kde/session/kwin-launch.sh" --xwayland; else exec /usr/bin/kwin_wayland_wrapper --xwayland; fi'
UNIT
cat > "$U/plasma-plasmashell.service.d/50-pager-thumbnails.conf" <<'UNIT'
# Pager thumbnails prototype — see ~/kde/README.md. Remove with ~/kde/rollback.sh.
[Service]
ExecStart=
ExecStart=/bin/sh -c 'if [ -x "%h/kde/session/plasmashell-launch.sh" ]; then exec "%h/kde/session/plasmashell-launch.sh" --no-respawn; else exec /usr/bin/plasmashell --no-respawn; fi'
UNIT
systemctl --user daemon-reload
echo "Installed. The patched KWin and pager take over at the next login."
