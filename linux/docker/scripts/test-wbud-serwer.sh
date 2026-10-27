#!/bin/bash
# Test funkcji test_wbudowanego_serwera w trzech sytuacjach
source /root/deploy/lib.sh
start_log "test-wbud-serwera"

head1 "A. Normalnie – wbudowany serwer PHP 7.4"
if test_wbudowanego_serwera /usr/local/src/php-mod/sapi/cli/php 8964; then
  ok "serwer wystartowal i odpowiedzial"
else
  err "serwer NIE wystartowal"
fi

head1 "B. Port zajety – symulacja warunkow z serwera uzytkownika"
# zajmujemy port, zeby wbudowany serwer nie mogl sie zbindowac
/usr/local/src/php-mod/sapi/cli/php -n -S 127.0.0.1:8970 -t /tmp >/dev/null 2>&1 &
BLOKER=$!
sleep 2
if test_wbudowanego_serwera /usr/local/src/php-mod/sapi/cli/php 8970; then
  err "nieoczekiwanie wystartowal mimo zajetego portu"
else
  ok "poprawnie wykryto, ze serwer nie startuje (port zajety)"
fi
kill $BLOKER 2>/dev/null || true
wait $BLOKER 2>/dev/null || true

head1 "C. Nieistniejaca binarka"
if test_wbudowanego_serwera /nie/ma/takiego/php 8964; then
  err "nieoczekiwany sukces"
else
  ok "poprawnie zwrocil blad"
fi

head1 "D. Czas wykonania (nie powinien blokowac na dlugo)"
S=$(date +%s)
test_wbudowanego_serwera /usr/local/src/php-mod/sapi/cli/php 8964 >/dev/null 2>&1
E=$(date +%s)
log "  czas: $((E-S)) s"
exit 0


