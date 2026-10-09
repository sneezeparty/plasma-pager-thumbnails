#!/usr/bin/env bash
# Exercises the session launchers' fallback logic against fake KWin/plasmashell
# binaries in a throwaway copy of ~/kde. Touches nothing of the real session.
#   LAUNCHER_SRC=dir   take the scripts from there (default ~/kde/session), *.sh or *.sh.new
SRC="${LAUNCHER_SRC:-$HOME/kde/session}"; SUF="${LAUNCHER_SUFFIX:-}"
unset LD_LIBRARY_PATH QT_PLUGIN_PATH
T="$(mktemp -d)"; export PT_HOME="$T/kde" XDG_RUNTIME_DIR="$T/run" PT_GRACE=4
export PT_STOCK_KWIN="$T/stock-kwin" PT_STOCK_SHELL="$T/stock-shell"
mkdir -p "$PT_HOME/session" "$XDG_RUNTIME_DIR"
for f in common kwin-launch plasmashell-launch; do cp "$SRC/$f.sh$SUF" "$PT_HOME/session/$f.sh"; done
printf '#!/bin/sh\necho STOCK-KWIN >> "%s/out"\n' "$T" > "$PT_STOCK_KWIN"
printf '#!/bin/sh\necho "SHELL overlay=${LD_LIBRARY_PATH:-none}" >> "%s/out"\n' "$T" > "$PT_STOCK_SHELL"
chmod +x "$PT_STOCK_KWIN" "$PT_STOCK_SHELL"
source "$PT_HOME/session/common.sh"
mkbuild() { # name wrapper-body [version-exit]
  local d="$PT_HOME/$1"; mkdir -p "$d/bin" "$d/plasma-overlay/lib64" "$d/plasma-overlay/plugins/plasma/applets"
  printf '#!/bin/sh\necho "PATCHED-%s" >> "%s/out"\n%s\n' "$1" "$T" "$2" > "$d/bin/kwin_wayland_wrapper"
  printf '#!/bin/sh\nexit %s\n' "${3:-0}" > "$d/bin/kwin_wayland"
  chmod +x "$d/bin/"*; pt_versions > "$d/host-versions.stamp"
}
fail=0
check() { # description expected-out-regex [file-that-must-exist] [file-that-must-not-exist]
  local out; out="$(tr '\n' ' ' < "$T/out" 2>/dev/null)"; local ok=1
  [[ "$out" =~ $2 ]] || ok=0
  [[ -z "${3:-}" || -e "$PT_STATE/$3" ]] || ok=0
  [[ -z "${4:-}" || ! -e "$PT_STATE/$4" ]] || ok=0
  if (( ok )); then echo "ok    $1"; else echo "FAIL  $1  (out: $out; state: $(ls "$PT_STATE" | tr '\n' ' '))"; fail=1; fi
  rm -f "$T/out"
}
reset() { rm -f "$PT_STATE"/{FAILED,STARTING,SHELL_FAILED} "$XDG_RUNTIME_DIR"/pager-*; }
run() { "$PT_HOME/session/kwin-launch.sh" --xwayland; }

mkbuild b1 'exit 0'; ln -sfn b1 "$PT_HOME/live"
run; check "crash loop (wrapper gives up with status 0) falls back and is remembered" '^PATCHED-b1 STOCK-KWIN $' FAILED STARTING
run; check "next login uses the system KWin" '^STOCK-KWIN $' FAILED
reset; mkbuild b1 'exit 3'
run; check "early non-zero exit falls back and is remembered" '^PATCHED-b1 STOCK-KWIN $' FAILED STARTING

reset; mkbuild b1 'exec sleep 30'
setsid "$PT_HOME/session/kwin-launch.sh" --xwayland & p=$!; sleep 1.5; kill -TERM -- -$p; wait $p
check "quick logout (SIGTERM) is a normal end" '^PATCHED-b1 $' "" FAILED
[[ -e "$PT_STATE/STARTING" ]] && { echo "FAIL  STARTING left after normal stop"; fail=1; }
run & p=$!; sleep 1; pkill -TERM -P $p 2>/dev/null; kill -TERM $p; wait $p; rm -f "$T/out"

reset
setsid "$PT_HOME/session/kwin-launch.sh" --xwayland & p=$!; sleep 1.5; kill -KILL -- -$p; wait $p 2>/dev/null; rm -f "$T/out"
run; check "power cut during the first minutes is remembered" '^STOCK-KWIN $' FAILED STARTING

reset; mkbuild b1 'sleep 6; exit 0'
run; check "exit after the grace period is not a failure" '^PATCHED-b1 $' "" FAILED
[[ -e "$PT_STATE/STARTING" ]] && { echo "FAIL  STARTING left after long run"; fail=1; }

reset; mkbuild b1 'exit 0' 1
run; check "build that does not load is never started" '^STOCK-KWIN $' FAILED STARTING

reset; mkbuild b1 'exec sleep 1'; echo changed >> "$PT_HOME/b1/host-versions.stamp"
run; check "package change uses the system KWin" '^STOCK-KWIN $' "" FAILED

mkbuild b1 'sleep 5'; mkbuild b2 'sleep 5'; touch "$PT_STATE/FAILED"
rm -rf "$PT_HOME/b2/plasma-overlay"; echo b2 > "$PT_HOME/live-next"
run; check "incomplete live-next is ignored" '^STOCK-KWIN $' FAILED
[[ "$(readlink "$PT_HOME/live")" == b1 ]] || { echo "FAIL  live moved to incomplete build"; fail=1; }
mkbuild b2 'sleep 5'; echo b2 > "$PT_HOME/live-next"
run; check "complete live-next is switched to and gets a fresh try" '^PATCHED-b2 $' "" FAILED
[[ "$(readlink "$PT_HOME/live")" == b2 && ! -e "$PT_HOME/live-next" ]] || { echo "FAIL  live not switched"; fail=1; }

reset; touch "$PT_ACTIVE"
for i in 1 2 3 4; do "$PT_HOME/session/plasmashell-launch.sh"; done
check "plasmashell crash loop drops the patched pager" '^SHELL overlay=[^ ]*plasma-overlay[^ ]* SHELL overlay=[^ ]*plasma-overlay[^ ]* SHELL overlay=none SHELL overlay=none $' SHELL_FAILED
reset
"$PT_HOME/session/plasmashell-launch.sh"; check "without the patched KWin plasmashell is unmodified" '^SHELL overlay=none $'

grep -c . "$PT_STATE/session.log" >/dev/null; [[ "${VERBOSE:-}" ]] && cat "$PT_STATE/session.log"
cat "$PT_STATE/session.log" > /dev/null; rm -rf "$T"; (( fail )) && echo "SOME TESTS FAILED" || echo "all passed"
