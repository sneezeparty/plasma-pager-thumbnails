#!/usr/bin/env bash
# Two-screen nested test: per-desktop wallpapers in the pager tiles, live and classic,
# using the uninstalled KWin build and a test overlay.
cd ~/kde; N=nested-home-host; ID=com.github.sneezeparty.desktopwallpapers
~/kde/src/desktop-wallpapers/install.sh ~/kde/$N/data >/dev/null
img(){ ls /usr/share/wallpapers/$1/contents/images/* 2>/dev/null | sort | tail -1; }
A=$(img Altai); C=$(img Coast); D=$(img Canopee); E=$(img Cascade); F=$(img Autumn)
PT_KWIN_BUILD=$HOME/kde/build-live/kwin/bin PT_OVERLAY=$HOME/kde/test-overlay NESTED_KWIN_ARGS="--output-count 2 --width 1280 --height 720" ./run-nested-host.sh > nested-host.log 2>&1 &
sleep 3; until grep -q kde-nested-host- $N/env.sh 2>/dev/null && [ -S "$(sed -n 's/.*XDG_RUNTIME_DIR="\([^"]*\)".*/\1/p' $N/env.sh)/wayland-nested-host" ]; do sleep 1; done
source $N/env.sh; sleep 10
kscreen-doctor -o 2>/dev/null | grep -q 'WL-' && kscreen-doctor output.2.rotation.left output.2.position.0,0 output.1.position.720,280 >/dev/null 2>&1
sleep 3
set -- $(qdbus-qt6 --literal org.kde.KWin /VirtualDesktopManager org.kde.KWin.VirtualDesktopManager.desktops 2>/dev/null | grep -oE '[0-9a-f]{8}-[0-9a-f-]{27}')
S1="{\"default\":{\"mode\":\"image\",\"url\":\"file://$D\"},\"desktops\":{\"$1\":{\"mode\":\"image\",\"url\":\"file://$A\"},\"$2\":{\"mode\":\"folder\",\"url\":\"file:///usr/share/wallpapers/\",\"order\":\"random\",\"interval\":3600},\"$3\":{\"mode\":\"image\",\"url\":\"file://$C\"}}}"
S2="{\"default\":{\"mode\":\"image\",\"url\":\"file://$F\"},\"desktops\":{\"$1\":{\"mode\":\"image\",\"url\":\"file://$E\"},\"$3\":{\"mode\":\"folder\",\"url\":\"file:///usr/share/wallpapers/\",\"order\":\"sequential\",\"interval\":86400}}}"
js(){ qdbus-qt6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$1"; }
js "desktops().forEach(function(d, i){ d.wallpaperPlugin='$ID'; d.currentConfigGroup=['Wallpaper','$ID','General']; d.writeConfig('Settings', i % 2 == 0 ? '$S1' : '$S2'); d.reloadConfig(); });" >/dev/null
pager(){ js "panels().forEach(function(p){p.widgets().forEach(function(w){if(w.type=='org.kde.plasma.pager'){w.currentConfigGroup=['General'];$1 w.reloadConfig();}});});" >/dev/null; sleep 5; }
(konsole >/dev/null 2>&1 &); sleep 3
qdbus-qt6 org.kde.KWin /KWin org.kde.KWin.setCurrentDesktop 2 >/dev/null; (kcalc >/dev/null 2>&1 &); sleep 3
qdbus-qt6 org.kde.KWin /KWin org.kde.KWin.setCurrentDesktop 3 >/dev/null; sleep 2
shot(){ spectacle -b -n -f -o ~/kde/tests/pw-$1.png >/dev/null 2>&1; }
pager "w.writeConfig('showThumbnails',true); w.writeConfig('showWallpaper',true); w.writeConfig('showOutlinesOverThumbnails',false);"; shot live
pw-dump 2>/dev/null | python3 -c "
import json,sys
f=set()
for o in json.load(sys.stdin):
    i=o.get('info') or {}
    if o.get('type','').endswith('Node') and (i.get('props') or {}).get('node.name')=='kwin_wayland':
        for x in i.get('params',{}).get('Format',[]): f.add(x.get('format'))
print('stream formats:', f)"
pager "w.writeConfig('showOutlinesOverThumbnails',true);"; shot live-outlines
pager "w.writeConfig('showThumbnails',false); w.writeConfig('showWindowOutlines',true);"; shot classic-wallpaper
pager "w.writeConfig('showWallpaper',false);"; shot classic
pager "w.writeConfig('showThumbnails',true);"; shot live-nowallpaper
pager "w.writeConfig('showWallpaper',true); w.writeConfig('showOutlinesOverThumbnails',false);"
grep -i 'pager.*qml\|main.qml.*rror\|TypeError\|ReferenceError\|DesktopWallpapers\|error creating screencast\|Cannot assign' nested-host.log | sort -u | head -10 | cut -c1-260
