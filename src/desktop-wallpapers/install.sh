#!/usr/bin/env bash
# Installs the wallpaper type for this user. No root, nothing outside ~/.local.
# Pass a data directory to install somewhere else (used by the nested test session).
set -euo pipefail
src="$(cd "$(dirname "$0")" && pwd)/package"
dest="${1:-${XDG_DATA_HOME:-$HOME/.local/share}}/plasma/wallpapers/com.github.sneezeparty.desktopwallpapers"
rm -rf "$dest"; mkdir -p "$(dirname "$dest")"; cp -r "$src" "$dest"
echo "Installed to $dest"
