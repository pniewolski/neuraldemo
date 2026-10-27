#!/bin/bash
# 20-install-prod.sh – [SERWER PRODUKCYJNY] krok 5P: instalacja gotowej paczki z serwera testowego.
# Nie instaluje kompilatorów. Nie przełącza Apache.
#
# Wymaga wcześniejszego skopiowania na serwer:
#   /root/php-7.4-patched-centos7.tgz  oraz  .sha256

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_root
start_log "20-install-prod"
require_centos7

head1 "Sprawdzenie paczki"
[ -f "$PKG" ]        || die "Brak paczki $PKG – skopiuj ją z serwera testowego (scp)."
[ -f "$PKG.sha256" ] || die "Brak $PKG.sha256 – skopiuj także sumę kontrolną."
cd "$(dirname "$PKG")"
sha256sum -c "$PKG.sha256" || die "Suma kontrolna się nie zgadza – paczka uszkodzona przy kopiowaniu."
ok "Suma kontrolna poprawna"

head1 "Zawartość paczki"
tar tzf "$PKG" | grep -E "$MOD_NAME|bin/php$" || warn "W paczce nie widać modułu ani binarki php"

head1 "Stan wyjściowy serwera"
[ -f "$MOD_DIR/libphp7.so" ] || warn "Brak $MOD_DIR/libphp7.so – ta instrukcja zakłada mod_php 7.2"
php -v 2>/dev/null | head -1 || true
MD5_BEFORE=$(md5sum "$MOD_DIR/libphp7.so" 2>/dev/null | cut -d' ' -f1 || echo "-")

if [ -d "$PHP_PREFIX" ]; then
  warn "$PHP_PREFIX już istnieje – zostanie nadpisany zawartością paczki"
  confirm "Kontynuować?"
fi

head1 "Rozpakowanie"
tar xzf "$PKG" -C /
ok "Rozpakowano do $PHP_PREFIX oraz $MOD_DIR/$MOD_NAME"

MD5_AFTER=$(md5sum "$MOD_DIR/libphp7.so" 2>/dev/null | cut -d' ' -f1 || echo "-")
[ "$MD5_BEFORE" = "$MD5_AFTER" ] || die "Moduł PHP 7.2 został zmieniony przez paczkę! Przerwij i sprawdź zawartość paczki."
ok "Moduł PHP 7.2 nietknięty"

head1 "SELinux"
restorecon -Rv "$MOD_DIR/$MOD_NAME" "$PHP_PREFIX" 2>/dev/null || true
if command -v getenforce >/dev/null 2>&1; then
  log "Tryb: $(getenforce)"
  ls -Z "$MOD_DIR/$MOD_NAME" 2>/dev/null | grep -q httpd_modules_t \
    && ok "Etykieta modułu: httpd_modules_t" \
    || warn "Etykieta modułu inna niż httpd_modules_t – uruchom: restorecon -v $MOD_DIR/$MOD_NAME"
fi

head1 "Biblioteki uruchomieniowe"
confirm "Zainstalować/uzupełnić: ${RUNTIME_PKGS[*]} ?"
yum -y install "${RUNTIME_PKGS[@]}"

MISSING=$(ldd "$MOD_DIR/$MOD_NAME" "$PHP_PREFIX/bin/php" | grep 'not found' || true)
if [ -z "$MISSING" ]; then
  ok "Wszystkie biblioteki dostępne"
else
  err "Brakujące biblioteki – PHP nie wystartuje:"
  printf '%s\n' "$MISSING"
  exit 1
fi

head1 "Weryfikacja binarki"
"$PHP_PREFIX/bin/php" -v | head -1
ok "PHP 7.4 zainstalowane"

head1 "Gotowe"
log "Dalej:"
log "  ./30-konfiguracja-php.sh     # php.ini dla 7.4"
log "  ./40-wlacz-php74.sh          # podmiana modułu w Apache + restart (okno serwisowe)"
log "  ./50-weryfikacja.sh          # sprawdzenie"

