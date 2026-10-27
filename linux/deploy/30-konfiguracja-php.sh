#!/bin/bash
# 30-konfiguracja-php.sh – kroki 6–7: php.ini dla PHP 7.4 + sprawdzenie SELinuksa.
# Uruchom na OBU serwerach. Nie przełącza Apache.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_root
start_log "30-konfiguracja-php"

[ -x "$PHP_PREFIX/bin/php" ] || die "Brak $PHP_PREFIX/bin/php – najpierw uruchom 10-build-test.sh lub 20-install-prod.sh"

head1 "Źródłowy php.ini z PHP 7.2"
SRC_INI=$(php --ini 2>/dev/null | sed -n 's/^Loaded Configuration File: *//p')
[ -n "$SRC_INI" ] && [ -f "$SRC_INI" ] || SRC_INI=/etc/php.ini
[ -f "$SRC_INI" ] || die "Nie znaleziono php.ini dla PHP 7.2 (sprawdź 'php --ini')"
ok "Używam jako wzorca: $SRC_INI"

DST_INI="$PHP_PREFIX/etc/php.ini"
mkdir -p "$PHP_PREFIX/etc/conf.d"

if [ -f "$DST_INI" ] && [ "${FORCE:-0}" != "1" ]; then
  warn "$DST_INI już istnieje – zostawiam bez zmian"
  log  "Aby nadpisać wzorcem z 7.2, uruchom: FORCE=1 $0"
else
  [ -f "$DST_INI" ] && cp -a "$DST_INI" "$WORKDIR/php.ini.7.4.bak-$(date +%H%M%S)"
  cp "$SRC_INI" "$DST_INI"
  # Rozszerzenia są wkompilowane, a pliki .so zbudowane dla 7.2 nie dadzą się wczytać w 7.4
  sed -i 's/^\s*extension\s*=/;&/; s/^\s*zend_extension\s*=/;&/' "$DST_INI"
  ok "Utworzono $DST_INI (wpisy extension/zend_extension zakomentowane)"
fi

head1 "Opcache"
if ls "$PHP_PREFIX/etc/conf.d/"*.ini >/dev/null 2>&1; then
  log "Pliki w conf.d:"; ls -1 "$PHP_PREFIX/etc/conf.d/"
else
  ok "conf.d pusty – opcache wyłączony, tak jak w PHP 7.2 na tym serwerze"
fi

head1 "Kontrola php.ini"
OUT=$("$PHP_PREFIX/bin/php" -c "$DST_INI" -r 'echo "PHP_OK";' 2>&1)
printf '%s\n' "$OUT" | grep -q PHP_OK || { err "PHP nie startuje z tym php.ini:"; printf '%s\n' "$OUT"; exit 1; }
WARNS=$(printf '%s' "$OUT" | grep -i 'unable to load\|warning' || true)
if [ -n "$WARNS" ]; then err "Ostrzeżenia przy starcie:"; printf '%s\n' "$WARNS"; exit 1; fi
ok "php.ini poprawny, bez ostrzeżeń"

head1 "Ustawienia warte sprawdzenia"
for k in memory_limit max_execution_time upload_max_filesize post_max_size max_input_vars \
         date.timezone error_log session.save_path max_multipart_body_parts; do
  printf '  %-28s = %s\n' "$k" "$("$PHP_PREFIX/bin/php" -c "$DST_INI" -r "echo ini_get('$k') === false ? '(brak)' : (ini_get('$k') === '' ? '(puste)' : ini_get('$k'));")"
done
log ""
log "  max_multipart_body_parts pochodzi z łatki. '-1' = max_input_vars + max_file_uploads (zalecane)."
log "  session.upload_progress jest wyłączony przez łatkę niezależnie od ustawień."
log "  session.save_path pusty oznacza, że ścieżkę narzuca Apache (php_value w php.conf) – to w porządku."

head1 "SELinux"
if command -v getenforce >/dev/null 2>&1; then
  log "Tryb: $(getenforce)"
  restorecon -Rv "$MOD_DIR/$MOD_NAME" "$PHP_PREFIX" 2>/dev/null || true
  if [ -f "$MOD_DIR/$MOD_NAME" ]; then
    ls -Z "$MOD_DIR/$MOD_NAME" | grep -q httpd_modules_t \
      && ok "Etykieta modułu: httpd_modules_t" \
      || warn "Etykieta modułu inna niż httpd_modules_t"
  fi
else
  log "SELinux niedostępny w tym systemie"
fi

head1 "Gotowe"
log "Dalej: ./40-wlacz-php74.sh   (podmiana modułu w Apache + restart)"

