#!/bin/bash
# capture the three reference commands from a guest
n=$1
python3 /root/qsnap/gc.py $n 'vtysh -c "show isis neighbor" ; echo "--DB--" ; vtysh -c "show isis database" ; echo "--RT--" ; vtysh -c "show ip route isis" ; echo "--BFD--" ; vtysh -c "show bfd peers brief" ; echo "--DATE--" ; date -u "+%F %T UTC"' 40
