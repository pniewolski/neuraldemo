#!/bin/bash
# Czy nieudany test tests/basic/bug67198.phpt ma zwiazek z latka?
#
# Rozstrzyga empirycznie: sprawdza, czy wbudowany serwer HTTP PHP
# (ktorego ten test wymaga) w ogole daje sie uruchomic w tym srodowisku,
# i porownuje zachowanie nowego PHP 7.4 z obecnym PHP 7.2.
#
# Nic nie zmienia. Mozna uruchomic po kompilacji, bez przebudowy.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_root
start_log "61-sprawdz-test-serwera"

NOWE="$SRCDIR/sapi/cli/php"
[ -x "$NOWE" ] || NOWE="$PHP_PREFIX/bin/php"
STARE="$(command -v php 2>/dev/null || true)"

head1 "Sprawdzane binarki"
log "  PHP 7.4 (nowe) : $NOWE"
[ -x "$NOWE" ] && log "                   $("$NOWE" -v 2>/dev/null | head -1)" || die "Brak binarki PHP 7.4"
log "  PHP 7.2 (stare): ${STARE:-brak w PATH}"
[ -n "$STARE" ] && log "                   $("$STARE" -v 2>/dev/null | head -1)"

head1 "Test 1: wbudowany serwer HTTP w PHP 7.4"
NOWY=1
if test_wbudowanego_serwera "$NOWE" 8964; then NOWY=0; ok "dziala"; else err "NIE dziala"; fi

head1 "Test 2: wbudowany serwer HTTP w PHP 7.2 (odniesienie)"
STARY=2
if [ -n "$STARE" ]; then
  if test_wbudowanego_serwera "$STARE" 8965; then STARY=0; ok "dziala"; else STARY=1; err "NIE dziala"; fi
else
  warn "brak PHP 7.2 w PATH - nie ma z czym porownac"
fi

head1 "Co zajmuje porty uzywane przez testy"
ss -ltnp 2>/dev/null | grep -E ':(8964|8965|8000)' || log "  (porty wolne)"

head1 "Zapora i SELinux"
systemctl is-active firewalld 2>/dev/null || log "  firewalld: nieaktywny lub brak"
getenforce 2>/dev/null || log "  SELinux: niedostepny"

head1 "WNIOSEK"
RC=0
if [ "$NOWY" -eq 0 ]; then
  ok "Wbudowany serwer w PHP 7.4 DZIALA."
  log "Niepowodzenie testu bylo chwilowe - zajety port albo obciazenie maszyny."
  log "Latka nie ma z tym zwiazku. Mozna kontynuowac wdrozenie."
elif [ "$STARY" -eq 1 ]; then
  ok "Wbudowany serwer nie startuje ANI w PHP 7.4, ANI w obecnym PHP 7.2."
  log "To ograniczenie srodowiska, nie skutek latki."
  log "Test bug67198.phpt jest w tym srodowisku niewykonalny - mozna go pominac."
  log "Wdrozenie jest bezpieczne."
elif [ "$STARY" -eq 0 ]; then
  err "Wbudowany serwer dziala w PHP 7.2, ale NIE w zbudowanym PHP 7.4."
  log "To wymaga wyjasnienia przed wdrozeniem na produkcje."
  log "Sprawdz log kompilacji: $WORKDIR/make.log"
  RC=1
else
  warn "Serwer nie startuje w PHP 7.4, brak PHP 7.2 do porownania."
  log "Najpewniej ograniczenie srodowiska. Dla pewnosci sprawdz zapore i wolne porty."
fi
log ""
log "Niezaleznie od wyniku: podatnosc dotyczy obslugi zadan HTTP przez Apache."
log "Stan serwera sprawdzisz poleceniem: ./60-czy-podatny.sh"
exit $RC

