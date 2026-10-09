#!/usr/bin/env bash
# Checks that desktop streams pause while a fullscreen window is focused (host rehearsal).
cd ~/kde; source nested-home-host/env.sh
nested(){ for p in $(pgrep -x "$1"); do tr '\0' '\n' < /proc/$p/environ 2>/dev/null | grep -q 'XDG_RUNTIME_DIR=.*kde-nested-host' && echo $p; done | tail -1; }
K=$(nested kwin_wayland); S=$(nested plasmashell)
m(){ top -b -n 5 -d 2 -p $K,$S | awk -v k=$K -v s=$S -v l="$1" '$1==k{a[++n]=$9} $1==s{b[++m]=$9} END{for(i=2;i<=n;i++){x+=a[i];y+=b[i]} printf "%s: kwin %.1f%%  plasmashell %.1f%%\n",l,x/(n-1),y/(m-1)}'; }
(konsole --fullscreen -e bash -c 'while :; do date +%T.%N; head -c 3000 /dev/urandom | base64; sleep 0.05; done' >/dev/null 2>&1 &)
sleep 6; T=$(nested konsole)
m "busy FULLSCREEN terminal focused"
echo 'workspace.windowList().forEach(w => { if (w.fullScreen) { w.fullScreen = false; } });' > tests/unfs.js
id=$(qdbus-qt6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript ~/kde/tests/unfs.js unfs$RANDOM); qdbus-qt6 org.kde.KWin /Scripting/Script$id org.kde.kwin.Script.run; sleep 4
m "same terminal, not fullscreen   "
[ -n "$T" ] && kill $T
