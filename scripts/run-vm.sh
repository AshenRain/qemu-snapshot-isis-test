#!/bin/bash
# usage: run-vm.sh <1|2> [extra qemu args...]
N=$1; shift
D=/root/qsnap
rm -f $D/vm$N-mon.sock $D/vm$N-ser.sock
qemu-system-x86_64 \
  -name vm$N \
  -machine q35,accel=kvm -cpu host -smp 2 -m 1024 \
  -rtc base=localtime,clock=vm \
  -drive file=$D/vm$N.qcow2,if=virtio,format=qcow2,cache=writeback \
  -drive file=$D/seed$N.iso,if=none,id=seed$N,format=raw,readonly=on \
  -device ide-cd,drive=seed$N \
  -netdev user,id=mgmt$N,hostfwd=tcp:127.0.0.1:222$N-:22 \
  -device virtio-net-pci,netdev=mgmt$N,mac=52:54:00:00:0$N:01 \
  -netdev tap,id=isis$N,ifname=tap$N,script=no,downscript=no \
  -device virtio-net-pci,netdev=isis$N,mac=52:54:00:00:0$N:02 \
  -display none -vga none \
  -chardev socket,id=ser$N,path=$D/vm$N-ser.sock,server=on,wait=off,logfile=$D/vm$N-console.log,logappend=on \
  -serial chardev:ser$N \
  -monitor unix:$D/vm$N-mon.sock,server=on,wait=off \
  -pidfile $D/vm$N.pid \
  -daemonize "$@"
