#!/bin/bash
cd /root/deploy || exit 1
./01-inwentaryzacja.sh >/tmp/i.out 2>&1; echo "RC inwentaryzacja = $?"
./50-weryfikacja.sh    >/tmp/w.out 2>&1; echo "RC weryfikacja   = $?"
echo "--- weryfikacja, podsumowanie:"
tail -20 /tmp/w.out

