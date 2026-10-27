#!/bin/bash
# Czy serwer jest podatny na CVE-2026-109618 / CVE-2026-109619?
# Sprawdza, jakim modulem PHP Apache obsluguje zadania i czy ten modul zawiera latke.
# Nic nie zmienia. Dziala takze wtedy, gdy nie da sie wykonac zadania HTTP.
#
# Kod wyjscia: 0 = zalatany, 1 = podatny, 2 = nie ustalono

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_root
start_log "60-czy-podatny"

# Dyrektywa php.ini "max_multipart_body_parts" wystepuje wylacznie w wersji z latka.
# UWAGA: swiadomie bez potoku "strings | grep -q". Przy wlaczonym pipefail grep -q
# konczy potok wczesniej, strings dostaje SIGPIPE, caly potok zwraca blad -
# i zalatany modul zostalby zgloszony jako podatny.
ma_latke() { grep -qa 'max_multipart_body_parts' "$1" 2>/dev/null; }

WERDYKT=""

head1 "1. Modul PHP uzywany przez dzialajacy Apache"
PID=$(pgrep -o -x httpd 2>/dev/null || true)
MOD_RUNTIME=""
if [ -n "$PID" ] && [ -r "/proc/$PID/maps" ]; then
  MOD_RUNTIME=$(sed -n 's|.*\(/[^ ]*libphp[^ ]*\.so\).*|\1|p' "/proc/$PID/maps" 2>/dev/null | sort -u | head -1)
fi
if [ -n "$MOD_RUNTIME" ] && [ -f "$MOD_RUNTIME" ]; then
  ok "Proces httpd (pid $PID) ma zaladowany: $MOD_RUNTIME"
elif [ -n "$MOD_RUNTIME" ]; then
  warn "Proces httpd uzywa $MOD_RUNTIME, ale plik zostal podmieniony po starcie."
  warn "Apache pracuje na POPRZEDNIEJ wersji do czasu restartu."
  MOD_RUNTIME=""
else
  warn "Nie udalo sie odczytac modulu z dzialajacego procesu httpd."
fi

WERSJA_LOG=$(grep -o 'PHP/[0-9][^ ]*' /var/log/httpd/error_log 2>/dev/null | tail -1 || true)
[ -n "$WERSJA_LOG" ] && ok "Ostatni start Apache zglosil wersje: $WERSJA_LOG"

MODCONF=$(find_php_module_conf 2>/dev/null || true)
MOD_CONFIG=""
if [ -n "$MODCONF" ]; then
  log "Konfiguracja ($MODCONF):"
  grep -i loadmodule "$MODCONF" | sed 's/^[[:space:]]*/  /'
  # wariant bez "-zts" to ten uzywany przy MPM prefork
  NAZWA=$(grep -i loadmodule "$MODCONF" | grep -v 'zts' \
          | sed -n 's|.*modules/\([^ ]*\.so\).*|\1|p' | head -1 || true)
  [ -n "$NAZWA" ] && MOD_CONFIG="$MOD_DIR/$NAZWA" && log "Wariant dla prefork: $MOD_CONFIG"
fi

head1 "2. Czy modul wskazany w konfiguracji zawiera latke"
# To mowi o stanie PO NAJBLIZSZYM RESTARCIE Apache
SPRAWDZANY="${MOD_RUNTIME:-$MOD_CONFIG}"
STAN_PLIK=""
if [ -n "$SPRAWDZANY" ] && [ -f "$SPRAWDZANY" ]; then
  if ma_latke "$SPRAWDZANY"; then
    ok "$SPRAWDZANY ZAWIERA latke"
    STAN_PLIK="zalatany"
  else
    err "$SPRAWDZANY NIE zawiera latki"
    STAN_PLIK="podatny"
  fi
else
  warn "Brak pliku modulu do sprawdzenia"
fi

head1 "3. Wszystkie moduly PHP na dysku"
for M in "$MOD_DIR"/libphp*.so; do
  [ -f "$M" ] || continue
  if ma_latke "$M"; then
    printf '  %-52s %s\n' "$(basename "$M")" "z latka"
  else
    printf '  %-52s %s\n' "$(basename "$M")" "BEZ latki"
  fi
done

head1 "4. Potwierdzenie zadaniem HTTP"
# To mowi o stanie BIEZACYM - jak serwer obsluguje zadania w tej chwili
STAN_HTTP=""
if auto_docroot 2>/dev/null; then
  WER=$(php_probe '<?php echo PHP_VERSION;' || true)
  MP=$(php_probe '<?php $v=ini_get("max_multipart_body_parts"); echo $v===false?"BRAK":$v;' || true)
  log "  PHP obslugujace zadania  : ${WER:-?}"
  log "  max_multipart_body_parts : ${MP:-?}"
  case "$MP" in
    BRAK|"") err "  Serwer odpowiada BEZ latki"; STAN_HTTP="podatny" ;;
    *)       ok  "  Serwer odpowiada Z latka";   STAN_HTTP="zalatany" ;;
  esac
else
  warn "Test HTTP niedostepny: ${PROBE_ERR:-brak polaczenia}"
  log "  Werdykt opiera sie na analizie pliku modulu (sekcja 2)."
  log "  Diagnoza polaczenia: ./99-diagnoza-http.sh"
fi

head1 "5. PHP w linii polecen (cron, skrypty)"
CLI=$(php -v 2>/dev/null | head -1 || true)
log "  php -v -> ${CLI:-brak polecenia php w PATH}"
if command -v php >/dev/null 2>&1; then
  if php -r 'exit(ini_get("max_multipart_body_parts")===false ? 1 : 0);' 2>/dev/null; then
    ok "  CLI ma latke"
  else
    warn "  CLI nie ma latki. Podatnosc dotyczy zadan HTTP, ale rozwaz przeniesienie crona."
  fi
fi

head1 "WERDYKT"
RC=2
if [ -n "$STAN_HTTP" ] && [ -n "$STAN_PLIK" ] && [ "$STAN_HTTP" != "$STAN_PLIK" ]; then
  # stan biezacy rozni sie od tego, co zaladuje sie po restarcie
  err "ROZBIEZNOSC miedzy stanem biezacym a konfiguracja!"
  log "  Teraz serwer obsluguje zadania: $STAN_HTTP"
  log "  Po restarcie Apache zaladuje  : $STAN_PLIK"
  if [ "$STAN_PLIK" = "podatny" ]; then
    err "Po najblizszym restarcie serwer stanie sie PODATNY."
    log "Sprawdz dyrektywe LoadModule w $MODCONF"
    RC=1
  else
    warn "Latka jest gotowa, ale Apache jej jeszcze nie zaladowal."
    log "Wykonaj pelny restart: systemctl restart httpd"
    RC=1
  fi
else
  WERDYKT="${STAN_HTTP:-$STAN_PLIK}"
  case "$WERDYKT" in
    zalatany)
      ok "Serwer obsluguje zadania modulem Z LATKA."
      log "CVE-2026-109618 / CVE-2026-109619: ZALATANE"
      RC=0 ;;
    podatny)
      err "Serwer uzywa modulu BEZ LATKI - jest PODATNY."
      log "Przelacz na PHP 7.4: ./menu.sh -> pozycja 5"
      RC=1 ;;
    *)
      warn "Nie udalo sie jednoznacznie ustalic stanu." ;;
  esac
fi
log ""
log "Sprawdzenie recznie, z dowolnego miejsca:"
log "  echo '<?php var_dump(ini_get(\"max_multipart_body_parts\"));' > $DOCROOT/t.php"
log "  curl -s http://ADRES/t.php     # string(2) \"-1\" = latka, bool(false) = brak latki"
log "  rm -f $DOCROOT/t.php"
exit $RC


