#!/bin/bash
cd /root/deploy || exit 1
printf '0\n' | ./menu.sh 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -n 'PODATNY\|Diagnoza\|Wyjscie\|Wyjście\|^ *p)\|^ *d)'

