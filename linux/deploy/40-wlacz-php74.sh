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
warn "Używam pełnego restartu procesu (systemctl restart httpd)."
warn "Przeładowanie (reload / graceful / httpd -k restart) przy podmianie mod_php powoduje segfaulty."
if ! restart_httpd; then
  err "Restart nieudany – przywracam PHP 7.2"
  cp -a "$BK" "$MODCONF"
  restart_httpd || err "Nie udało się wystartować Apache! Sprawdź: journalctl -xe -u httpd"
  die "Przerwano. Logi: /var/log/httpd/error_log"
fi
sleep 2
if ! httpd_is_running; then
  cp -a "$BK" "$MODCONF"
  restart_httpd || true
  die "Apache nie działa po restarcie – przywrócono PHP 7.2"
fi
ok "Apache uruchomiony"

head1 "Szybkie sprawdzenie"
# Jeśli skonfigurowany adres nie działa, spróbuj znaleźć właściwy DocumentRoot
auto_docroot >/dev/null 2>&1 || true

if VER=$(php_probe '<?php echo PHP_VERSION,"|",PHP_SAPI;'); then
  log "Odpowiedź serwera: $VER"
  case "$VER" in
    7.4*) ok "Apache obsługuje żądania przez PHP $VER" ;;
    *)    warn "Nieoczekiwana wersja: $VER"; tail -10 /var/log/httpd/error_log ;;
  esac
else
  # brak odpowiedzi nie musi oznaczać awarii – sprawdzamy stan innymi metodami
  warn "Nie udało się wykonać testowego żądania HTTP."
  log ""

  WERSJA_LOG=$(grep -o 'PHP/[0-9][^ ]*' /var/log/httpd/error_log 2>/dev/null | tail -1 || true)
  if [ -n "$WERSJA_LOG" ]; then
    case "$WERSJA_LOG" in
      PHP/7.4*) ok "Log Apache potwierdza start z $WERSJA_LOG – podmiana modułu ZADZIAŁAŁA" ;;
      *)        err "Log Apache pokazuje $WERSJA_LOG – podmiana mogła się nie udać" ;;
    esac
  fi
  if grep -qa 'max_multipart_body_parts' "$MOD_DIR/$MOD_NAME" 2>/dev/null; then
    ok "Zainstalowany moduł zawiera łatkę"
  fi
  if httpd_is_running; then ok "Apache działa"; else err "Apache NIE działa"; fi

  log ""
  log "Samo żądanie HTTP nie przeszło. Najczęstsza przyczyna to niewłaściwy TEST_URL/DOCROOT"
  log "w config.sh albo brak lokalnego dostępu do serwera (zapora, vhost)."
  log ""
  log "Co zrobić:"
  log "  1) ./99-diagnoza-http.sh   – wskaże, co dokładnie blokuje połączenie"
  log "  2) ./60-czy-podatny.sh     – potwierdzi stan serwera bez użycia HTTP"
  log "  3) sprawdź stronę w przeglądarce"
  log ""
  log "Gdyby aplikacja nie działała: ./90-rollback-php72.sh"
  diagnoza_probe
  exit 1
fi

if tail -200 /var/log/httpd/error_log 2>/dev/null | grep -q 'Segmentation fault'; then
  warn "W logu Apache są wpisy o segmentation fault – sprawdź /var/log/httpd/error_log"
fi

head1 "Gotowe"
log "Dalej: ./50-weryfikacja.sh"
log "Powrót do PHP 7.2 w razie problemów: ./90-rollback-php72.sh"



