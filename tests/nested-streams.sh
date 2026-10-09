#!/usr/bin/env bash
# Lists the PipeWire streams of the nested KWin (not those of the real session, which
# shares the PipeWire daemon): state and negotiated format.
source ~/kde/nested-home-host/env.sh
pid=""
for p in $(pgrep -x kwin_wayland); do
  tr '\0' '\n' < /proc/$p/environ 2>/dev/null | grep -q "^XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR$" && pid=$p
done
pw-dump 2>/dev/null | python3 -c "
import json,sys
pid=sys.argv[1]; objs=json.load(sys.stdin)
clients={o['id'] for o in objs if o.get('type','').endswith('Client') and str((o.get('info',{}).get('props') or {}).get('pipewire.sec.pid'))==pid}
out=[]
for o in objs:
    i=o.get('info') or {}; pr=i.get('props') or {}
    if o.get('type','').endswith('Node') and pr.get('client.id') in clients:
        f=[(x.get('size',{}).get('width'),x.get('size',{}).get('height'),x.get('format')) for x in i.get('params',{}).get('Format',[])]
        out.append(f\"{pr.get('media.name') or pr.get('node.description') or pr.get('node.name')}: {i.get('state')} {f[0] if f else ''}\")
print(' | '.join(sorted(out)) or 'no streams')" "$pid"
