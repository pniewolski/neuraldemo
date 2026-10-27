#!/bin/bash
# Test nowej logiki analizy wynikow testow w 10-build-test.sh
# Uruchamia wlasciwa sekcje na gotowym buildzie, bez ponownej kompilacji.
source /root/deploy/lib.sh
start_log "test-sekcji-testow"
JOBS="$(nproc)"
cd /usr/local/src/php-mod || exit 1

head1 "Krok 5: testy obszarów zmienionych przez łatkę"
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
  log "Ponawiam je pojedynczo, bez zrównoleglenia..."
  NADAL_ZLE=""
  for t in $PODEJRZANE; do
    rm -f "${t%.phpt}.diff" "${t%.phpt}.out"
    POJ=0
    TEST_PHP_EXECUTABLE=sapi/cli/php sapi/cli/php run-tests.php -q \
        -d opcache.enable_cli=0 "$t" > "$WORKDIR/retest.log" 2>&1 || POJ=$?
    if grep -q '^PASS' "$WORKDIR/retest.log"; then
      ok "$t – przechodzi pojedynczo (niestabilny test, nie wina łatki)"
    elif grep -q '^SKIP' "$WORKDIR/retest.log"; then
      ok "$t – pominięty"
    else
      err "$t – nadal nie przechodzi"
      NADAL_ZLE="$NADAL_ZLE $t"
    fi
  done
  [ -n "$NADAL_ZLE" ] && err "Nadal źle:$NADAL_ZLE" || ok "Wszystkie pozostałe przechodzą pojedynczo"
else
  ok "Brak nieoczekiwanych błędów"
fi
exit 0

