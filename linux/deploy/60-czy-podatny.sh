#!/bin/bash
# Czy serwer jest podatny na CVE-2026-109618 / CVE-2026-109619?
# Sprawdza wersje PHP uzywana przez Apache i obecnosc latki.
# Nic nie zmienia. Nie wymaga dzialajacego polaczenia HTTP.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_root
start_log "99-czy-podatny"

WERDYKT=""
head1 "1. Modul PHP zaladowany przez Apache"

# Biezacy proces httpd -> ktory plik .so ma otwarty
PID=$(pgrep -o -x httpd 2>/dev/null || true)
MOD_RUNTIME=""
if [ -n "$PID" ]; then
  MOD_RUNTIME=$(tr '\0' '\n' < "/proc/$PID/maps" 2>/dev/null | awk '/libphp/ {print $NF}' | sort -u | head -1)
  [ -z "$MOD_RUNTIME" ] && MOD_RUNTIME=$(grep -o '/[^ ]*libphp[^ ]*\.so' "/proc/$PID/maps" 2>/dev/null | sort -u | head -1)
fi
if [ -n "$MOD_RUNTIME" ]; then
  ok "Dziaĺający proces httpd (pid $PID) uzywa: $MOD_RUNTIME"
else
  warn "Nie udalo sie odczytac modulu z dzialajacego procesu httpd"
fi

# Wersja PHP zapisana w logu przy ostatnim starcie Apache
WERSJA_LOG=$(grep -o 'PHP/[0-9][^ ]*' /var/log/httpd/error_log 2>/dev/null | tail -1 || true)
[ -n "$WERSJA_LOG" ] && ok "Ostatni start Apache zglosil: $WERSJA_LOG"

# Konfiguracja
MODCONF=$(find_php_module_conf 2>/dev/null || true)
if [ -n "$MODCONF" ]; then
  log "Konfiguracja ($MODCONF):"
  grep -i loadmodule "$MODCONF" | sed 's/^[[:space:]]*/  /'
fi

head1 "2. Czy ten modul zawiera latke"
# Nowa dyrektywa php.ini "max_multipart_body_parts" wystepuje TYLKO w wersji z latka.
SPRAWDZANY="${MOD_RUNTIME:-$MOD_DIR/$MOD_NAME}"
if [ -f "$SPRAWDZANY" ]; then
  if strings -a "$SPRAWDZANY" 2>/dev/null | grep -q 'max_multipart_body_parts'; then
    ok "Modul $SPRAWDZANY ZAWIERA latke (znaleziono max_multipart_body_parts)"
    WERDYKT="zalatany"
  else
    err "Modul $SPRAWDZANY NIE zawiera latki"
    WERDYKT="podatny"
  fi
else
  warn "Nie znaleziono pliku modulu do sprawdzenia: $SPRAWDZANY"
fi

head1 "3. Porownanie obu modulow na dysku"
for M in "$MOD_DIR/libphp7.so" "$MOD_DIR/libphp7-zts.so" "$MOD_DIR/$MOD_NAME"; do
  [ -f "$M" ] || continue
  if strings -a "$M" 2>/dev/null | grep -q 'max_multipart_body_parts'; then
    printf '  %-55s %s\n' "$M" "z latka"
  else
    printf '  %-55s %s\n' "$M" "BEZ latki"
  fi
done

head1 "4. PHP w linii polecen (cron, skrypty)"
CLI=$(php -v 2>/dev/null | head -1 || true)
log "  php -v -> ${CLI:-brak polecenia php}"
if command -v php >/dev/null 2>&1; then
  if php -r 'exit(ini_get("max_multipart_body_parts")===false ? 1 : 0);' 2>/dev/null; then
    ok "  CLI ma latke"
  else
    warn "  CLI NIE ma latki (podatnosc dotyczy zadan HTTP, ale warto przeniesc cron)"
  fi
fi

head1 "WERDYKT"
case "$WERDYKT" in
  zalatany)
    ok "Apache obsluguje zadania modulem Z LATKA."
    log "Podatnosc CVE-2026-109618 / CVE-2026-109619 jest zalatana."
    ;;
  podatny)
    err "Apache uzywa modulu BEZ LATKI - serwer jest PODATNY."
    log "Wykonaj: ./menu.sh -> pozycja 5 (przelacz na PHP 7.4)"
    ;;
  *)
    warn "Nie udalo sie jednoznacznie ustalic stanu - sprawdz powyzsze sekcje."
    ;;
esac
log ""
log "Dodatkowo (gdy dziala polaczenie HTTP) mozna sprawdzic z zewnatrz:"
log "  curl -s http://ADRES/plik.php   na stronie z: <?php var_dump(ini_get('max_multipart_body_parts'));"
log "  wynik string(2) \"-1\" = latka obecna, bool(false) = brak latki"
exit 0

