#!/usr/bin/env bash
# Starts the patched KWin + Plasma as a window inside the normal session.
#   distrobox enter kde-dev -- ~/kde/run-nested.sh            (patched build in ~/kde/usr)
#   distrobox enter kde-dev -- ~/kde/run-nested.sh --stock    (the container's unpatched packages)
# NESTED_KWIN_ARGS overrides the output setup, e.g. "--output-count 2 --width 1280 --height 720".
# Uses its own config/cache/data/runtime dirs and its own D-Bus session, so it can't
# touch the real Plasma settings in ~/.config. Closing the window ends it.
set -euo pipefail
K="$HOME/kde"
N="$K/nested-home"
HOST_RUNTIME="$XDG_RUNTIME_DIR"

if [[ "${1:-}" != "--stock" ]]; then
  set +u
  source "$K/build/kwin/prefix.sh"
  set -u
  export LD_LIBRARY_PATH="$K/usr/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi

export XDG_CONFIG_HOME="$N/config" XDG_CACHE_HOME="$N/cache" XDG_DATA_HOME="$N/data" XDG_STATE_HOME="$N/state"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"

# Private runtime dir that only lends the host's Wayland and PipeWire sockets.
export XDG_RUNTIME_DIR="$HOST_RUNTIME/kde-nested"
rm -rf "$XDG_RUNTIME_DIR"; mkdir -m 700 "$XDG_RUNTIME_DIR"
for s in "${WAYLAND_DISPLAY:-wayland-0}" pipewire-0 pipewire-0-manager; do
  [[ -e "$HOST_RUNTIME/$s" ]] && ln -s "$HOST_RUNTIME/$s" "$XDG_RUNTIME_DIR/$s"
done

if [[ ! -f "$XDG_CONFIG_HOME/kwinrc" ]]; then
  printf '[Desktops]\nNumber=4\nRows=1\n' > "$XDG_CONFIG_HOME/kwinrc"
fi

# Lets the test tools bind KWin's restricted protocols; only affects the nested KWin.
export KWIN_WAYLAND_NO_PERMISSION_CHECKS=1
export QT_LOGGING_RULES="kwin_screencast.debug=true"

exec dbus-run-session -- bash -c '
  env | grep -E "^(DBUS_SESSION_BUS_ADDRESS|XDG_|PATH|LD_LIBRARY_PATH|QT_PLUGIN_PATH|QML2_IMPORT_PATH|QML_IMPORT_PATH|QT_QUICK_CONTROLS_STYLE_PATH|KWIN_|NESTED_)" | sed "s/^/export /; s/=/=\"/; s/\$/\"/" > "'"$N"'/env.sh"
  echo "export WAYLAND_DISPLAY=wayland-nested" >> "'"$N"'/env.sh"
  exec kwin_wayland ${NESTED_KWIN_ARGS:---width 1920 --height 1080} --xwayland --socket wayland-nested --exit-with-session plasmashell
'
