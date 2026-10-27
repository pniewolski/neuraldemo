#!/bin/bash
# Czy bug67198 jest niestabilny? 5 przebiegow na wersji Z LATKA i BEZ LATKI.
T=tests/basic/bug67198.phpt
for D in php-mod php-build-php-7.4-vanilla; do
  SRC=/usr/local/src/$D
  [ -x "$SRC/sapi/cli/php" ] || { echo "$D: brak"; continue; }
  case "$D" in
    php-mod) OPIS="Z LATKA   (php-mod)" ;;
    *)       OPIS="BEZ LATKI (vanilla)" ;;
  esac
  cd "$SRC" || continue
  P=0; F=0
  for i in 1 2 3 4 5; do
    rm -f "${T%.phpt}".{diff,out}
    if TEST_PHP_EXECUTABLE=sapi/cli/php sapi/cli/php run-tests.php -d opcache.enable_cli=0 "$T" 2>&1 \
       | grep -q '^PASS'; then P=$((P+1)); else F=$((F+1)); fi
    sleep 1
  done
  echo "$OPIS : PASS=$P  FAIL=$F"
done
echo
echo "=== obciazenie maszyny (wolny start serwera testowego to czesta przyczyna):"
uptime

