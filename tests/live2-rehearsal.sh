#!/usr/bin/env bash
# Final rehearsal of an installed build directory (default live-2) on the host, two screens,
# reusing the settings left in the nested config by pager-wallpaper-test.sh.
cd ~/kde; N=nested-home-host
PT_LIVE_DIR=$HOME/kde/${1:-live-2} NESTED_KWIN_ARGS="--output-count 2 --width 1280 --height 720" ./run-nested-host.sh > nested-host.log 2>&1 &
sleep 3; until grep -q kde-nested-host- $N/env.sh 2>/dev/null && [ -S "$(sed -n 's/.*XDG_RUNTIME_DIR="\([^"]*\)".*/\1/p' $N/env.sh)/wayland-nested-host" ]; do sleep 1; done
source $N/env.sh; sleep 10
kscreen-doctor -o 2>/dev/null | grep -q 'WL-' && kscreen-doctor output.2.rotation.left output.2.position.0,0 output.1.position.720,280 >/dev/null 2>&1
sleep 3; (kcalc >/dev/null 2>&1 &); sleep 3
qdbus-qt6 org.kde.KWin /KWin org.kde.KWin.setCurrentDesktop 2 >/dev/null; sleep 4
spectacle -b -n -f -o ~/kde/tests/live2.png >/dev/null 2>&1
for p in $(pgrep -x kwin_wayland; pgrep -x plasmashell); do tr '\0' '\n' < /proc/$p/environ 2>/dev/null | grep -q "XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR" && { echo "$(readlink /proc/$p/exe)"; grep -o '/[^ ]*\(libkwin\.so\.6\.7\.4\|libtaskmanager\.so\.6\.7\.4\|plasma\.pager\.so\)' /proc/$p/maps | sort -u | sed 's/^/    /'; }; done
grep -i 'error creating screencast\|TypeError\|ReferenceError\|undefined symbol' nested-host.log | sort -u | head -5 | cut -c1-200
