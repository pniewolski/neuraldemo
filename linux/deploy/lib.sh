#!/bin/bash
# Wspólne funkcje dla skryptów wdrożenia. Nie uruchamiaj bezpośrednio.

set -euo pipefail

_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "$_DIR/config.sh"

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
  log "Log: $LOGFILE"
}

# Ścieżka pliku z dyrektywą LoadModule php7_module (remi: 15-php.conf, base: 10-php.conf)
find_php_module_conf() {
  local f
  f=$(grep -rls 'LoadModule[[:space:]]\+php7_module' /etc/httpd/conf.modules.d/ 2>/dev/null | head -1)
  [ -n "$f" ] || return 1
  printf '%s\n' "$f"
}

# Która wersja PHP jest wpisana w konfiguracji Apache: "72", "74" albo "?"
current_apache_php() {
  local f
  f=$(find_php_module_conf) || { echo "?"; return; }
  if grep -q "$MOD_NAME" "$f"; then echo "74"
  elif grep -q 'libphp7\.so' "$f"; then echo "72"
  else echo "?"; fi
}

# Wykonuje żądanie HTTP do tymczasowego skryptu PHP i sprząta po sobie
php_probe() {
  local code="$1" name="_probe_$$_${RANDOM}.php"
  printf '%s' "$code" > "$DOCROOT/$name"
  local out
  out=$(curl -sg --max-time 10 "$TEST_URL/$name" 2>/dev/null || true)
  rm -f "$DOCROOT/$name"
  printf '%s' "$out"
}

