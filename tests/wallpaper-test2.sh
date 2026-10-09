#!/usr/bin/env bash
# Two-screen nested test of the per-desktop wallpaper: applies settings, checks the wallpaper,
# then renders the settings page in three states for screenshots.
cd ~/kde; N=nested-home-host; ID=com.github.sneezeparty.desktopwallpapers; T=$ID.configtest
~/kde/src/desktop-wallpapers/install.sh ~/kde/$N/data >/dev/null
img(){ ls /usr/share/wallpapers/$1/contents/images/* 2>/dev/null | sort | tail -1; }
A=$(img Altai); C=$(img Coast); D=$(img Canopee); E=$(img Cascade)
PT_LIVE_DIR="${PT_LIVE_DIR:-$HOME/kde/live}" NESTED_KWIN_ARGS="${NESTED_KWIN_ARGS:---output-count 2 --width 1280 --height 720}" ./run-nested-host.sh > nested-host.log 2>&1 &
sleep 3; until grep -q kde-nested-host- $N/env.sh 2>/dev/null && [ -S "$(sed -n 's/.*XDG_RUNTIME_DIR="\([^"]*\)".*/\1/p' $N/env.sh)/wayland-nested-host" ]; do sleep 1; done
source $N/env.sh; sleep 10
kscreen-doctor -o 2>/dev/null | grep -q 'WL-' && kscreen-doctor output.2.rotation.left output.2.position.0,0 output.1.position.720,280 >/dev/null 2>&1
sleep 3
set -- $(qdbus-qt6 --literal org.kde.KWin /VirtualDesktopManager org.kde.KWin.VirtualDesktopManager.desktops 2>/dev/null | grep -oE '[0-9a-f]{8}-[0-9a-f-]{27}')
S1="{\"default\":{\"mode\":\"image\",\"url\":\"file://$D\"},\"desktops\":{\"$1\":{\"mode\":\"image\",\"url\":\"file://$A\"},\"$2\":{\"mode\":\"folder\",\"url\":\"file:///usr/share/wallpapers/\",\"order\":\"random\",\"interval\":3600},\"$3\":{\"mode\":\"image\",\"url\":\"file://$C\"}}}"
S2="{\"default\":{\"mode\":\"folder\",\"url\":\"file:///usr/share/wallpapers/\",\"order\":\"sequential\",\"interval\":86400},\"desktops\":{\"$1\":{\"mode\":\"image\",\"url\":\"file://$E\"}}}"
apply(){ qdbus-qt6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "
desktops().forEach(function(d, i){ d.wallpaperPlugin='$1'; d.currentConfigGroup=['Wallpaper','$1','General']; d.writeConfig('Settings', i % 2 == 0 ? '$S1' : '$S2'); d.reloadConfig(); });" >/dev/null; }
apply $ID; sleep 6
for n in 1 2 4; do qdbus-qt6 org.kde.KWin /KWin org.kde.KWin.setCurrentDesktop $n >/dev/null; sleep 3; spectacle -b -n -f -o ~/kde/tests/wp2-desk$n.png >/dev/null 2>&1; done
qdbus-qt6 org.kde.KWin /KWin org.kde.KWin.setCurrentDesktop 1 >/dev/null; sleep 2
CUR=$(grep -m1 '^CurrentImages=' $N/config/plasma-org.kde.plasma.desktop-appletsrc | cut -d= -f2-)
echo "published: $(echo "$CUR" | tr ',' '\n' | wc -l) images for screen A"
# --- settings page harness
Dn=$N/data/plasma/wallpapers/$T; rm -rf $Dn; cp -r $N/data/plasma/wallpapers/$ID $Dn
sed -i "s/\"Id\": \"$ID\"/\"Id\": \"$T\"/" $Dn/metadata.json
cat > $Dn/contents/ui/main.qml <<QML
import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
WallpaperItem {
    id: w
    property var parentLayout: null
    property var steps: ["$1", "$2", "$4", ""]
    property int step: 0
    Rectangle { anchors.fill: parent; color: Kirigami.Theme.backgroundColor }
    Loader {
        id: loader
        x: 30; y: ${CONFIG_Y:-250}; width: 660
        source: "config.qml"
        onLoaded: {
            item.cfg_Settings = w.configuration.Settings;
            item.wallpaperConfiguration = ({ CurrentImages: "$CUR".split(",") });
            item.cfg_FillMode = w.configuration.FillMode;
            item.cfg_Color = w.configuration.Color;
            item.selected = w.steps[0];
            console.log("CONFIGTEST loaded");
        }
        onStatusChanged: if (status === Loader.Error) console.log("CONFIGTEST failed to load");
    }
    Timer { interval: 5000; running: true; repeat: true; onTriggered: { w.step = (w.step + 1) % w.steps.length; loader.item.selected = w.steps[w.step]; } }
}
QML
qdbus-qt6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "var d = desktops()[0]; d.wallpaperPlugin='$T'; d.currentConfigGroup=['Wallpaper','$T','General']; d.writeConfig('Settings', '$S1'); d.reloadConfig();" >/dev/null
sleep 3
for s in 1 2 3 4; do spectacle -b -n -f -o ~/kde/tests/wp2-config$s.png >/dev/null 2>&1; sleep 4.2; done
qdbus-qt6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "var d = desktops()[0]; d.wallpaperPlugin='$ID';" >/dev/null
rm -rf $Dn
# KWin and plasmashell log to the journal, not to nested-host.log
for p in $(pgrep -x plasmashell); do
  tr '\0' '\n' < /proc/$p/environ 2>/dev/null | grep -q "^XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR$" && journalctl --user _PID=$p --since "-5min" --no-pager -o cat 2>/dev/null |
    grep -i 'CONFIGTEST\|config.qml\|main.qml\|Sources.js\|desktopwallpapers\|TypeError\|ReferenceError' | sort | uniq -c | head -15 | cut -c1-260
done
grep -E '^(CurrentImages|State)=' $N/config/plasma-org.kde.plasma.desktop-appletsrc | cut -c1-330
