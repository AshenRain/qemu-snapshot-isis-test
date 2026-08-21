#!/bin/bash
# Cold restart test: savevm -> kill QEMU -> wait -> qemu -loadvm snap1
# usage: TAG=B WAIT_SEC=900 POST_SEC=120 ./testB.sh
cd /root/qsnap
TAG=${TAG:-B}; WAIT_SEC=${WAIT_SEC:-900}; POST_SEC=${POST_SEC:-120}
R=results; mkdir -p $R
LOG=$R/test$TAG.log; : > $LOG
log(){ echo "[$(date -u +%T)] $*" | tee -a $LOG; }

log "=== TEST $TAG (cold restart): wait=${WAIT_SEC}s post=${POST_SEC}s ==="
log "=== BASELINE ==="
for n in 1 2; do ./snapshot.sh $n > $R/$TAG-baseline-vm$n.txt 2>&1; cat $R/$TAG-baseline-vm$n.txt >> $LOG; done

log "=== DELVM + SAVEVM snap$TAG (parallel) ==="
for n in 1 2; do python3 mon.py $n "delvm snap$TAG" 120 >> $LOG 2>&1; done
( python3 mon.py 1 "savevm snap$TAG" 900 > $R/$TAG-savevm-vm1.txt 2>&1 ) &
( python3 mon.py 2 "savevm snap$TAG" 900 > $R/$TAG-savevm-vm2.txt 2>&1 ) &
wait
for n in 1 2; do echo "vm$n savevm: $(grep -a ELAPSED $R/$TAG-savevm-vm$n.txt)" | tee -a $LOG; done

log "=== KILL QEMU (graceful quit via monitor) ==="
for n in 1 2; do python3 mon.py $n "quit" 30 >> $LOG 2>&1 & done
wait
sleep 5
pkill -f "qemu-system-x86_64 -name vm" 2>/dev/null
sleep 3
echo "qemu processes left: $(pgrep -cf 'qemu-system-x86_64 -name vm')" | tee -a $LOG
log "host bridge/tap state while QEMU is down:"
ip -br link show br-isis >> $LOG; ip -br link show tap1 >> $LOG; ip -br link show tap2 >> $LOG
for n in 1 2; do echo "--- vm$n snapshots on disk ---" >> $LOG; qemu-img info -U vm$n.qcow2 | sed -n '/Snapshot list/,$p' >> $LOG; done
ls -l vm1.qcow2 vm2.qcow2 | tee -a $LOG

log "=== WAITING ${WAIT_SEC}s with QEMU fully stopped ==="
sleep $WAIT_SEC

log "=== COLD START with -loadvm snap$TAG (parallel) ==="
T0=$(date +%s.%N)
( /usr/bin/time -f "vm1_qemu_start_sec=%e" -o $R/$TAG-coldstart-vm1.txt ./run-vm.sh 1 -loadvm snap$TAG ) &
( /usr/bin/time -f "vm2_qemu_start_sec=%e" -o $R/$TAG-coldstart-vm2.txt ./run-vm.sh 2 -loadvm snap$TAG ) &
wait
T1=$(date +%s.%N)
cat $R/$TAG-coldstart-vm1.txt $R/$TAG-coldstart-vm2.txt | tee -a $LOG
log "WALL_BOTH_COLDSTART_SEC=$(awk "BEGIN{printf \"%.3f\", $T1-$T0}")"
log "host date at restore: $(date -u '+%F %T UTC')"
for n in 1 2; do python3 mon.py $n "info status" 30 | grep -a "VM status" | tee -a $LOG; done

log "=== state IMMEDIATELY after cold start ==="
for n in 1 2; do ./snapshot.sh $n > $R/$TAG-after0-vm$n.txt 2>&1; cat $R/$TAG-after0-vm$n.txt >> $LOG; done
log "time to first guest response measured above"

log "=== +${POST_SEC}s ==="
sleep $POST_SEC
for n in 1 2; do ./snapshot.sh $n > $R/$TAG-after1-vm$n.txt 2>&1; cat $R/$TAG-after1-vm$n.txt >> $LOG; done
log "host date: $(date -u '+%F %T UTC')"
log "=== connectivity check ==="
python3 gc.py 1 'ping -c3 -W2 10.0.0.2; ping -c2 -W2 2.2.2.2' 30 >> $LOG 2>&1
log "=== TEST $TAG DONE ==="
