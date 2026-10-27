#!/bin/bash
# Ponowne sprawdzenie bug67198 po poprawce: bez flagi -q
cd /usr/local/src/php-mod || exit 1
T=tests/basic/bug67198.phpt
rm -f "${T%.phpt}".{diff,out}
echo "=== uruchomienie pojedyncze BEZ -q:"
TEST_PHP_EXECUTABLE=sapi/cli/php sapi/cli/php run-tests.php -d opcache.enable_cli=0 "$T" 2>&1 \
  | grep -E '^(PASS|FAIL|SKIP|BORK)|Tests (passed|failed|skipped)'
echo
echo "=== to samo z -q (pokazuje, dlaczego grep PASS zawodzil):"
rm -f "${T%.phpt}".{diff,out}
TEST_PHP_EXECUTABLE=sapi/cli/php sapi/cli/php run-tests.php -q -d opcache.enable_cli=0 "$T" 2>&1 \
  | grep -E '^(PASS|FAIL|SKIP|BORK)' || echo "  (brak linii PASS/FAIL - tryb cichy)"

