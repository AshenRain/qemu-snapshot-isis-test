#!/usr/bin/env python3
import socket, sys, time
n = sys.argv[1]; cmd = sys.argv[2]
timeout = float(sys.argv[3]) if len(sys.argv) > 3 else 600.0
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect(f"/root/qsnap/vm{n}-mon.sock")
s.settimeout(3)
buf = b""
try:
    while True:
        d = s.recv(65536); buf += d
        if buf.rstrip().endswith(b"(qemu)"): break
except Exception: pass
t0 = time.time()
s.sendall((cmd + "\n").encode())
out = b""; s.settimeout(timeout); deadline = time.time() + timeout
while time.time() < deadline:
    try: d = s.recv(65536)
    except socket.timeout: break
    if not d: break
    out += d
    if out.rstrip().endswith(b"(qemu)") and cmd.encode() in out: break
el = time.time() - t0
print("ELAPSED_SEC=%.3f" % el)
print(out.decode(errors="replace").replace("\r", ""))
