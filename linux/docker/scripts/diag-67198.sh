#!/bin/bash
cd /usr/local/src/php-mod || exit 1
T=tests/basic/bug67198.phpt
echo "=== procesy php nasluchujace (moga blokowac port testu):"
ps -eo pid,args | grep -E '[p]hp .*-S|[p]hp-cli' | head
ss -ltnp 2>/dev/null | grep -E '8964|8000' || echo "  (brak nasluchu na typowych portach testu)"
echo
echo "=== diff testu:"
cat "${T%.phpt}.diff" 2>/dev/null | head -20
echo
echo "=== out testu:"
cat "${T%.phpt}.out" 2>/dev/null | head -20
echo
echo "=== po sprzatnieciu procesow, ponowne uruchomienie:"
pkill -f 'php.*-S 127.0.0.1' 2>/dev/null
sleep 1
rm -f "${T%.phpt}".{diff,out}
TEST_PHP_EXECUTABLE=sapi/cli/php sapi/cli/php run-tests.php -d opcache.enable_cli=0 "$T" 2>&1 \
  | grep -E '^(PASS|FAIL|SKIP)|Tests (passed|failed)'

