#!/usr/bin/env bash
# Puts the session back on the stock KWin and pager. Works from a text console too
# (Ctrl+Alt+F3, log in, run this, then reboot or log in again).
#   ~/kde/rollback.sh                    remove the overrides
#   ~/kde/rollback.sh --restore-config   also put back the Plasma/KWin config saved before going live
set -uo pipefail
U="$HOME/.config/systemd/user"
rm -f "$U/plasma-kwin_wayland.service.d/50-pager-thumbnails.conf" "$U/plasma-plasmashell.service.d/50-pager-thumbnails.conf"
rmdir "$U/plasma-kwin_wayland.service.d" "$U/plasma-plasmashell.service.d" 2>/dev/null
rm -f "$HOME/kde/session/ENABLE_ON_NEXT_START"
systemctl --user daemon-reload 2>/dev/null
echo "Overrides removed."

if [[ "${1:-}" == "--restore-config" ]]; then
  B="$(ls -d "$HOME"/kde/config-backup-*-prelive 2>/dev/null | tail -1)"
  if [[ -z "$B" ]]; then echo "No pre-live config backup found."; exit 1; fi
  running=0; systemctl --user is-active -q plasma-plasmashell.service && running=1
  (( running )) && systemctl --user stop plasma-plasmashell.service
  cp -a "$B"/. "$HOME/.config/"
  (( running )) && systemctl --user start plasma-plasmashell.service
  echo "Config restored from $B."
fi
echo "Log out and back in (or reboot) to return to the stock KWin and pager."
