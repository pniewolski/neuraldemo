#!/bin/bash
# menu.sh – jeden punkt wejścia do wdrożenia PHP 7.4 z łatką CVE-2026-109618 / CVE-2026-109619.
#
# Uruchom:  ./menu.sh
#
# Menu samo wykrywa stan serwera, pokazuje, co jest już zrobione,
# i podpowiada następny krok. Nic nie dzieje się bez Twojego wyboru.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib.sh"
set +e          # w menu nie przerywamy pracy po pierwszym niepowodzeniu
require_root

ROLE_FILE="$WORKDIR/rola"
mkdir -p "$WORKDIR"

# ----------------------------------------------------------------- rola serwera
wybierz_role() {
  clear
  printf '%s%s%s\n\n' "$C_HEAD" "Na jakim serwerze pracujesz?" "$C_N"
  printf '  1) TESTOWY     – tu kompilujemy PHP i przygotowujemy paczkę\n'
  printf '  2) PRODUKCYJNY – tu instalujemy gotową paczkę z serwera testowego\n\n'
  local a
  read -r -p "Wybór [1/2]: " a
  case "$a" in
    1) echo "test" > "$ROLE_FILE" ;;
    2) echo "prod" > "$ROLE_FILE" ;;
    *) return 1 ;;
  esac
}

[ -f "$ROLE_FILE" ] || { wybierz_role || exit 1; }
ROLE=$(cat "$ROLE_FILE" 2>/dev/null)
[ "$ROLE" = "test" ] || [ "$ROLE" = "prod" ] || { wybierz_role || exit 1; ROLE=$(cat "$ROLE_FILE"); }

# ----------------------------------------------------------------- stan serwera
zbadaj_stan() {
  ST_OS=$(sed -n 's/^PRETTY_NAME="\(.*\)"/\1/p' /etc/os-release 2>/dev/null)
  ST_MPM=$(httpd -V 2>/dev/null | sed -n 's/.*Server MPM: *//p')
  ST_MODCONF=$(find_php_module_conf 2>/dev/null)
  ST_APACHE_PHP=$(current_apache_php 2>/dev/null)
  ST_PHP72=$(php -v 2>/dev/null | head -1 | awk '{print $2}')
  ST_PHP74=$("$PHP_PREFIX/bin/php" -v 2>/dev/null | head -1 | awk '{print $2}')
  ST_MOD74="nie"; [ -f "$MOD_DIR/$MOD_NAME" ] && ST_MOD74="tak"
  ST_INI74="nie"; [ -f "$PHP_PREFIX/etc/php.ini" ] && ST_INI74="tak"
  ST_PKG="nie";   [ -f "$PKG" ] && ST_PKG="tak ($(du -h "$PKG" 2>/dev/null | cut -f1))"
  ST_INWENT="nie"; [ -f "$WORKDIR/php72-modules-apache.txt" ] && ST_INWENT="tak"
  ST_YUM="błąd";  yum -q repolist >/dev/null 2>&1 && ST_YUM="OK"
  ST_HTTPD="nie działa"; httpd_is_running 2>/dev/null && ST_HTTPD="działa"
  ST_SRC="nie"; [ -d "$SRCDIR/.git" ] && ST_SRC="tak"
}

# następny zalecany krok (numer pozycji menu)
nastepny_krok() {
  [ "$ST_INWENT" = "nie" ] && { echo 1; return; }
  [ "$ST_YUM" = "błąd" ]   && { echo 2; return; }
  if [ "$ROLE" = "test" ]; then
    [ -z "$ST_PHP74" ] && { echo 3; return; }
  else
    [ -z "$ST_PHP74" ] && { echo 3; return; }
  fi
  [ "$ST_INI74" = "nie" ] && { echo 4; return; }
  [ "$ST_APACHE_PHP" != "74" ] && { echo 5; return; }
  echo 6
}

m() {  # pozycja menu: numer, opis, stan
  local nr="$1" opis="$2" stan="$3"
  local wsk="  "
  [ "$nr" = "$NEXT" ] && wsk="${C_OK}->${C_N}"
  printf ' %s %s) %-48s %s\n' "$wsk" "$nr" "$opis" "$stan"
}

znacznik() { [ "$1" = "tak" ] && printf '%s[zrobione]%s' "$C_OK" "$C_N" || printf '%s[do zrobienia]%s' "$C_WARN" "$C_N"; }

# ----------------------------------------------------------------- ekran
ekran() {
  zbadaj_stan
  NEXT=$(nastepny_krok)
  clear
  printf '%s===========================================================================%s\n' "$C_HEAD" "$C_N"
  printf '%s  Wdrożenie PHP 7.4 z łatką CVE-2026-109618 / CVE-2026-109619%s\n' "$C_HEAD" "$C_N"
  printf '%s===========================================================================%s\n' "$C_HEAD" "$C_N"
  printf '  System      : %s\n' "${ST_OS:-?}"
  printf '  Rola        : %s\n' "$([ "$ROLE" = test ] && echo 'SERWER TESTOWY (kompilacja)' || echo 'SERWER PRODUKCYJNY (instalacja paczki)')"
  printf '  Apache      : %s, MPM %s\n' "$ST_HTTPD" "${ST_MPM:-?}"
  case "$ST_APACHE_PHP" in
    72) printf '  PHP w Apache: %sPHP 7.2 (podatne)%s\n' "$C_WARN" "$C_N" ;;
    74) printf '  PHP w Apache: %sPHP 7.4 z łatką%s\n' "$C_OK" "$C_N" ;;
    *)  printf '  PHP w Apache: %s?%s (sprawdź %s)\n' "$C_ERR" "$C_N" "${ST_MODCONF:-conf.modules.d}" ;;
  esac
  printf '  PHP 7.2 CLI : %s\n' "${ST_PHP72:-brak}"
  printf '  PHP 7.4     : %s   moduł Apache: %s   php.ini: %s\n' "${ST_PHP74:-niezainstalowane}" "$ST_MOD74" "$ST_INI74"
  [ "$ROLE" = "test" ] && printf '  Paczka      : %s\n' "$ST_PKG"
  printf '  Repozytoria : %s\n' "$ST_YUM"
  printf '%s---------------------------------------------------------------------------%s\n' "$C_HEAD" "$C_N"
  printf '  %sStrzałka -> wskazuje zalecany następny krok%s\n\n' "$C_OK" "$C_N"

  m 1 "Inwentaryzacja i kopia zapasowa (nic nie zmienia)" "$(znacznik "$ST_INWENT")"
  m 2 "Naprawa repozytoriów yum (vault)"                  "$([ "$ST_YUM" = OK ] && znacznik tak || znacznik nie)"
  if [ "$ROLE" = "test" ]; then
    m 3 "Kompilacja PHP 7.4 + testy + paczka  (~15 min)"  "$([ -n "$ST_PHP74" ] && znacznik tak || znacznik nie)"
  else
    m 3 "Instalacja paczki z serwera testowego"           "$([ -n "$ST_PHP74" ] && znacznik tak || znacznik nie)"
  fi
  m 4 "Konfiguracja php.ini dla PHP 7.4"                  "$(znacznik "$ST_INI74")"
  m 5 "PRZEŁĄCZ Apache na PHP 7.4  (restart!)"            "$([ "$ST_APACHE_PHP" = 74 ] && znacznik tak || znacznik nie)"
  m 6 "Weryfikacja (nic nie zmienia)"                     ""
  printf '\n'
  printf '    7) Powrót do PHP 7.2 (rollback)\n'
  printf '    8) Podgląd logów i plików pomocniczych\n'
  printf '    9) Zmień rolę serwera (teraz: %s)\n' "$ROLE"
  printf '    0) Wyjście\n\n'
}

pauza() { printf '\n'; read -r -p "Naciśnij Enter, aby wrócić do menu... " _; }

uruchom() {
  local skrypt="$1"
  printf '\n%s>>> %s%s\n\n' "$C_HEAD" "$skrypt" "$C_N"
  bash "$DIR/$skrypt"
  local rc=$?
  printf '\n'
  [ $rc -eq 0 ] && ok "Zakończono poprawnie: $skrypt" || err "Zakończono błędem ($rc): $skrypt"
  pauza
}

# ----------------------------------------------------------------- podmenu: logi
menu_logi() {
  while true; do
    clear
    printf '%s== Logi i pliki pomocnicze%s\n\n' "$C_HEAD" "$C_N"
    printf '  Katalog roboczy: %s\n\n' "$WORKDIR"
    printf '    1) Ostatni log skryptu wdrożeniowego\n'
    printf '    2) Apache error_log (ostatnie 40 linii)\n'
    printf '    3) Apache error_log – na żywo (Ctrl+C kończy)\n'
    printf '    4) Konfiguracja LoadModule (Apache)\n'
    printf '    5) php.ini dla PHP 7.4 – kluczowe ustawienia\n'
    printf '    6) Lista plików w katalogu roboczym\n'
    printf '    7) Wynik testów run-tests.php (podsumowanie)\n'
    printf '    0) Powrót\n\n'
    local a; read -r -p "Wybór: " a
    case "$a" in
      1) local L; L=$(ls -t "$WORKDIR"/*.log 2>/dev/null | head -1)
         [ -n "$L" ] && { printf '\n--- %s ---\n' "$L"; tail -60 "$L"; } || warn "Brak logów"; pauza ;;
      2) tail -40 /var/log/httpd/error_log 2>/dev/null || warn "Brak pliku"; pauza ;;
      3) printf '\n(Ctrl+C kończy podgląd)\n\n'; tail -f /var/log/httpd/error_log ;;
      4) local F; F=$(find_php_module_conf) && { printf '\n--- %s ---\n' "$F"; cat "$F"; } || warn "Nie znaleziono"; pauza ;;
      5) if [ -x "$PHP_PREFIX/bin/php" ]; then
           for k in memory_limit max_execution_time upload_max_filesize post_max_size \
                    max_input_vars max_file_uploads date.timezone error_log \
                    session.save_path max_multipart_body_parts; do
             printf '  %-28s = %s\n' "$k" "$("$PHP_PREFIX/bin/php" -r "\$v=ini_get('$k'); echo \$v===false?'(brak)':(\$v===''?'(puste)':\$v);" 2>/dev/null)"
           done
         else warn "PHP 7.4 nie jest zainstalowane"; fi; pauza ;;
      6) ls -lht "$WORKDIR" 2>/dev/null | head -30; pauza ;;
      7) local T="$WORKDIR/run-tests.log"
         if [ -f "$T" ]; then
           sed -n '/Number of tests/,/Time taken/p' "$T"
           printf '\nNieudane testy:\n'
           sed -n '/^FAILED TEST SUMMARY/,/^=====/p' "$T" | grep '\.phpt\]' | sed 's/^/  /'
           printf '\nOczekiwane: 8x rfc1867 + bug45392 (zamierzone zmiany łatki)\n'
         else warn "Brak $T – uruchom kompilację (pozycja 3)"; fi; pauza ;;
      0) return ;;
      *) ;;
    esac
  done
}

# ----------------------------------------------------------------- pętla główna
while true; do
  ekran
  read -r -p "Wybierz pozycję: " WYBOR
  case "$WYBOR" in
    1) uruchom 01-inwentaryzacja.sh ;;
    2) FORCE=1 uruchom 02-repozytoria.sh ;;
    3) if [ "$ROLE" = "test" ]; then
         printf '\n'
         warn "Kompilacja potrwa kilkanaście minut i zainstaluje pakiety deweloperskie."
         [ -n "$ST_PHP74" ] && warn "PHP 7.4 jest już zainstalowane – zostanie zbudowane od nowa (REBUILD=1)."
         read -r -p "Kontynuować? [t/N] " a
         case "$a" in [tTyY]*) REBUILD=1 uruchom 10-build-test.sh ;; *) ;; esac
       else
         if [ ! -f "$PKG" ]; then
           printf '\n'; err "Brak paczki $PKG"
           log "Skopiuj ją z serwera testowego, np.:"
           log "  scp root@TESTOWY:$PKG* /root/"
           pauza
         else
           uruchom 20-install-prod.sh
         fi
       fi ;;
    4) if [ -f "$PHP_PREFIX/etc/php.ini" ]; then
         printf '\n'; warn "php.ini dla 7.4 już istnieje."
         read -r -p "Nadpisać go wzorcem z PHP 7.2? [t/N] " a
         case "$a" in [tTyY]*) FORCE=1 uruchom 30-konfiguracja-php.sh ;; *) uruchom 30-konfiguracja-php.sh ;; esac
       else
         uruchom 30-konfiguracja-php.sh
       fi ;;
    5) printf '\n'
       warn "Apache zostanie ZRESTARTOWANY – strona będzie niedostępna przez kilka sekund."
       [ "$ROLE" = "prod" ] && warn "To serwer PRODUKCYJNY. Upewnij się, że masz okno serwisowe."
       log "W razie problemów wrócisz do PHP 7.2 pozycją 7."
       read -r -p "Kontynuować? [t/N] " a
       case "$a" in [tTyY]*) uruchom 40-wlacz-php74.sh ;; *) ;; esac ;;
    6) uruchom 50-weryfikacja.sh ;;
    7) printf '\n'
       warn "Apache wróci do PHP 7.2 i zostanie zrestartowany."
       read -r -p "Kontynuować? [t/N] " a
       case "$a" in [tTyY]*) uruchom 90-rollback-php72.sh ;; *) ;; esac ;;
    8) menu_logi ;;
    9) wybierz_role && ROLE=$(cat "$ROLE_FILE") ;;
    0) clear
       printf 'Koniec.\n\n'
       zbadaj_stan
       case "$ST_APACHE_PHP" in
         74) ok "Apache używa PHP 7.4 z łatką." ;;
         72) warn "Apache nadal używa PHP 7.2 – podatność NIE jest załatana." ;;
       esac
       log "Katalog roboczy z logami i kopiami: $WORKDIR"
       exit 0 ;;
    *) ;;
  esac
done

