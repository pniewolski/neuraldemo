#!/bin/bash
# Test menu.sh – symuluje wybory użytkownika i sprawdza, czy ekran się poprawnie renderuje.
cd /root/deploy || exit 1
bash -n menu.sh || { echo "BLAD SKLADNI"; exit 1; }
echo "=== skladnia menu.sh OK"
echo
echo "=== ekran startowy (rola: test, wyjscie od razu):"
rm -f /root/php74-migracja/rola
printf '1\n0\n' | ./menu.sh 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | tail -40

