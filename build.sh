#!/usr/bin/env bash
# Build + install one repo from ~/kde/src into ~/kde/usr. Run via:
#   distrobox enter kde-dev -- ~/kde/build.sh <repo> [extra cmake args]
set -euo pipefail
repo="$1"; shift
K="$HOME/kde"
# KDE_PREFIX / KDE_BUILD select another install prefix and build tree (the live copy uses
# ~/kde/live and ~/kde/build-live). KDE_TARGETS builds only those targets and skips the install.
P="${KDE_PREFIX:-$K/usr}"
# KDE_DEPS is where the patched protocols are looked for, if not in the install prefix (the live
# prefix is a symlink to whichever build is in use, and only the first one has them: use ~/kde/sdk).
D="${KDE_DEPS:-$P}"
B="${KDE_BUILD:-$K/build}"
export CCACHE_DIR="$K/ccache"
cmake -S "$K/src/$repo" -B "$B/$repo" -G Ninja \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DCMAKE_INSTALL_PREFIX="$P" \
  -DCMAKE_PREFIX_PATH="$D" \
  -DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
  -DCMAKE_EXE_LINKER_FLAGS=-fuse-ld=mold -DCMAKE_SHARED_LINKER_FLAGS=-fuse-ld=mold -DCMAKE_MODULE_LINKER_FLAGS=-fuse-ld=mold \
  -DBUILD_TESTING=OFF -DBUILD_QCH=OFF -DKDE_INSTALL_USE_QT_SYS_PATHS=OFF "$@"
if [[ -n "${KDE_TARGETS:-}" ]]; then
  cmake --build "$B/$repo" --target $KDE_TARGETS
  echo "== $repo: built $KDE_TARGETS (not installed)"
  exit 0
fi
cmake --build "$B/$repo"
# KAuth/D-Bus/polkit helpers ask for absolute system paths; keep them inside the prefix.
grep -rlE --include=cmake_install.cmake '["}]/usr/(libexec|share)/' "$B/$repo" \
  | xargs -r sed -i -E "s#([\"}])/usr/(libexec|share)/#\\1$P/\\2/#g" || true
cmake --install "$B/$repo" >/dev/null
echo "== $repo installed to $P"
