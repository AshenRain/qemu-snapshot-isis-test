#!/usr/bin/env python3
# guest command over the QEMU serial console (survives snapshot restore)
import socket, sys, time, re
n = sys.argv[1]; cmd = sys.argv[2]
timeout = float(sys.argv[3]) if len(sys.argv) > 3 else 25.0
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect(f"/root/qsnap/vm{n}-ser.sock")
s.settimeout(0.4)
# drain
try:
    while True:
        if not s.recv(65536): break
except Exception: pass
MARK = "___E%dND___" % int(time.time()*1000 % 100000)
s.sendall(b"\n")
time.sleep(0.3)
try:
    while True:
        if not s.recv(65536): break
except Exception: pass
s.sendall((cmd + f"; echo {MARK}$?\n").encode())
buf = b""; t0 = time.time()
while time.time() - t0 < timeout:
    try:
        d = s.recv(65536)
        if not d: break
        buf += d
        if MARK.encode() in buf and buf.count(MARK.encode()) >= 2:
            break
    except socket.timeout:
        if MARK.encode() in buf and buf.count(MARK.encode()) >= 2:
            break
out = buf.decode(errors="replace").replace("\r", "")
lines = out.split("\n")
# strip echoed command line and marker lines
res = []
started = False
for l in lines:
    if not started:
        if MARK in l:   # echo of the command itself
            started = True
        continue
    if MARK in l:
        break
    res.append(l)
sys.stdout.write("\n".join(res).strip() + "\n")
