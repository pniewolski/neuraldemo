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
MPM=$(httpd -V 2>/dev/null | sed -n 's/.*Server MPM: *//p')
if [ "$MPM" = "prefork" ]; then ok "MPM: prefork"
else warn "MPM: ${MPM:-nieznany} – mod_php wymaga prefork. Przerwij i skonsultuj zmianę MPM."; fi

if httpd -M 2>/dev/null | grep -q 'php7_module'; then ok "Apache używa mod_php (php7_module)"
else warn "Apache NIE ma php7_module – ta instrukcja zakłada mod_php. Sprawdź, jak serwowane jest PHP."; fi

if MODCONF=$(find_php_module_conf); then
  ok "LoadModule w pliku: $MODCONF"
  cp -a "$MODCONF" "$WORKDIR/$(basename "$MODCONF").php72"
  ok "Kopia tego pliku: $WORKDIR/$(basename "$MODCONF").php72"
  sed -n 's/^[[:space:]]*/  /p' "$MODCONF" | grep -i loadmodule || true
else
  warn "Nie znaleziono LoadModule php7_module w /etc/httpd/conf.modules.d/"
fi

if [ -f "$MOD_DIR/libphp7.so" ]; then ok "Moduł PHP 7.2: $MOD_DIR/libphp7.so"
else warn "Brak $MOD_DIR/libphp7.so – sprawdź, skąd ładowany jest moduł PHP."; fi

head1 "Rozszerzenia widziane przez Apache"
EXT=$(php_probe '<?php echo implode("\n", get_loaded_extensions()),"\n";')
if [ -n "$EXT" ]; then
  printf '%s' "$EXT" | sort -f > "$WORKDIR/php72-modules-apache.txt"
  ok "Zapisano: $WORKDIR/php72-modules-apache.txt ($(wc -l < "$WORKDIR/php72-modules-apache.txt") rozszerzeń)"
  head1 "Różnice CLI vs Apache (oczekiwane: apache2handler, pcntl, readline)"
  diff -i <(php -m 2>/dev/null | grep -v '^\[' | grep -v '^$' | sort -f) \
          "$WORKDIR/php72-modules-apache.txt" || true
else
  warn "Brak odpowiedzi z $TEST_URL – ustaw TEST_URL w config.sh na działający adres vhosta."
  warn "Bez tej listy nie da się potwierdzić, że 7.4 ma te same rozszerzenia co 7.2 w Apache."
fi

head1 "Gotowe"
log "Dalej:"
log "  - serwer testowy:     ./02-repozytoria.sh, potem ./10-build-test.sh"
log "  - serwer produkcyjny: ./02-repozytoria.sh, potem ./20-install-prod.sh"
warn "Zrób snapshot maszyny, jeśli jeszcze go nie masz."

