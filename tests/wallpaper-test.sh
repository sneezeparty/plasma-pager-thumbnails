#!/usr/bin/env bash
# Two-screen nested test of the per-desktop wallpaper plugin (live KWin + system plasmashell).
cd ~/kde; N=nested-home-host; ID=com.github.sneezeparty.desktopwallpapers
img(){ ls /usr/share/wallpapers/$1/contents/images/* 2>/dev/null | sort | tail -1; }
A=$(img Altai); B=$(img Autumn); C=$(img Coast); D=$(img Canopee); E=$(img Cascade); F=$(img EveningGlow)
NESTED_KWIN_ARGS="--output-count 2 --width 1280 --height 720" ./run-nested-host.sh > nested-host.log 2>&1 &
sleep 3; until grep -q kde-nested-host- $N/env.sh 2>/dev/null && [ -S "$(sed -n 's/.*XDG_RUNTIME_DIR="\([^"]*\)".*/\1/p' $N/env.sh)/wayland-nested-host" ]; do sleep 1; done
source $N/env.sh; sleep 10
kscreen-doctor -o 2>/dev/null | grep -q 'WL-' && kscreen-doctor output.2.rotation.left output.2.position.0,0 output.1.position.720,280 >/dev/null 2>&1
sleep 3
ids=$(qdbus-qt6 --literal org.kde.KWin /VirtualDesktopManager org.kde.KWin.VirtualDesktopManager.desktops 2>/dev/null | grep -oE '[0-9a-f]{8}-[0-9a-f-]{27}' | tr '\n' ' ')
set -- $ids; echo "desktop ids: $# found"
qdbus-qt6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "
var out=[];
desktops().forEach(function(d, i){
  d.wallpaperPlugin='$ID'; d.currentConfigGroup=['Wallpaper','$ID','General'];
  if (i % 2 == 0) { d.writeConfig('DesktopSources', ['$1=file://$A','$2=file://$B','$3=file://$C']); d.writeConfig('DefaultSource','file://$D'); }
  else            { d.writeConfig('DesktopSources', ['$1=file://$E','$2=file:///usr/share/wallpapers/']); d.writeConfig('DefaultSource','file://$F'); }
  d.reloadConfig(); out.push('screen '+d.screen+' containment '+d.id);
});
print(out.join('; '));"
sleep 5
for n in 1 2 3 4; do
  qdbus-qt6 org.kde.KWin /KWin org.kde.KWin.setCurrentDesktop $n >/dev/null; sleep 3
  spectacle -b -n -f -o ~/kde/tests/wp-desk$n.png >/dev/null 2>&1
done
qdbus-qt6 org.kde.KWin /KWin org.kde.KWin.setCurrentDesktop 1 >/dev/null
grep -n 'CurrentImages' $N/config/plasma-org.kde.plasma.desktop-appletsrc | cut -c1-400
grep -i 'desktopwallpapers\|TypeError\|ReferenceError\|is not a type\|Cannot assign\|not installed' nested-host.log | sort -u | head -12 | cut -c1-260
