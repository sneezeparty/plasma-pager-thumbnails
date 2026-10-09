#!/usr/bin/env bash
# Host-side driver: GPU benchmark inside the nested session, thumbnails on/off, visible and hidden.
x(){ timeout ${T:-40} distrobox enter kde-dev -- ~/kde/nested-exec.sh bash -c "$1" 2>&1; }
thumbs(){ x "qdbus-qt6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript 'panels().forEach(function(p){p.widgets().forEach(function(w){if(w.type==\"org.kde.plasma.pager\"){w.currentConfigGroup=[\"General\"];w.writeConfig(\"showThumbnails\",$1);w.reloadConfig();}});});'; sleep 6" >/dev/null; }
desk(){ x "qdbus-qt6 org.kde.KWin /KWin org.kde.KWin.setCurrentDesktop $1; sleep 3" >/dev/null; }
M=~/kde/tests/measure.py
bench(){ # $1 label, $2 command  -> prints FPS of a 12s visible fullscreen run
  for i in 1 2; do printf "%-44s %s\n" "$1 (run $i)" "$(T=60 x "$2 --fullscreen -b terrain:duration=12 2>&1 | grep -oE 'FPS: [0-9]+ FrameTime: [0-9.]+ ms'")"; done; }
hidden(){ # $1 label, $2 command, $3 pgrep pattern
  desk 2; x "($2 --fullscreen -b terrain:duration=300 >/dev/null 2>&1 &); sleep 6" >/dev/null; desk 1
  APP_PAT="$3" python3 $M "$1 hidden, thumbnails ON" 14; thumbs false
  APP_PAT="$3" python3 $M "$1 hidden, thumbnails OFF" 14; thumbs true
  pkill -f "$3"; sleep 2; }
desk 1; thumbs true
bench "Wayland game visible, thumbnails ON" glmark2-wayland
thumbs false
bench "Wayland game visible, thumbnails OFF" glmark2-wayland
thumbs true
hidden "Wayland game" glmark2-wayland '^glmark2-waylan[d]'
