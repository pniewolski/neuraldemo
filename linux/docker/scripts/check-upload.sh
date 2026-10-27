#!/bin/bash
cd /tmp/upl || exit 1
for f in *.sh; do
  if bash -n "$f"; then echo "OK   $f"; else echo "BLAD $f"; fi
done
echo "--- wywolania 60/61/99 w menu (oczekiwane 3):"
grep -cE 'uruchom (60|61|99)-' menu.sh
echo "--- pliki z CR (oczekiwane: brak):"
grep -l $'\r' *.sh docs/*.md README.md 2>/dev/null || echo "brak"

