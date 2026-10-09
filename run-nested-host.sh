#!/usr/bin/env bash
# Dress rehearsal ON THE HOST (not in the container): the live KWin from ~/kde/live plus the
# system plasmashell with the overlay, as a window, with its own config and D-Bus session.
set -euo pipefail
K="$HOME/kde"; N="$K/nested-home-host"; L="${PT_LIVE_DIR:-$K/live}"
HOST_RUNTIME="$XDG_RUNTIME_DIR"
export XDG_CONFIG_HOME="$N/config" XDG_CACHE_HOME="$N/cache" XDG_DATA_HOME="$N/data" XDG_STATE_HOME="$N/state"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"
# A fresh directory per run: a previous run can leave a portal mount behind that can't be removed.
export XDG_RUNTIME_DIR="$HOST_RUNTIME/kde-nested-host-$$"
mkdir -m 700 "$XDG_RUNTIME_DIR"
for s in "${WAYLAND_DISPLAY:-wayland-0}" pipewire-0 pipewire-0-manager; do
  [[ -e "$HOST_RUNTIME/$s" ]] && ln -s "$HOST_RUNTIME/$s" "$XDG_RUNTIME_DIR/$s"
done
[[ -f "$XDG_CONFIG_HOME/kwinrc" ]] || printf '[Desktops]\nNumber=4\nRows=1\n' > "$XDG_CONFIG_HOME/kwinrc"
# PT_OVERLAY=<dir> lends plasmashell another overlay than the live one (for experiments).
OV="${PT_OVERLAY:-$L/plasma-overlay}"
cat > "$N/shell.sh" <<SH
#!/usr/bin/env bash
# plasmashell gets only the overlay, exactly like the real session.
export LD_LIBRARY_PATH="$OV/lib64" QT_PLUGIN_PATH="$OV/plugins"
unset QML_IMPORT_PATH
export XDG_DATA_DIRS="\${PT_ORIG_XDG_DATA_DIRS}"
exec /usr/bin/plasmashell
SH
chmod +x "$N/shell.sh"
# PT_KWIN_BUILD=<build tree>/bin runs an uninstalled KWin (for experiments) instead of the live one.
if [[ -n "${PT_KWIN_BUILD:-}" ]]; then KB_BIN="$PT_KWIN_BUILD"; KB_LIB="$PT_KWIN_BUILD"; KB_PLUGINS="$PT_KWIN_BUILD"
else KB_BIN="$L/bin"; KB_LIB="$L/lib64"; KB_PLUGINS="$L/lib64/plugins"; fi
export PT_ORIG_XDG_DATA_DIRS="${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
unset DISPLAY
exec dbus-run-session -- bash -c '
  echo "export DBUS_SESSION_BUS_ADDRESS=\"$DBUS_SESSION_BUS_ADDRESS\" XDG_RUNTIME_DIR=\"$XDG_RUNTIME_DIR\" XDG_CONFIG_HOME=\"$XDG_CONFIG_HOME\" XDG_CACHE_HOME=\"$XDG_CACHE_HOME\" XDG_DATA_HOME=\"$XDG_DATA_HOME\" XDG_STATE_HOME=\"$XDG_STATE_HOME\" WAYLAND_DISPLAY=wayland-nested-host; unset DISPLAY" > "'"$N"'/env.sh"
  export LD_LIBRARY_PATH="'"$KB_LIB"'" QT_PLUGIN_PATH="'"$KB_PLUGINS"'" QML_IMPORT_PATH="'"$L"'/lib64/qml" XDG_DATA_DIRS="'"$L"'/share:$PT_ORIG_XDG_DATA_DIRS"
  exec "'"$KB_BIN"'/kwin_wayland" ${NESTED_KWIN_ARGS:---width 1600 --height 900} --xwayland --socket wayland-nested-host --exit-with-session "'"$N"'/shell.sh"
'
