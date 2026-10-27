#!/bin/bash
# Czy bug67198.phpt zawodzi przez łatkę, czy przez zestaw rozszerzeń?
T=tests/basic/bug67198.phpt
echo "=== tresc testu:"
cat /usr/local/src/php-mod/$T
echo
for D in php-mod php-build-php-7.4-patched php-build-php-7.4-vanilla; do
  SRC=/usr/local/src/$D
  [ -d "$SRC" ] || { echo "--- $D: brak"; continue; }
  BIN="$SRC/sapi/cli/php"
  [ -x "$BIN" ] || { echo "--- $D: brak binarki"; continue; }
  echo "--- $D  ($($BIN -v | head -1 | awk '{print $2}'))"
  cd "$SRC" || continue
  TEST_PHP_EXECUTABLE="$BIN" "$BIN" run-tests.php -q -d opcache.enable_cli=0 "$T" 2>&1 | grep -E '^(PASS|FAIL|SKIP|BORK)'
  [ -f "${T%.phpt}.diff" ] && { echo "    diff:"; sed 's/^/    /' "${T%.phpt}.diff" | head -12; }
done

