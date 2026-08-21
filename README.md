# Do routing protocols survive a QEMU snapshot restore?

*[Русская версия](README_ru.md)*

An empirical check of whether a live IS-IS adjacency and a BFD session survive restoring a virtual machine from a QEMU snapshot (`savevm` / `loadvm`) — including a full cold restart of the QEMU process.

The motivation: training an LLM agent with reinforcement learning needs thousands of scenario runs on a network device simulator, and booting a virtual router until its protocols converge takes minutes. The idea is to restore the lab from a snapshot in which the network has already converged. Before building an architecture on that assumption, it had to be verified that the protocols actually survive it.

**Full report: [REPORT.md](REPORT.md)** (in Russian).

## Results

| Test | What was checked | Outcome |
|---|---|---|
| **A** | `savevm` → 15 minutes → `loadvm` inside the live QEMU process | **passed** — adjacency Up, LSDB bit-for-bit identical, routes intact |
| **B** | `savevm` → QEMU processes fully terminated → 15 minutes → cold start with `-loadvm` | **passed** — same result, with no manual intervention and no reconvergence |
| **C** | Same, with BFD 300 ms × 3 bound to IS-IS | **does not survive** — the session drops, recovers on its own in ~3–4 s, routes in ~34 s |

Key numbers (2 vCPU, 1 GB RAM per node, NVMe SSD):

| Metric | Value |
|---|---|
| `loadvm` inside a live QEMU process | 3.0 / 3.2 s |
| **Cold start with `-loadvm`** | **3.25 / 3.38 s** |
| `savevm` in steady state | 1.6–2.1 s |
| Snapshot size (`VM_SIZE`) | 917–950 MB for 1024 MB of guest RAM |
| Full boot to convergence, for comparison | ~170 s |

Lab preparation is roughly **50× faster**.

## The main finding

The binding constraint is not how long the snapshot sits unused before it is restored — that can be anything, verified over 15 minutes — but **how long the `savevm` operation itself takes**.

While QEMU writes guest memory to disk, the guest vCPUs are stopped, but the clock state captured in the snapshot corresponds to the *end* of that write, whereas the last instruction the guest actually executed corresponds to its *beginning*. A restored guest therefore wakes up with every timer overdue by exactly the duration of the write.

A controlled measurement of the full cycle:

```
savevm (freeze)                 63.05 s
downtime with QEMU killed       15.07 s
QEMU startup with -loadvm        1.96 s
────────────────────────────────────────
elapsed on the HOST             81.21 s
counted by the GUEST (uptime)   64.11 s   ← exactly the savevm duration
```

The guest did not notice the downtime or the restore at all. Hence the rule: **`savevm` must be shorter than the shortest detection timer in the lab.**

| Freeze | Threshold crossed | Consequence |
|---|---|---|
| 1.6 s | IS-IS holdtime of 30 s — not crossed | nothing |
| 2.1 s | BFD detection time of **0.9 s** | session drops, adjacency flaps, 34 s until routes return |
| 118 s | `WatchdogSec=60` on `frr.service` | systemd killed the FRR daemons with signal 6 |

## The lab

Two QEMU VMs (Ubuntu 24.04 cloud image + FRRouting 8.4.4) connected through tap interfaces on a host Linux bridge. IS-IS level-2-only point-to-point with `metric-style wide`, plus loopbacks `1.1.1.1/32` and `2.2.2.2/32` serving as the routes under test. Clocks are pinned with `-rtc base=localtime,clock=vm`, and time synchronisation inside the guests is disabled.

Host: Windows 11 with WSL2 (Ubuntu 26.04, nested KVM), QEMU 10.2.1, NVMe SSD.

Choosing tap + bridge over `-netdev socket` matters: the bridge and tap interfaces live on the host and survive a full QEMU shutdown, so connectivity comes back by itself after a cold start and node startup order is irrelevant. Confirmed — it never caused a problem.

## Layout

```
REPORT.md                  full report, in Russian
README_ru.md               this page, in Russian
scripts/
  run-vm.sh                launches a VM; also used for the cold start with -loadvm
  testA.sh testB.sh testC.sh   test scenarios, parameterised by pause duration
  mon.py                   QEMU monitor access over a unix socket, with timing
  gc.py                    runs commands in a guest over the serial console
  snapshot.sh              captures reference state (neighbor / database / route / bfd / date)
results/
  test{A,B,C}.log          run logs with timestamps
  {A,B,C}-baseline-*.txt   state before the snapshot
  {A,B,C}-after0-*.txt     state immediately after the restore
  {A,B,C}-after1-*.txt     state two minutes later
  C-bfdpoll-vm1.txt        BFD / IS-IS / route polling after the cold start, 60 samples
  vm{1,2}-console.log      full serial console logs from both guests
```

Guest commands were issued over the serial console rather than ssh: an ssh session breaks on restore, whereas a serial console session lives in guest memory and is restored along with it.

## Reproducing

Requires a Linux host with KVM, QEMU and `cloud-image-utils`. The scripts assume a working directory of `/root/qsnap` containing `vm1.qcow2` / `vm2.qcow2`, and a host bridge `br-isis` with `tap1` / `tap2` attached.

```bash
TAG=A WAIT_SEC=900 POST_SEC=120 ./testA.sh   # restore inside the live process
TAG=B WAIT_SEC=900 POST_SEC=120 ./testB.sh   # cold restart
TAG=C WAIT_SEC=900 POST_SEC=120 ./testC.sh   # same, with BFD
```

For a quick sanity check without the long pauses, use `WAIT_SEC=20 POST_SEC=15`.

## Caveats

The lab ran under WSL2 with nested virtualisation, where kvmclock may behave differently than on bare metal; that is worth verifying separately. One run was contaminated by the host entering Modern Standby (confirmed by Kernel-Power event 506); it was re-run, but is kept in the report because it is precisely the run that exposed the FRR watchdog failure mode.
