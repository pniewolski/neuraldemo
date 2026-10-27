#!/bin/bash
# 01-inwentaryzacja.sh – krok 0: spis stanu serwera + kopia zapasowa konfiguracji.
# Uruchom na OBU serwerach (testowym i produkcyjnym) PRZED jakimikolwiek zmianami.
# Nic nie modyfikuje poza katalogiem $WORKDIR.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_root
start_log "01-inwentaryzacja"
require_centos7

head1 "Kopia zapasowa konfiguracji"
BK="$WORKDIR/backup-etc-$(date +%F-%H%M%S).tgz"
tar czf "$BK" /etc/httpd /etc/php.ini /etc/php.d 2>/dev/null || true
ok "Zapisano: $BK"

head1 "Spis obecnego PHP i Apache"
php -v                        > "$WORKDIR/php72-version.txt" 2>&1 || warn "Brak polecenia php w PATH"
php -m                        > "$WORKDIR/php72-modules.txt" 2>&1 || true
php --ini                     > "$WORKDIR/php72-ini.txt"     2>&1 || true
rpm -qa | grep -i php | sort  > "$WORKDIR/php72-rpms.txt"           || true
httpd -V                      > "$WORKDIR/httpd-V.txt"       2>&1  || true
httpd -M                      > "$WORKDIR/httpd-modules.txt" 2>&1  || true
ok "Pliki zapisane w $WORKDIR"

head1 "Warunki wymagane przez instrukcję"
MPM=$(httpd -V 2>/dev/null | sed -n 's/.*Server MPM: *//p' || true)
if [ "$MPM" = "prefork" ]; then ok "MPM: prefork"
else warn "MPM: ${MPM:-nieznany} – mod_php wymaga prefork. Przerwij i skonsultuj zmianę MPM."; fi

if httpd -M 2>/dev/null | grep -q 'php7_module'; then ok "Apache używa mod_php (php7_module)"
else warn "Apache NIE ma php7_module – ta instrukcja zakłada mod_php. Sprawdź, jak serwowane jest PHP."; fi

if MODCONF=$(find_php_module_conf); then
  ok "LoadModule w pliku: $MODCONF"
  cp -a "$MODCONF" "$WORKDIR/$(basename "$MODCONF").php72"
  ok "Kopia tego pliku: $WORKDIR/$(basename "$MODCONF").php72"
  grep -i loadmodule "$MODCONF" | sed 's/^[[:space:]]*/  /' || true
  # remi wpisuje dwie dyrektywy: libphp7.so dla prefork i libphp7-zts.so dla MPM wielowątkowych
  if grep -q 'libphp7-zts\.so' "$MODCONF"; then
    log ""
    log "  Plik zawiera dwa warianty modułu (to normalne dla pakietów remi):"
    log "    libphp7.so      – używany przy MPM prefork  <- ten podmienimy"
    log "    libphp7-zts.so  – używany przy MPM worker/event (pozostanie bez zmian)"
  fi
else
  warn "Nie znaleziono LoadModule php7_module w /etc/httpd/conf.modules.d/"
fi

if [ -f "$MOD_DIR/libphp7.so" ]; then ok "Moduł PHP 7.2: $MOD_DIR/libphp7.so"
else warn "Brak $MOD_DIR/libphp7.so – sprawdź, skąd ładowany jest moduł PHP."; fi

head1 "Rozszerzenia widziane przez Apache"
if auto_docroot; then
  ok "Apache wykonuje PHP: $TEST_URL -> $DOCROOT"
  EXT=$(php_probe '<?php echo implode("\n", get_loaded_extensions()),"\n";')
  printf '%s' "$EXT" | sort -f > "$WORKDIR/php72-modules-apache.txt"
  ok "Zapisano: $WORKDIR/php72-modules-apache.txt ($(wc -l < "$WORKDIR/php72-modules-apache.txt") rozszerzeń)"
  if command -v php >/dev/null 2>&1; then
    head1 "Różnice CLI vs Apache (oczekiwane: apache2handler, pcntl, readline)"
    diff -i <(php -m 2>/dev/null | grep -v '^\[' | grep -v '^$' | sort -f) \
            "$WORKDIR/php72-modules-apache.txt" || true
  else
    warn "Brak polecenia php w PATH – pomijam porównanie CLI vs Apache"
  fi
else
  rm -f "$WORKDIR/php72-modules-apache.txt"
  head1 "Nie udało się wykonać testowego skryptu PHP przez Apache"
  diagnoza_probe
  warn "Bez tej listy nie potwierdzimy, że PHP 7.4 ma te same rozszerzenia co 7.2."
  warn "Popraw config.sh i uruchom ten krok ponownie."
fi

head1 "Gotowe"
log "Dalej:"
log "  - serwer testowy:     ./02-repozytoria.sh, potem ./10-build-test.sh"
log "  - serwer produkcyjny: ./02-repozytoria.sh, potem ./20-install-prod.sh"
warn "Zrób snapshot maszyny, jeśli jeszcze go nie masz."



