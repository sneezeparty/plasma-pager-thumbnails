#!/usr/bin/env python3
# Measures CPU/GPU of the nested KWin + plasmashell (+ mpv) over a window, and mpv's playback health.
import json, socket, subprocess, sys, time, os
label, secs = sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 16
SOCK = os.path.expanduser('~/kde/tests/mpv.sock')
def pid(pat):
    r = subprocess.run(['pgrep', '-n', '-f', pat], capture_output=True, text=True).stdout.split()
    return int(r[0]) if r else None
pids = {'kwin': pid(r'^kwin_wayland .*--socket wayland-neste[d]'), 'shell': pid(r'kde/usr/bin/[p]lasmashell'), 'mpv': pid(os.environ.get('APP_PAT', r'^mpv --no-audio'))}
def mpv(prop):
    try:
        s = socket.socket(socket.AF_UNIX); s.settimeout(2); s.connect(SOCK)
        s.sendall((json.dumps({'command': ['get_property', prop]}) + '\n').encode())
        buf = b''
        while b'\n' not in buf: buf += s.recv(4096)
        for line in buf.split(b'\n'):
            if line and b'"error"' in line: return json.loads(line).get('data')
    except Exception: return None
props = ['frame-drop-count', 'decoder-frame-drop-count', 'vo-delayed-frame-count']
before = {p: mpv(p) for p in props} if pids['mpv'] else {}
live = [str(p) for p in pids.values() if p]
top = subprocess.Popen(['top', '-b', '-n', str(secs // 2 + 1), '-d', '2', '-p', ','.join(live)], stdout=subprocess.PIPE, text=True)
pmon = subprocess.Popen(['nvidia-smi', 'pmon', '-c', str(secs), '-s', 'u'], stdout=subprocess.PIPE, text=True)
smi = subprocess.Popen(['nvidia-smi', '--query-gpu=utilization.gpu,power.draw', '--format=csv,noheader,nounits', '-l', '1'], stdout=subprocess.PIPE, text=True)
pm = pmon.communicate()[0]; tp = top.communicate()[0]; smi.terminate(); sm = smi.communicate()[0]
cpu = {k: [] for k in pids}; gpu = {k: [] for k in pids}; dec = {k: [] for k in pids}
first = True
for block in tp.split('\ntop - ')[1:]:          # skip the first sample (since-boot averages)
    for line in block.splitlines():
        f = line.split()
        for k, p in pids.items():
            if p and f and f[0] == str(p): cpu[k].append(float(f[8]))
for line in pm.splitlines():
    f = line.split()
    for k, p in pids.items():
        if p and len(f) > 6 and f[1] == str(p):
            gpu[k].append(0.0 if f[3] == '-' else float(f[3])); dec[k].append(0.0 if f[6] == '-' else float(f[6]))
avg = lambda v: sum(v) / len(v) if v else 0.0
tot = [tuple(map(float, l.split(','))) for l in sm.strip().splitlines() if ',' in l]
out = f"{label:34s} CPU kwin {avg(cpu['kwin']):5.1f} shell {avg(cpu['shell']):4.1f}"
out += f" | GPU kwin {avg(gpu['kwin']):4.1f} shell {avg(gpu['shell']):4.1f}"
if pids['mpv']:
    after = {p: mpv(p) for p in props}
    d = lambda p: (after[p] or 0) - (before[p] or 0)
    out += f" | app CPU {avg(cpu['mpv']):5.1f} GPU {avg(gpu['mpv']):4.1f} dec {avg(dec['mpv']):4.1f} fps {mpv('estimated-vf-fps') or 0:.1f} hwdec {mpv('hwdec-current')}"
    out += f" drops vo {d('frame-drop-count')} dec {d('decoder-frame-drop-count')} late {d('vo-delayed-frame-count')}"
out += f" | card {avg([t[0] for t in tot]):.0f}% {avg([t[1] for t in tot]):.0f}W"
print(out, flush=True)
