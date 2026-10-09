#!/usr/bin/env bash
# Renders the pager's settings page inside the running nested session via a throwaway wallpaper.
cd ~/kde; N=nested-home-host; ID=com.github.sneezeparty.desktopwallpapers; T=$ID.configtest
source $N/env.sh
D=$N/data/plasma/wallpapers/$T; rm -rf $D; cp -r $N/data/plasma/wallpapers/$ID $D
sed -i "s/\"Id\": \"$ID\"/\"Id\": \"$T\"/" $D/metadata.json
cat > $D/contents/ui/main.qml <<'QML'
import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
WallpaperItem {
    id: w
    property bool live: false
    Rectangle { anchors.fill: parent; color: Kirigami.Theme.backgroundColor }
    Loader {
        id: loader
        x: 30; y: 20; width: 660; height: 700
        source: "qrc:/qt/qml/plasma/applet/org/kde/plasma/pager/configGeneral.qml"
        onLoaded: { item.cfg_showThumbnails = false; item.cfg_showWallpaper = true; item.cfg_showWindowOutlines = true; console.log("PAGERCONFIG loaded"); }
        onStatusChanged: if (status === Loader.Error) console.log("PAGERCONFIG failed to load");
    }
    Timer { interval: 6000; running: true; onTriggered: loader.item.cfg_showThumbnails = true }
}
QML
qdbus-qt6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "var d = desktops()[0]; d.wallpaperPlugin='$T';" >/dev/null
sleep 3; spectacle -b -n -f -o ~/kde/tests/pagercfg-outlines.png >/dev/null 2>&1
sleep 5; spectacle -b -n -f -o ~/kde/tests/pagercfg-live.png >/dev/null 2>&1
qdbus-qt6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "var d = desktops()[0]; d.wallpaperPlugin='$ID';" >/dev/null
rm -rf $D
grep -i 'PAGERCONFIG\|configGeneral' nested-host.log | grep -v 'Default$' | sort -u | head -8 | cut -c1-240
