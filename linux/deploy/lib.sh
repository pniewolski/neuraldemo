#!/bin/bash
# Wspólne funkcje dla skryptów wdrożenia. Nie uruchamiaj bezpośrednio.

set -Eeuo pipefail

_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "$_DIR/config.sh"

# DocumentRoot wykryty wcześniej przez auto_docroot ma pierwszeństwo przed wartością z config.sh
[ -s "$WORKDIR/docroot" ] && DOCROOT="$(cat "$WORKDIR/docroot")"

# --- kolory (wyłączone, gdy wyjście nie jest terminalem) ---
if [ -t 1 ]; then
  C_OK=$'\033[32m'; C_ERR=$'\033[31m'; C_WARN=$'\033[33m'; C_HEAD=$'\033[1;36m'; C_N=$'\033[0m'
else
  C_OK=""; C_ERR=""; C_WARN=""; C_HEAD=""; C_N=""
fi

log()   { printf '%s\n' "$*"; }
head1() { printf '\n%s== %s%s\n' "$C_HEAD" "$*" "$C_N"; }
ok()    { printf '%s[ OK ]%s %s\n' "$C_OK" "$C_N" "$*"; }
warn()  { printf '%s[UWAGA]%s %s\n' "$C_WARN" "$C_N" "$*"; }
err()   { printf '%s[BŁĄD]%s %s\n' "$C_ERR" "$C_N" "$*" >&2; }
die()   { err "$*"; exit 1; }

require_root() {
  [ "$(id -u)" -eq 0 ] || die "Uruchom jako root (sudo)."
}

require_centos7() {
  grep -q 'CentOS Linux 7' /etc/os-release 2>/dev/null \
    || warn "To nie wygląda na CentOS 7 – sprawdź, czy skrypt pasuje do tego systemu."
}

# Potwierdzenie przed operacją zmieniającą stan. Pomijane przy ASSUME_YES=1.
confirm() {
  local msg="$1"
  if [ "${ASSUME_YES:-0}" = "1" ]; then
    log "$msg -> tak (ASSUME_YES=1)"
    return 0
  fi
  local ans
  read -r -p "$msg [t/N] " ans
  case "$ans" in [tTyY]*) return 0 ;; *) die "Przerwano na życzenie użytkownika." ;; esac
}

# Zapis całej sesji do pliku logu w $WORKDIR
start_log() {
  mkdir -p "$WORKDIR"
  local name="$1"
  LOGFILE="$WORKDIR/${name}-$(date +%Y%m%d-%H%M%S).log"
  exec > >(tee -a "$LOGFILE") 2>&1
  _TEE_PID=$!
  # bez tego ostatnie linie (np. komunikat o błędzie) mogą nie zdążyć trafić na ekran
  trap '_flush_log' EXIT
  # żeby skrypt nigdy nie kończył się po cichu – zawsze wiadomo, która linia zawiodła
  trap '_on_err $? $LINENO' ERR
  log "Log: $LOGFILE"
}

_on_err() {
  local rc="$1" line="$2"
  err "Przerwano: polecenie w linii $line zakończyło się kodem $rc"
  err "Szczegóły w logu: ${LOGFILE:-brak}"
}

_flush_log() {
  local rc=$?
  # Pułapkę ERR trzeba zdjąć, a "wait" pominąć: w pułapce EXIT ich niezerowy wynik
  # nadpisywałby kod wyjścia skryptu (skrypt kończył się jedynką mimo powodzenia).
  # Zamknięcie deskryptorów wymusza opróżnienie bufora tee, więc nic nie ginie.
  trap - ERR
  exec 1>&- 2>&-
  return $rc
}

# PEŁNY restart Apache (stop + start).# Nie wolno używać reload/graceful/"httpd -k restart" – przy podmianie mod_php powodują segfaulty,
# bo Apache odłącza i ładuje moduł ponownie w istniejącym procesie.
restart_httpd() {
  if command -v systemctl >/dev/null 2>&1 && systemctl list-units --type=service >/dev/null 2>&1; then
    systemctl restart httpd
  else
    warn "systemd niedostępny – używam apachectl (stop + start)"
    apachectl stop >/dev/null 2>&1 || true
    sleep 2
    apachectl start
  fi
}

httpd_is_running() {
  if command -v systemctl >/dev/null 2>&1 && systemctl list-units --type=service >/dev/null 2>&1; then
    systemctl is-active --quiet httpd
  else
    pgrep -x httpd >/dev/null 2>&1
  fi
}

# Czy w tym środowisku da się w ogóle uruchomić wbudowany serwer HTTP PHP?
# Część testów z pakietu PHP (np. tests/basic/bug67198.phpt) tego wymaga.
# Zwraca 0, gdy serwer wystartował i odpowiedział.
#   $1 – ścieżka do binarki php
#   $2 – port (domyślnie 8964, tak jak w testach PHP)
test_wbudowanego_serwera() {
  local BIN="$1" PORT="${2:-8964}" DIR OUT="" PID I
  [ -x "$BIN" ] || return 2
  DIR=$(mktemp -d)
  printf '<?php echo "SRV_OK";' > "$DIR/i.php"
  # -n = bez php.ini, żeby konfiguracja nie wpływała na wynik
  "$BIN" -n -S "127.0.0.1:$PORT" -t "$DIR" >/dev/null 2>&1 &
  PID=$!
  for I in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    sleep 0.4
    kill -0 "$PID" 2>/dev/null || break      # proces padł
    OUT=$(curl -s --max-time 2 "http://127.0.0.1:$PORT/i.php" 2>/dev/null || true)
    [ -n "$OUT" ] && break
  done
  kill "$PID" 2>/dev/null || true
  wait "$PID" 2>/dev/null || true
  rm -rf "$DIR"
  case "$OUT" in *SRV_OK*) return 0 ;; *) return 1 ;; esac
}

# Ścieżka pliku z dyrektywą LoadModule php7_module (remi: 15-php.conf, base: 10-php.conf)
find_php_module_conf() {
  local f
  f=$(grep -rls 'LoadModule[[:space:]]\+php7_module' /etc/httpd/conf.modules.d/ 2>/dev/null | head -1 || true)
  [ -n "$f" ] || return 1
  printf '%s\n' "$f"
}

# Która wersja PHP jest wpisana w konfiguracji Apache: "72", "74" albo "?"
# Uwaga: plik remi zawiera dwie dyrektywy LoadModule – dla prefork (libphp7.so)
# i dla MPM wielowątkowych (libphp7-zts.so). Podmieniamy wyłącznie wariant prefork.
current_apache_php() {
  local f
  f=$(find_php_module_conf) || { echo "?"; return; }
  if grep -q "modules/$MOD_NAME" "$f"; then echo "74"
  elif grep -q 'modules/libphp7\.so' "$f"; then echo "72"
  else echo "?"; fi
}

# Kandydaci na DocumentRoot z konfiguracji Apache.
# "|| true" jest konieczne: grep zwraca 2, gdy któraś ze ścieżek w masce nie istnieje.
kandydaci_docroot() {
  { grep -rhE '^[[:space:]]*DocumentRoot[[:space:]]' \
         /etc/httpd/conf/httpd.conf /etc/httpd/conf.d/ /etc/httpd/conf.modules.d/ 2>/dev/null \
      || true; } | awk '{print $2}' | tr -d '"' | sort -u
}

# Podpowiedź, co ustawić w config.sh, gdy test HTTP nie działa
diagnoza_probe() {
  err "${PROBE_ERR:-Nie udało się wykonać testowego żądania HTTP}"
  log ""
  log "Obecne ustawienia z config.sh:"
  log "  TEST_URL = $TEST_URL"
  log "  DOCROOT  = $DOCROOT"
  log ""
  log "DocumentRoot znalezione w konfiguracji Apache:"
  kandydaci_docroot | sed 's/^/  /' || true
  log ""
  log "Hosty wirtualne (httpd -S):"
  httpd -S 2>&1 | grep -E 'port|namevhost' | head -10 | sed 's/^/  /' || true
  log ""
  log "Popraw TEST_URL i/lub DOCROOT w config.sh tak, aby wskazywały ten sam katalog."
}

# Szuka DocumentRoot, pod którym Apache faktycznie wykonuje PHP.
# Zwraca 0 i ustawia DOCROOT, jeśli znajdzie działającą kombinację.
auto_docroot() {
  local d pierwotny="$DOCROOT"
  if php_probe '<?php echo "PROBE_OK";' | grep -q PROBE_OK; then
    echo "$DOCROOT" > "$WORKDIR/docroot" 2>/dev/null || true
    return 0
  fi
  for d in $(kandydaci_docroot); do
    [ -d "$d" ] || continue
    [ "$d" = "$pierwotny" ] && continue
    DOCROOT="$d"
    if php_probe '<?php echo "PROBE_OK";' | grep -q PROBE_OK; then
      warn "DOCROOT '$pierwotny' nie działał – wykryto działający: $DOCROOT"
      warn "Zapamiętano w $WORKDIR/docroot (możesz wpisać go na stałe w config.sh)."
      echo "$DOCROOT" > "$WORKDIR/docroot" 2>/dev/null || true
      return 0
    fi
  done
  DOCROOT="$pierwotny"
  return 1
}

# Wykonuje żądanie HTTP do tymczasowego skryptu PHP i sprząta po sobie.
# Zwraca treść odpowiedzi tylko wtedy, gdy serwer naprawdę wykonał PHP (HTTP 200, nie strona błędu).
# Niepowodzenie jest tu normalną sytuacją (np. szukanie właściwego DOCROOT),
# dlatego na czas działania wyłączamy pułapkę ERR – inaczej zgłaszałaby fałszywe błędy.
php_probe() {
  local code="$1" name="_probe_$$_${RANDOM}.php" rc=0
  local had_E=0; case "$-" in *E*) had_E=1 ;; esac
  set +E
  PROBE_ERR=""

  local raw http body out=""
  if [ ! -d "$DOCROOT" ]; then
    PROBE_ERR="Katalog DOCROOT nie istnieje: $DOCROOT"; rc=1
  elif ! printf '%s' "$code" > "$DOCROOT/$name" 2>/dev/null; then
    PROBE_ERR="Brak prawa zapisu w $DOCROOT"; rc=1
  else
    raw=$(curl -sg --max-time 10 -w '__HTTP__%{http_code}' "$TEST_URL/$name" 2>/dev/null)
    rm -f "$DOCROOT/$name"
    http="${raw##*__HTTP__}"
    body="${raw%__HTTP__*}"
    if [ -z "$raw" ]; then
      PROBE_ERR="Brak odpowiedzi z $TEST_URL (serwer nie odpowiada albo adres jest błędny)"; rc=1
    elif [ "$http" != "200" ]; then
      PROBE_ERR="Serwer zwrócił HTTP $http. Adres $TEST_URL nie prowadzi do katalogu $DOCROOT."; rc=1
    else
      case "$body" in
        *'<!DOCTYPE'*|*'<html'*|*'<HTML'*)
          PROBE_ERR="Serwer zwrócił stronę HTML zamiast wyniku skryptu PHP (pliki .php nie są wykonywane)."
          rc=1 ;;
        *) out="$body" ;;
      esac
    fi
  fi

  [ "$had_E" = 1 ] && set -E
  [ $rc -eq 0 ] && printf '%s' "$out"
  return $rc
}







