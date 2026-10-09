# Shared by the session launchers. Decides whether the patched build may be used.
PT_HOME="${PT_HOME:-$HOME/kde}"
PT_LIVE="$PT_HOME/live"
PT_STATE="$PT_HOME/session"
PT_RUNTIME="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
PT_ACTIVE="$PT_RUNTIME/pager-thumbnails-active"

pt_log() { echo "$(date -Is) $*" >> "$PT_STATE/session.log"; }

# The system packages the patched build was compiled against. If an update changes
# any of them, the patched build is skipped until it is rebuilt.
pt_versions() {
  {
    rpm -q kwin plasma-workspace plasma-desktop libplasma kpipewire kdecoration kscreenlocker \
      kglobalacceld kwayland plasma-activities \
      qt6-qtbase qt6-qtdeclarative qt6-qtwayland qt6-qtsvg \
      libwayland-server pipewire-libs libinput libdrm libdisplay-info libepoxy libxcvt 2>&1
    rpm -qa 'kf6-*'
  } | sort
}

# Loads the patched binaries the way the session would and makes sure every symbol
# they need is there. Catches a build that no longer fits the system before it is
# given the screen.
pt_preflight_kwin() {
  local out
  out="$(
    export PATH="$PT_LIVE/bin:$PATH" LD_LIBRARY_PATH="$PT_LIVE/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    LD_BIND_NOW=1 timeout 20 "$PT_LIVE/bin/kwin_wayland" --version 2>&1 >/dev/null || echo "kwin_wayland --version failed"
    for so in "$PT_LIVE"/lib64/plugins/kwin/plugins/*.so "$PT_LIVE"/lib64/plugins/kwin/effects/plugins/*.so; do
      [[ -e "$so" ]] && ldd -r "$so" 2>&1 | grep -E 'undefined symbol|not found' | sed "s|^|${so##*/}: |"
    done
  )"
  [[ -z "$out" ]] && return 0
  PT_REASON="patched KWin does not load: $(head -n 2 <<<"$out" | tr '\n\t' '  ')"
  return 1
}

pt_preflight_overlay() {
  local overlay="$PT_LIVE/plasma-overlay" out
  out="$(
    export LD_LIBRARY_PATH="$overlay/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    for so in "$overlay"/lib64/*.so.? "$overlay"/plugins/plasma/applets/*.so; do
      [[ -e "$so" ]] && ldd -r "$so" 2>&1 | grep -E 'undefined symbol|not found' | sed "s|^|${so##*/}: |"
    done
  )"
  [[ -z "$out" ]] && return 0
  PT_REASON="patched pager does not load: $(head -n 2 <<<"$out" | tr '\n\t' '  ')"
  return 1
}

pt_usable() {
  PT_REASON=""
  if [[ -e "$PT_HOME/DISABLE" ]]; then PT_REASON="switched off by ~/kde/DISABLE"; return 1; fi
  if [[ ! -x "$PT_LIVE/bin/kwin_wayland_wrapper" || ! -x "$PT_LIVE/bin/kwin_wayland" || ! -f "$PT_LIVE/host-versions.stamp" ]]; then
    PT_REASON="patched build not found in $PT_LIVE"; return 1; fi
  if [[ -e "$PT_STATE/FAILED" ]]; then
    PT_REASON="patched KWin failed to start earlier (delete ~/kde/session/FAILED to retry)"; return 1; fi
  if [[ "$(pt_versions)" != "$(cat "$PT_LIVE/host-versions.stamp")" ]]; then
    PT_REASON="system packages changed since the patched build was made (rebuild needed)"; return 1; fi
  return 0
}
