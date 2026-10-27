#!/bin/bash
# 90-rollback-php72.sh – krok 11: powrót Apache do PHP 7.2.
# Przywraca kopię pliku z LoadModule i wykonuje pełny restart Apache.
# Nie usuwa PHP 7.4 – można je włączyć ponownie skryptem 40-wlacz-php74.sh.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_root
start_log "90-rollback-php72"

MODCONF=$(find_php_module_conf) || die "Nie znaleziono LoadModule php7_module w /etc/httpd/conf.modules.d/"
BK="$WORKDIR/$(basename "$MODCONF").php72"

head1 "Stan obecny"
log "Plik konfiguracji: $MODCONF"
sed 's/^/  /' "$MODCONF"

CUR=$(current_apache_php)
if [ "$CUR" = "72" ]; then
  ok "Apache już używa PHP 7.2 – nie ma czego cofać"
  exit 0
fi

head1 "Przywracanie PHP 7.2"
if [ -f "$BK" ]; then
  log "Źródło: kopia zapasowa $BK"
  confirm "Przywrócić PHP 7.2 i zrestartować Apache?"
  cp -a "$BK" "$MODCONF"
else
  warn "Brak kopii $BK – podmieniam ścieżkę modułu z powrotem"
  [ -f "$MOD_DIR/libphp7.so" ] || die "Brak $MOD_DIR/libphp7.so – nie ma do czego wrócić"
  confirm "Przywrócić PHP 7.2 i zrestartować Apache?"
  sed -i "s|modules/$MOD_NAME|modules/libphp7.so|" "$MODCONF"
fi
sed 's/^/  /' "$MODCONF"

head1 "Test składni"
httpd -t || die "httpd -t zgłosił błąd – popraw $MODCONF ręcznie przed restartem"
ok "Syntax OK"

head1 "Restart Apache"
systemctl restart httpd || die "Restart nieudany – sprawdź: journalctl -xe -u httpd"
sleep 2
systemctl is-active --quiet httpd || die "Apache nie działa – sprawdź /var/log/httpd/error_log"
ok "Apache uruchomiony"

head1 "Sprawdzenie"
VER=$(php_probe '<?php echo PHP_VERSION,"|",PHP_SAPI;')
log "Odpowiedź serwera: ${VER:-(brak)}"
case "$VER" in
  7.2*) ok "Przywrócono PHP $VER" ;;
  "")   err "Brak odpowiedzi z $TEST_URL"; tail -15 /var/log/httpd/error_log; exit 1 ;;
  *)    warn "Nieoczekiwana odpowiedź: $VER" ;;
esac

head1 "Opcjonalne sprzątanie"
log "PHP 7.4 pozostaje zainstalowane i gotowe do ponownego włączenia (./40-wlacz-php74.sh)."
log "Jeśli chcesz je usunąć całkowicie:"
log "  rm -rf $PHP_PREFIX $MOD_DIR/$MOD_NAME /usr/local/bin/php"
if [ -L /usr/local/bin/php ]; then
  warn "Istnieje dowiązanie /usr/local/bin/php -> $(readlink -f /usr/local/bin/php)"
  log  "Jeśli wskazuje na PHP 7.4, usuń je: rm -f /usr/local/bin/php"
fi

