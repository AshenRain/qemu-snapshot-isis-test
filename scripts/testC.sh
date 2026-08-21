#!/bin/bash
# Test C: BFD (300ms x3) bound to IS-IS, then cold restart like test B
# usage: TAG=C WAIT_SEC=900 POST_SEC=120 ./testC.sh
cd /root/qsnap
TAG=${TAG:-C}; WAIT_SEC=${WAIT_SEC:-900}; POST_SEC=${POST_SEC:-120}
R=results; mkdir -p $R
LOG=$R/test$TAG.log; : > $LOG
log(){ echo "[$(date -u +%T)] $*" | tee -a $LOG; }

log "=== TEST $TAG (BFD + cold restart): wait=${WAIT_SEC}s post=${POST_SEC}s ==="
log "=== configuring BFD 300ms x3 on both VMs ==="
for n in 1 2; do
  peer=$([ $n = 1 ] && echo 10.0.0.2 || echo 10.0.0.1)
  python3 gc.py $n "vtysh -c 'configure terminal' -c 'bfd' -c 'profile fast' -c 'transmit-interval 300' -c 'receive-interval 300' -c 'detect-multiplier 3' -c 'end' -c 'configure terminal' -c 'interface eth1' -c 'isis bfd' -c 'isis bfd profile fast' -c 'end' -c 'write memory'" 60 >> $LOG 2>&1
done
log "=== waiting for BFD to come Up ==="
for i in $(seq 1 20); do
  s=$(python3 gc.py 1 "vtysh -c 'show bfd peers brief' | grep -c up" 30 | tr -d ' \r')
  [ "$s" = "1" ] && break
  sleep 5
done
for n in 1 2; do echo "--- vm$n bfd ---" >> $LOG; python3 gc.py $n "vtysh -c 'show bfd peers'" 40 >> $LOG 2>&1; done
sleep 30

log "=== BASELINE ==="
for n in 1 2; do ./snapshot.sh $n > $R/$TAG-baseline-vm$n.txt 2>&1; cat $R/$TAG-baseline-vm$n.txt >> $LOG; done
for n in 1 2; do python3 gc.py $n "vtysh -c 'show bfd peers'" 40 > $R/$TAG-baseline-bfd-vm$n.txt 2>&1; cat $R/$TAG-baseline-bfd-vm$n.txt >> $LOG; done

log "=== DELVM + SAVEVM snap$TAG (parallel) ==="
for n in 1 2; do python3 mon.py $n "delvm snap$TAG" 300 >> $LOG 2>&1; done
( python3 mon.py 1 "savevm snap$TAG" 900 > $R/$TAG-savevm-vm1.txt 2>&1 ) &
( python3 mon.py 2 "savevm snap$TAG" 900 > $R/$TAG-savevm-vm2.txt 2>&1 ) &
wait
for n in 1 2; do echo "vm$n savevm: $(grep -a ELAPSED $R/$TAG-savevm-vm$n.txt)" | tee -a $LOG; done

log "=== KILL QEMU ==="
for n in 1 2; do python3 mon.py $n "quit" 30 >> $LOG 2>&1 & done
wait; sleep 5
pkill -f "qemu-system-x86_64 -name vm" 2>/dev/null; sleep 3
echo "qemu processes left: $(pgrep -cf 'qemu-system-x86_64 -name vm')" | tee -a $LOG

log "=== WAITING ${WAIT_SEC}s with QEMU fully stopped ==="
sleep $WAIT_SEC

log "=== COLD START with -loadvm snap$TAG ==="
T0=$(date +%s.%N)
( /usr/bin/time -f "vm1_qemu_start_sec=%e" -o $R/$TAG-coldstart-vm1.txt ./run-vm.sh 1 -loadvm snap$TAG ) &
( /usr/bin/time -f "vm2_qemu_start_sec=%e" -o $R/$TAG-coldstart-vm2.txt ./run-vm.sh 2 -loadvm snap$TAG ) &
wait
T1=$(date +%s.%N)
cat $R/$TAG-coldstart-vm1.txt $R/$TAG-coldstart-vm2.txt | tee -a $LOG
log "WALL_BOTH_COLDSTART_SEC=$(awk "BEGIN{printf \"%.3f\", $T1-$T0}")"

log "=== BFD POLL: 60 samples, 1/s, starting immediately ==="
python3 gc.py 1 'for i in $(seq 1 60); do echo "$(date +%T.%2N) BFD=$(vtysh -c "show bfd peers brief" | grep -oE "up|down" | tail -1) ISIS_ADJ=$(vtysh -c "show isis neighbor" | grep -c Up) ROUTE=$(vtysh -c "show ip route isis" | grep -c 2.2.2.2)"; done' 180 > $R/$TAG-bfdpoll-vm1.txt 2>&1
cat $R/$TAG-bfdpoll-vm1.txt >> $LOG

log "=== full state after cold start ==="
for n in 1 2; do ./snapshot.sh $n > $R/$TAG-after0-vm$n.txt 2>&1; cat $R/$TAG-after0-vm$n.txt >> $LOG; done
for n in 1 2; do python3 gc.py $n "vtysh -c 'show bfd peers'" 40 > $R/$TAG-after0-bfd-vm$n.txt 2>&1; cat $R/$TAG-after0-bfd-vm$n.txt >> $LOG; done

log "=== +${POST_SEC}s ==="
sleep $POST_SEC
for n in 1 2; do ./snapshot.sh $n > $R/$TAG-after1-vm$n.txt 2>&1; cat $R/$TAG-after1-vm$n.txt >> $LOG; done
for n in 1 2; do python3 gc.py $n "vtysh -c 'show bfd peers'" 40 > $R/$TAG-after1-bfd-vm$n.txt 2>&1; cat $R/$TAG-after1-bfd-vm$n.txt >> $LOG; done
python3 gc.py 1 'ping -c3 -W2 2.2.2.2' 30 >> $LOG 2>&1
log "=== TEST $TAG DONE ==="
