#!/bin/bash
# Test menu z nowymi pozycjami p i d
cd /root/deploy || exit 1
echo "=== ekran glowny (nowe pozycje):"
printf '0\n' | ./menu.sh 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E '^\s+(p|d|0|7|8|9)\)'
echo
echo "=== pozycja p (czy podatny):"
printf 'p\n\n0\n' | ./menu.sh 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | sed -n '/WERDYKT/,/Naciśnij/p' | head -8

