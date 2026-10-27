#!/bin/bash
# 40-wlacz-php74.sh – krok 8: przełączenie Apache z mod_php 7.2 na mod_php 7.4 z łatką.
#
# Podmienia ścieżkę w dyrektywie LoadModule i wykonuje PEŁNY restart Apache.
# W razie błędu automatycznie przywraca poprzednią konfigurację.
#
# UWAGA: wymaga krótkiej przerwy w działaniu strony – uruchamiaj w oknie serwisowym.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_root
start_log "40-wlacz-php74"

[ -f "$MOD_DIR/$MOD_NAME" ] || die "Brak modułu $MOD_DIR/$MOD_NAME – najpierw 10-build-test.sh lub 20-install-prod.sh"
[ -f "$PHP_PREFIX/etc/php.ini" ] || die "Brak $PHP_PREFIX/etc/php.ini – najpierw uruchom 30-konfiguracja-php.sh"

MODCONF=$(find_php_module_conf) || die "Nie znaleziono LoadModule php7_module w /etc/httpd/conf.modules.d/"
head1 "Konfiguracja modułu PHP"
log "Plik: $MODCONF"
sed 's/^/  /' "$MODCONF"

CUR=$(current_apache_php)
if [ "$CUR" = "74" ]; then
  ok "Apache już używa PHP 7.4 – nie ma co zmieniać"
  log "Weryfikacja: ./50-weryfikacja.sh"
  exit 0
fi
[ "$CUR" = "72" ] || warn "Nie rozpoznano obecnego modułu – sprawdź plik powyżej"

head1 "Kopia zapasowa"
BK="$WORKDIR/$(basename "$MODCONF").php72"
[ -f "$BK" ] || cp -a "$MODCONF" "$BK"
cp -a "$MODCONF" "$WORKDIR/$(basename "$MODCONF").przed-$(date +%Y%m%d-%H%M%S)"
ok "Kopia do rollbacku: $BK"

head1 "Podmiana modułu"
log "  libphp7.so (PHP 7.2)  ->  $MOD_NAME (PHP 7.4 z łatką)"
confirm "Wykonać podmianę i PEŁNY restart Apache (krótka przerwa w działaniu strony)?"

sed -i "s|modules/libphp7\.so|modules/$MOD_NAME|" "$MODCONF"
grep -q "$MOD_NAME" "$MODCONF" || { cp -a "$BK" "$MODCONF"; die "Podmiana nie powiodła się – przywrócono poprzedni plik"; }
sed 's/^/  /' "$MODCONF"

head1 "Test składni konfiguracji Apache"
if ! httpd -t; then
  cp -a "$BK" "$MODCONF"
  die "httpd -t zgłosił błąd – przywrócono PHP 7.2, Apache nie był restartowany"
fi
ok "Syntax OK"

head1 "Restart Apache"
warn "Używam 'systemctl restart' (pełny restart procesu)."
warn "Przeładowanie (reload / graceful / httpd -k restart) przy podmianie mod_php powoduje segfaulty."
if ! systemctl restart httpd; then
  err "Restart nieudany – przywracam PHP 7.2"
  cp -a "$BK" "$MODCONF"
  systemctl restart httpd || err "Nie udało się wystartować Apache! Sprawdź: journalctl -xe -u httpd"
  die "Przerwano. Logi: /var/log/httpd/error_log"
fi
sleep 2
systemctl is-active --quiet httpd || { cp -a "$BK" "$MODCONF"; systemctl restart httpd; die "Apache nie działa – przywrócono PHP 7.2"; }
ok "Apache uruchomiony"

head1 "Szybkie sprawdzenie"
VER=$(php_probe '<?php echo PHP_VERSION,"|",PHP_SAPI;')
log "Odpowiedź serwera: ${VER:-(brak)}"
case "$VER" in
  7.4*) ok "Apache obsługuje żądania przez PHP $VER" ;;
  "")   err "Brak odpowiedzi z $TEST_URL"
        tail -15 /var/log/httpd/error_log
        warn "Jeśli w logu są segfaulty lub strona nie działa, cofnij zmianę: ./90-rollback-php72.sh"
        exit 1 ;;
  *)    warn "Nieoczekiwana odpowiedź: $VER"; tail -10 /var/log/httpd/error_log ;;
esac

grep -c 'Segmentation fault' /var/log/httpd/error_log >/dev/null 2>&1 && \
  tail -200 /var/log/httpd/error_log | grep -q 'Segmentation fault' && \
  warn "W logu są wpisy o segmentation fault – sprawdź /var/log/httpd/error_log"

head1 "Gotowe"
log "Dalej: ./50-weryfikacja.sh"
log "Powrót do PHP 7.2 w razie problemów: ./90-rollback-php72.sh"

