#!/usr/bin/env bash
# Two-screen rehearsal of an installed build: pager tiles and KWin's overview / grid with
# per-desktop wallpapers. Reuses the settings left in the nested config.
cd ~/kde; N=nested-home-host
PT_LIVE_DIR=$HOME/kde/${1:-live-3} NESTED_KWIN_ARGS="--output-count 2 --width 1280 --height 720" ./run-nested-host.sh > nested-host.log 2>&1 &
sleep 3; until grep -q kde-nested-host- $N/env.sh 2>/dev/null && [ -S "$(sed -n 's/.*XDG_RUNTIME_DIR="\([^"]*\)".*/\1/p' $N/env.sh)/wayland-nested-host" ]; do sleep 1; done
source $N/env.sh; sleep 10
kscreen-doctor -o 2>/dev/null | grep -q 'WL-' && kscreen-doctor output.2.rotation.left output.2.position.0,0 output.1.position.720,280 >/dev/null 2>&1
sleep 3; (kcalc >/dev/null 2>&1 &); sleep 3
qdbus-qt6 org.kde.KWin /KWin org.kde.KWin.setCurrentDesktop 2 >/dev/null; sleep 4
spectacle -b -n -f -o ~/kde/tests/ov-desktop.png >/dev/null 2>&1
qdbus-qt6 org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.shortcutNames 2>/dev/null | grep -i -E 'overview|grid' | tr '\n' ' '; echo
qdbus-qt6 org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.invokeShortcut "Grid View" >/dev/null 2>&1; sleep 4
spectacle -b -n -f -o ~/kde/tests/ov-grid.png >/dev/null 2>&1
qdbus-qt6 org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.invokeShortcut "Grid View" >/dev/null 2>&1; sleep 2
qdbus-qt6 org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.invokeShortcut "Overview" >/dev/null 2>&1; sleep 4
spectacle -b -n -f -o ~/kde/tests/ov-overview.png >/dev/null 2>&1
qdbus-qt6 org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.invokeShortcut "Overview" >/dev/null 2>&1
grep -c 'CurrentImages' $N/config/plasma-org.kde.plasma.desktop-appletsrc
grep -i 'wallpaper item\|error creating screencast\|TypeError\|ReferenceError\|undefined symbol' nested-host.log | sort -u | head -5 | cut -c1-200
