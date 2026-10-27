#!/bin/bash
T=tests/basic/bug67198.phpt
for D in php-mod php-build-php-7.4-vanilla; do
  SRC=/usr/local/src/$D
  BIN="$SRC/sapi/cli/php"
  [ -x "$BIN" ] || { echo "--- $D: brak binarki"; continue; }
  echo "===================== $D"
  cd "$SRC" || continue
  rm -f "${T%.phpt}".{diff,out,log,exp}
  TEST_PHP_EXECUTABLE="$BIN" "$BIN" run-tests.php -d opcache.enable_cli=0 "$T" 2>&1 | tail -20
  if [ -f "${T%.phpt}.diff" ]; then echo "--- diff:"; head -15 "${T%.phpt}.diff"; fi
  if [ -f "${T%.phpt}.out" ]; then echo "--- out:"; head -10 "${T%.phpt}.out"; fi
done

