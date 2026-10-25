#!/usr/bin/env bash
# Builds a new copy for the real session into ~/kde/live-N, never into the one in use.
# Run on the host:
#   ~/kde/make-live.sh 5        # builds ~/kde/live-5 from ~/kde/src
# then test it and queue it for the next login (the steps are printed at the end).
set -euo pipefail
K="$HOME/kde"
n="${1:?usage: make-live.sh <N>   (builds ~/kde/live-N)}"
dest="$K/live-$n"
[[ -e "$dest" ]] && { echo "$dest already exists — pick another number."; exit 1; }
unset LD_LIBRARY_PATH QT_PLUGIN_PATH
source "$K/session/common.sh"

# The build only fits the host if the container has the very same versions of the packages
# it is built against. Anything the container has in another version is a reason to stop.
host="$(pt_versions | grep -v 'not installed')"
names="$(rpm -q --qf '%{NAME}.%{ARCH}\n' $host)"
other="$(distrobox enter kde-dev -- rpm -q $names 2>/dev/null | grep -v 'not installed' | grep -vxFf <(echo "$host") || true)"
if [[ -n "$other" ]]; then
  echo "The kde-dev container has other versions than the host of:"; echo "$other" | sed 's/^/  /'
  echo "Pin it to the host's versions first (see README.md, pin-list.txt)."; exit 1
fi

# The install prefix compiled into KWin is ~/kde/live (the symlink to the build in use).
# The patched protocols are looked up in ~/kde/sdk, which no session runs from.
box() { distrobox enter kde-dev -- env KDE_BUILD="$K/build-live" KDE_PREFIX="$K/live" KDE_DEPS="$K/sdk" "$@"; }
proto="-DPlasmaWaylandProtocols_DIR=$K/sdk/share/cmake/PlasmaWaylandProtocols"
distrobox enter kde-dev -- env KDE_BUILD="$K/build-live" KDE_PREFIX="$K/sdk" "$K/build.sh" plasma-wayland-protocols
box env KDE_TARGETS=all "$K/build.sh" kwin "$proto"
box env KDE_TARGETS=taskmanager "$K/build.sh" plasma-workspace "$proto"
box env KDE_TARGETS=org.kde.plasma.pager "$K/build.sh" plasma-desktop

box cmake --install "$K/build-live/kwin" --prefix "$dest" > /dev/null
overlay="$dest/plasma-overlay"
mkdir -p "$overlay/lib64" "$overlay/plugins/plasma/applets"
lib="$(basename "$(ls "$K"/build-live/plasma-workspace/bin/libtaskmanager.so.6.*)")"
cp "$K/build-live/plasma-workspace/bin/$lib" "$overlay/lib64/"
ln -s "$lib" "$overlay/lib64/libtaskmanager.so.6"
cp "$K/build-live/plasma-desktop/bin/plasma/applets/org.kde.plasma.pager.so" "$overlay/plugins/plasma/applets/"
distrobox enter kde-dev -- patchelf --remove-rpath "$overlay/lib64/$lib" "$overlay/plugins/plasma/applets/org.kde.plasma.pager.so"
pt_versions > "$dest/host-versions.stamp"

PT_LIVE="$dest"
pt_preflight_kwin || { echo "$PT_REASON"; exit 1; }
pt_preflight_overlay || { echo "$PT_REASON"; exit 1; }
# Keep the published patch series in step with what was built
for repo in kwin plasma-workspace plasma-desktop; do
  rm -rf "$K/patches/$repo"
  git -C "$K/src/$repo" format-patch -q --no-signature -o "$K/patches/$repo" v6.7.5..HEAD
done

cat <<EOF
== built $dest
Test it (nothing of the running session is touched):
  PT_LIVE_DIR=$dest ~/kde/tests/wrapper-test.sh
  ~/kde/tests/overview-test.sh live-$n      # then look at tests/ov-*.png; ~/kde/tests/nested-stop.sh
Use it from the next login on:
  echo live-$n > ~/kde/live-next
EOF
