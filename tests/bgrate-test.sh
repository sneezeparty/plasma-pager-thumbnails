#!/usr/bin/env bash
# Measures the cost of asking windows on hidden desktops to draw more often.
# Runs an uninstalled KWin build nested on the host; the live session is not involved.
cd ~/kde
N=nested-home-host
nested(){ for p in $(pgrep -x "$1"); do tr '\0' '\n' < /proc/$p/environ 2>/dev/null | grep -q 'XDG_RUNTIME_DIR=.*kde-nested-host' && echo $p; done | tail -1; }
thumbs(){ qdbus-qt6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "panels().forEach(function(p){p.widgets().forEach(function(w){if(w.type==\"org.kde.plasma.pager\"){w.currentConfigGroup=[\"General\"];w.writeConfig(\"showThumbnails\",$1);w.reloadConfig();}});});" >/dev/null; sleep 5; }
desk(){ qdbus-qt6 org.kde.KWin /KWin org.kde.KWin.setCurrentDesktop $1 >/dev/null; sleep 3; }
measure(){ # label, app pid
  local K=$(nested kwin_wayland) S=$(nested plasmashell) A=$2
  nvidia-smi pmon -c 10 -s u > /tmp/bg-pmon.$$ 2>/dev/null & local PM=$!
  nvidia-smi --query-gpu=power.draw --format=csv,noheader,nounits -l 1 > /tmp/bg-pow.$$ 2>/dev/null & local SM=$!
  top -b -n 6 -d 2 -p $K,$S${A:+,$A} > /tmp/bg-top.$$
  wait $PM 2>/dev/null; kill $SM 2>/dev/null
  awk -v k=$K -v s=$S -v a=${A:-0} -v l="$1" '
    FNR==NR { if ($1==k) x[++nk]=$9; if ($1==s) y[++ns]=$9; if ($1==a) z[++na]=$9; next }
    FILENAME ~ /pmon/ { if ($2==a) { g+=($4=="-"?0:$4); ng++ } next }
    { p+=$1; np++ }
    END { for(i=2;i<=nk;i++) kx+=x[i]; for(i=2;i<=ns;i++) sy+=y[i]; for(i=2;i<=na;i++) az+=z[i];
          printf "%-34s kwin %4.1f%%  shell %4.1f%%  app CPU %5.1f%%  app GPU %4.1f%%  card %3.0f W\n", l, kx/(nk-1), sy/(ns-1), (na>1?az/(na-1):0), (ng?g/ng:0), (np?p/np:0) }' /tmp/bg-top.$$ /tmp/bg-pmon.$$ /tmp/bg-pow.$$
  rm -f /tmp/bg-*.$$
}
run_case(){ # interval label
  export KWIN_THROTTLED_OFFSCREEN_INTERVAL=$1
  PT_KWIN_BUILD=$HOME/kde/build-live/kwin/bin ./run-nested-host.sh > nested-host.log 2>&1 &
  sleep 3; until grep -q kde-nested-host- $N/env.sh 2>/dev/null && [ -S "$(sed -n 's/.*XDG_RUNTIME_DIR="\([^"]*\)".*/\1/p' $N/env.sh)/wayland-nested-host" ]; do sleep 1; done
  ( source $N/env.sh; sleep 9
    [ "$2" = off ] && thumbs false || thumbs true
    for w in ${WORKLOADS:-video cube terminal}; do
      desk 2
      case $w in
        video)    NR="$XDG_RUNTIME_DIR"; env -u XDG_DATA_HOME -u XDG_CONFIG_HOME -u XDG_CACHE_HOME -u XDG_STATE_HOME -u DBUS_SESSION_BUS_ADDRESS XDG_RUNTIME_DIR=/run/user/$(id -u) distrobox enter kde-dev -- env XDG_RUNTIME_DIR="$NR" WAYLAND_DISPLAY=$WAYLAND_DISPLAY mpv --no-audio --loop=inf --hwdec=nvdec --geometry=1280x720 ~/kde/tests/clip4k.webm >~/kde/tests/mpv-bg.log 2>&1 & sleep 9; A=$(pgrep -n -x mpv); [ -z "$A" ] && { echo "mpv did not start:"; tail -3 ~/kde/tests/mpv-bg.log; };;
        cube)     vkcube --wsi wayland >/dev/null 2>&1 & sleep 4; A=$(pgrep -n -x vkcube);;
        terminal) konsole -e bash -c 'while :; do date +%T.%N; head -c 3000 /dev/urandom | base64; sleep 0.05; done' >/dev/null 2>&1 & sleep 4; A=$(nested konsole);;
      esac
      desk 1
      measure "$3, hidden $w" $A
      kill $A 2>/dev/null; sleep 2
    done )
  kill $(nested kwin_wayland) 2>/dev/null; sleep 4
  for p in $(pgrep -u $UID); do tr '\0' '\n' < /proc/$p/environ 2>/dev/null | grep -q 'XDG_RUNTIME_DIR=.*/kde-nested-host' && kill $p; done 2>/dev/null
  sleep 2
}
for c in ${CASES:-off 1000 200 66}; do
  case $c in
    off)  run_case 1000 off "thumbnails off";;
    1000) run_case 1000 on  "1 per second ";;
    200)  run_case 200  on  "5 per second ";;
    66)   run_case 66   on  "15 per second";;
  esac
done
