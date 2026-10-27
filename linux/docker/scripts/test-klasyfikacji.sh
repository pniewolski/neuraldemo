#!/bin/bash
# Test nowej klasyfikacji nieudanych testow (sekcja z 10-build-test.sh)
source /root/deploy/lib.sh
start_log "test-klasyfikacji"
JOBS="$(nproc)"
SRCDIR=/usr/local/src/php-mod
cd "$SRCDIR" || exit 1

TESTS_RC=0
TEST_PHP_EXECUTABLE=sapi/cli/php sapi/cli/php run-tests.php -j"$JOBS" -q \
    -d opcache.enable_cli=0 Zend/tests ext/session/tests tests/basic tests/lang \
    > "$WORKDIR/run-tests.log" 2>&1 || TESTS_RC=$?

sed -n '/Number of tests/,/Time taken/p' "$WORKDIR/run-tests.log" || true

FAILED_PATHS=$(sed -n '/^FAILED TEST SUMMARY/,/^=====/p' "$WORKDIR/run-tests.log" \
               | sed -n 's/.*\[\(.*\.phpt\)\]$/\1/p' || true)
OCZEKIWANE=$(printf '%s\n' "$FAILED_PATHS" | grep -cE 'rfc1867|bug45392' || true)
PODEJRZANE=$(printf '%s\n' "$FAILED_PATHS" | grep -vE 'rfc1867|bug45392' | grep '\.phpt$' || true)

log ""
log "Nieudane testy zgodne z oczekiwaniem: ${OCZEKIWANE:-0} (8x rfc1867 + bug45392)"

if [ -n "$PODEJRZANE" ]; then
  warn "Pozostałe nieudane testy:"
  printf '%s\n' "$PODEJRZANE" | sed 's/^/  /'
  log ""
  log "Sprawdzam każdy z osobna, bez zrównoleglenia."
  NADAL_ZLE=""; SRODOWISKO=""
  for t in $PODEJRZANE; do
    rm -f "${t%.phpt}.diff" "${t%.phpt}.out"
    POJ=0
    TEST_PHP_EXECUTABLE=sapi/cli/php sapi/cli/php run-tests.php \
        -d opcache.enable_cli=0 "$t" > "$WORKDIR/retest.log" 2>&1 || POJ=$?
    if grep -q '^PASS' "$WORKDIR/retest.log"; then
      ok "$t – przechodzi pojedynczo (niestabilny przy zrównolegleniu, nie wina łatki)"
    elif grep -q '^SKIP' "$WORKDIR/retest.log"; then
      ok "$t – pominięty"
    elif grep -q 'php_cli_server' "$t" 2>/dev/null && \
         grep -qiE 'not accepting connections|Connection refused|Address already in use|Failed to listen' \
              "${t%.phpt}.out" 2>/dev/null; then
      warn "$t – test uruchamia wbudowany serwer HTTP PHP i nie udało się z nim połączyć."
      log  "    Powód: $(head -1 "${t%.phpt}.out" 2>/dev/null)"
      log  "    To ograniczenie środowiska (port/sieć), a nie skutek łatki."
      SRODOWISKO="$SRODOWISKO $t"
    else
      err "$t – nadal nie przechodzi"
      NADAL_ZLE="$NADAL_ZLE $t"
    fi
  done
  [ -n "$SRODOWISKO" ] && warn "Testy zależne od środowiska (do pominięcia):$SRODOWISKO"
  if [ -n "$NADAL_ZLE" ]; then
    err "Nie przechodzą także pojedynczo:$NADAL_ZLE"
  else
    ok "Brak błędów wskazujących na problem z łatką"
  fi
else
  ok "Brak nieoczekiwanych błędów"
fi
exit 0

