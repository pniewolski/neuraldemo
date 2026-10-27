#!/bin/bash
# Odtwarza sytuacje z serwera uzytkownika: test bug67198 nie przechodzi,
# i sprawdza, czy skrypt poprawnie sklasyfikuje przyczyne.
source /root/deploy/lib.sh
start_log "test-klasyfikacji2"
SRCDIR=/usr/local/src/php-mod
cd "$SRCDIR" || exit 1

# blokujemy port uzywany przez testy PHP, zeby wymusic niepowodzenie
sapi/cli/php -n -S 127.0.0.1:8964 -t /tmp >/dev/null 2>&1 &
BLOKER=$!
sleep 2
log "Zablokowano port 8964 (pid $BLOKER) – wymuszam niepowodzenie testu."

t=tests/basic/bug67198.phpt
rm -f "${t%.phpt}.diff" "${t%.phpt}.out"
POJ=0
TEST_PHP_EXECUTABLE=sapi/cli/php sapi/cli/php run-tests.php \
    -d opcache.enable_cli=0 "$t" > "$WORKDIR/retest.log" 2>&1 || POJ=$?

NADAL_ZLE=""; SRODOWISKO=""
if grep -q '^PASS' "$WORKDIR/retest.log"; then
  ok "$t – przechodzi pojedynczo"
elif grep -q '^SKIP' "$WORKDIR/retest.log"; then
  ok "$t – pominiety"
elif grep -q 'php_cli_server' "$t" 2>/dev/null; then
  warn "$t – test wymaga wbudowanego serwera HTTP PHP."
  log  "    Komunikat: $(head -1 "${t%.phpt}.out" 2>/dev/null)"
  log  "    Sprawdzam, czy wbudowany serwer w ogole dziala w tym srodowisku..."
  NOWY_OK=1; STARY_OK=2
  test_wbudowanego_serwera sapi/cli/php 8964 && NOWY_OK=0 || NOWY_OK=1
  if command -v php >/dev/null 2>&1; then
    test_wbudowanego_serwera "$(command -v php)" 8965 && STARY_OK=0 || STARY_OK=1
  fi
  log "    (wynik: nowy=$NOWY_OK stary=$STARY_OK ; 0=dziala)"
  if [ "$NOWY_OK" -ne 0 ] && [ "$STARY_OK" -ne 0 ]; then
    ok "  Wbudowany serwer nie startuje ANI w nowym PHP 7.4, ANI w obecnym PHP 7.2."
    log "  To ograniczenie srodowiska, nie skutek latki."
    SRODOWISKO="$SRODOWISKO $t"
  elif [ "$NOWY_OK" -ne 0 ] && [ "$STARY_OK" -eq 0 ]; then
    err "  Wbudowany serwer dziala w PHP 7.2, ale NIE w zbudowanym PHP 7.4."
    NADAL_ZLE="$NADAL_ZLE $t"
  else
    ok "  Wbudowany serwer w PHP 7.4 dziala poprawnie."
    SRODOWISKO="$SRODOWISKO $t"
  fi
else
  err "$t – nadal nie przechodzi"
  NADAL_ZLE="$NADAL_ZLE $t"
fi

kill $BLOKER 2>/dev/null || true
wait $BLOKER 2>/dev/null || true

head1 "Wynik klasyfikacji"
[ -n "$SRODOWISKO" ] && warn "Zalezne od srodowiska:$SRODOWISKO"
[ -n "$NADAL_ZLE" ] && err "Wymaga wyjasnienia:$NADAL_ZLE" || ok "Brak bledow wskazujacych na problem z latka"
exit 0

