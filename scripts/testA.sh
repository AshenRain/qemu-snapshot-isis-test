#!/bin/bash
# usage: TAG=A WAIT_SEC=900 POST_SEC=120 ./testA.sh
cd /root/qsnap
TAG=${TAG:-A}; WAIT_SEC=${WAIT_SEC:-900}; POST_SEC=${POST_SEC:-120}
R=results; mkdir -p $R
LOG=$R/test$TAG.log; : > $LOG
log(){ echo "[$(date -u +%T)] $*" | tee -a $LOG; }

log "=== TEST $TAG: wait=${WAIT_SEC}s post=${POST_SEC}s ==="
log "=== BASELINE ==="
for n in 1 2; do ./snapshot.sh $n > $R/$TAG-baseline-vm$n.txt 2>&1; cat $R/$TAG-baseline-vm$n.txt >> $LOG; done

log "=== DELVM (cleanup) ==="
for n in 1 2; do python3 mon.py $n "delvm snap1" 120 >> $LOG 2>&1; done

log "=== SAVEVM snap1 (parallel) ==="
( python3 mon.py 1 "savevm snap1" 900 > $R/$TAG-savevm-vm1.txt 2>&1 ) &
( python3 mon.py 2 "savevm snap1" 900 > $R/$TAG-savevm-vm2.txt 2>&1 ) &
wait
for n in 1 2; do echo "vm$n savevm: $(grep -a ELAPSED $R/$TAG-savevm-vm$n.txt)" | tee -a $LOG; done
for n in 1 2; do echo "--- qemu-img info vm$n ---" >> $LOG; qemu-img info -U vm$n.qcow2 >> $LOG 2>&1; done
ls -l vm1.qcow2 vm2.qcow2 | tee -a $LOG

log "=== WAITING ${WAIT_SEC}s ==="
sleep $WAIT_SEC
log "=== state just BEFORE loadvm ==="
for n in 1 2; do ./snapshot.sh $n > $R/$TAG-before-loadvm-vm$n.txt 2>&1; cat $R/$TAG-before-loadvm-vm$n.txt >> $LOG; done

log "=== LOADVM snap1 (parallel) ==="
T0=$(date +%s.%N)
( python3 mon.py 1 "loadvm snap1" 900 > $R/$TAG-loadvm-vm1.txt 2>&1 ) &
( python3 mon.py 2 "loadvm snap1" 900 > $R/$TAG-loadvm-vm2.txt 2>&1 ) &
wait
T1=$(date +%s.%N)
for n in 1 2; do echo "vm$n loadvm: $(grep -a ELAPSED $R/$TAG-loadvm-vm$n.txt)" | tee -a $LOG; done
log "WALL_BOTH_LOADVM_SEC=$(awk "BEGIN{printf \"%.3f\", $T1-$T0}")"
log "host date at restore: $(date -u '+%F %T UTC')"

log "=== state IMMEDIATELY after loadvm ==="
for n in 1 2; do ./snapshot.sh $n > $R/$TAG-after0-vm$n.txt 2>&1; cat $R/$TAG-after0-vm$n.txt >> $LOG; done

log "=== +${POST_SEC}s ==="
sleep $POST_SEC
for n in 1 2; do ./snapshot.sh $n > $R/$TAG-after1-vm$n.txt 2>&1; cat $R/$TAG-after1-vm$n.txt >> $LOG; done
log "host date: $(date -u '+%F %T UTC')"
log "=== TEST $TAG DONE ==="
