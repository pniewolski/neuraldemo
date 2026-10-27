#!/bin/bash
# Uruchamia smoke test przez Apache dla aktywnej wersji PHP.
set -e
echo hello > /tmp/up.txt; printf hello > /tmp/up.txt
curl -s "http://127.0.0.1/smoke.php?a[b][c]=x" \
  -F field=value -F "up=@/tmp/up.txt" -F "many[]=@/tmp/up.txt" -F "many[]=@/tmp/up.txt"

