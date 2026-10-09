#!/usr/bin/env bash
# Starts the patched KWin through its wrapper with the same environment kwin-launch.sh sets,
# nested, and reports which binary the wrapper actually ran.
PT_LIVE="${PT_LIVE_DIR:-$HOME/kde/live}"; HOST_RUNTIME="$XDG_RUNTIME_DIR"
export XDG_RUNTIME_DIR="$HOST_RUNTIME/kde-wrapper-test-$$"; mkdir -m 700 "$XDG_RUNTIME_DIR"
ln -s "$HOST_RUNTIME/${WAYLAND_DISPLAY:-wayland-0}" "$XDG_RUNTIME_DIR/wayland-host"; ln -s "$HOST_RUNTIME/pipewire-0" "$XDG_RUNTIME_DIR/"
export WAYLAND_DISPLAY=wayland-host
export XDG_CONFIG_HOME="$HOME/kde/nested-home-host/config" XDG_CACHE_HOME="$HOME/kde/nested-home-host/cache"
unset DISPLAY
(
  export PATH="$PT_LIVE/bin:$PATH"
  export LD_LIBRARY_PATH="$PT_LIVE/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  export QT_PLUGIN_PATH="$PT_LIVE/lib64/plugins${QT_PLUGIN_PATH:+:$QT_PLUGIN_PATH}"
  export QML_IMPORT_PATH="$PT_LIVE/lib64/qml${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}"
  export XDG_DATA_DIRS="$PT_LIVE/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
  exec dbus-run-session -- "$PT_LIVE/bin/kwin_wayland_wrapper" --xwayland
) > "$HOME/kde/tests/wrapper-test.log" 2>&1 &
W=$!
sleep 12
for p in $(pgrep -x kwin_wayland); do
  if tr '\0' '\n' < /proc/$p/environ 2>/dev/null | grep -q "XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"; then
    echo "wrapper started: $(readlink /proc/$p/exe)"
    grep -o "/[^ ]*\(plugins/kwin/plugins/screencast\.so\|libkwin\.so[^ ]*\)" /proc/$p/maps | sort -u
    ls "$XDG_RUNTIME_DIR" | tr "\n" " "; echo; grep -c screencast /proc/$p/maps; sock=$(ls "$XDG_RUNTIME_DIR" | grep -E "^wayland-[0-9]+$" | grep -v "^wayland-host$" | head -1)
    echo "socket: $sock"; WAYLAND_DISPLAY=$sock wayland-info 2>/dev/null | grep zkde_screencast
    kill $p
  fi
done
sleep 2; pkill -P $W 2>/dev/null; kill $W 2>/dev/null
grep -i 'screencast\|undefined' "$HOME/kde/tests/wrapper-test.log" | head -3 | cut -c1-200
