#!/bin/bash
# Test menu: wybor pozycji 1 (inwentaryzacja), potem wyjscie
cd /root/deploy || exit 1
printf '1\n\n0\n' | ./menu.sh 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -vE '^[[:space:]]*$' | tail -30
echo
echo "=== powtorne uruchomienie menu – czy pamieta wykryty DOCROOT:"
grep -H . /root/php74-migracja/docroot

