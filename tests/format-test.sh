#!/usr/bin/env bash
# kpipewire advertises only as many pixel formats as fit in a fixed buffer, in the random
# order of a QHash, so a consumer may lack any given format. Starts the nested session with
# different hash seeds until the panel's consumer lacks BGRA, then reports whether the
# desktop streams still negotiate.   usage: format-test.sh live-N
cd ~/kde; unset LD_LIBRARY_PATH QT_PLUGIN_PATH
report() { pw-dump 2>/dev/null | python3 -c "
import json,sys
pid=sys.argv[1]; objs=json.load(sys.stdin)
cl={o['id'] for o in objs if o.get('type','').endswith('Client') and str((o.get('info',{}).get('props') or {}).get('pipewire.sec.pid')) in pid.split(',')}
prod=[];cons=set()
for o in objs:
    i=o.get('info') or {}; pr=i.get('props') or {}
    if not o.get('type','').endswith('Node') or pr.get('client.id') not in cl: continue
    if pr.get('node.name')=='kwin_wayland':
        f=[(x.get('format'),'dmabuf' if 'modifier' in x else 'shm') for x in i.get('params',{}).get('Format',[])]
        prod.append((i.get('state'), f[0] if f else None))
    else:
        cons|={x.get('format') for x in i.get('params',{}).get('EnumFormat',[])}
print('consumer accepts:', sorted(cons)); print('streams:', prod)" "$1"; }
for seed in ${SEEDS:-1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16}; do
  QT_HASH_SEED=$seed PT_LIVE_DIR=$HOME/kde/${1:-live} NESTED_KWIN_ARGS="--width 1000 --height 700" ./run-nested-host.sh > nested-host.log 2>&1 &
  sleep 18; source nested-home-host/env.sh
  pids=$(for p in $(pgrep -x kwin_wayland; pgrep -x plasmashell); do tr '\0' '\n' < /proc/$p/environ 2>/dev/null | grep -q "^XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR$" && echo -n "$p,"; done)
  out="$(report "$pids")"
  if ! grep -q "consumer accepts:.*'BGRA'" <<<"$out"; then echo "seed $seed (consumer without BGRA)"; echo "$out"; found=1; fi
  [[ -n "${VERBOSE:-}" ]] && { echo "seed $seed"; echo "$out"; }
  tests/nested-stop.sh >/dev/null 2>&1; sleep 2
  [[ -n "${found:-}" ]] && break
done
[[ -n "${found:-}" ]] || echo "no seed produced a consumer without BGRA"
