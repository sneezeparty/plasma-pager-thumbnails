#!/usr/bin/env bash
# Host-side driver: plays the 4K clip in the nested session and measures with thumbnails on/off.
x(){ timeout 30 distrobox enter kde-dev -- ~/kde/nested-exec.sh bash -c "$1" >/dev/null 2>&1; }
thumbs(){ x "qdbus-qt6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript 'panels().forEach(function(p){p.widgets().forEach(function(w){if(w.type==\"org.kde.plasma.pager\"){w.currentConfigGroup=[\"General\"];w.writeConfig(\"showThumbnails\",$1);w.reloadConfig();}});});'; sleep 6"; }
desk(){ x "qdbus-qt6 org.kde.KWin /KWin org.kde.KWin.setCurrentDesktop $1; sleep 4"; }
M=~/kde/tests/measure.py
thumbs true; desk 4
python3 $M "idle, thumbnails ON"; thumbs false; python3 $M "idle, thumbnails OFF"; thumbs true
x "rm -f ~/kde/tests/mpv.sock; (mpv --no-audio --loop=inf --fs --hwdec=nvdec --input-ipc-server=$HOME/kde/tests/mpv.sock ~/kde/tests/clip4k.webm &) ; sleep 8"
python3 $M "4K60 video visible, thumbnails ON"; thumbs false; python3 $M "4K60 video visible, thumbnails OFF"; thumbs true
desk 1
python3 $M "4K60 video hidden, thumbnails ON"; thumbs false; python3 $M "4K60 video hidden, thumbnails OFF"; thumbs true
desk 4
python3 $M "4K60 video visible again, ON"
echo '{"command":["quit"]}' | python3 -c "
import socket,sys,os
s=socket.socket(socket.AF_UNIX); s.connect(os.path.expanduser('~/kde/tests/mpv.sock')); s.sendall(sys.stdin.read().encode()+b'\n')"
