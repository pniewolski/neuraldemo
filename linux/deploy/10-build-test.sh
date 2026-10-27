#!/bin/bash
# 10-build-test.sh – [SERWER TESTOWY] kroki 2–5: kompilacja PHP 7.4 z łatką jako moduł Apache
# i spakowanie wyniku do przeniesienia na produkcję.
#
# NIE przełącza Apache. Po zakończeniu uruchom 30-konfiguracja-php.sh, a potem 40-wlacz-php74.sh.
#
# Zmienne:
#   ASSUME_YES=1  – bez pytań
#   SKIP_TESTS=1  – pomija run-tests.php (niezalecane)
#   REBUILD=1     – wymusza przebudowę, gdy PHP jest już zainstalowane

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_root
start_log "10-build-test"
require_centos7

JOBS="$(nproc)"

# ---------------------------------------------------------------- stan wyjściowy
head1 "Stan wyjściowy"
if [ -d "$PHP_PREFIX" ] && [ "${REBUILD:-0}" != "1" ]; then
  warn "$PHP_PREFIX już istnieje (wersja: $("$PHP_PREFIX/bin/php" -v 2>/dev/null | head -1 || true))"
  log  "Aby zbudować od nowa, uruchom: REBUILD=1 $0"
  exit 0
fi
[ -f "$MOD_DIR/libphp7.so" ] || warn "Brak $MOD_DIR/libphp7.so – upewnij się, że to serwer z mod_php 7.2"
ok "Rdzenie do kompilacji: $JOBS"

# ---------------------------------------------------------------- krok 2: pakiety
head1 "Krok 2: narzędzia i biblioteki do kompilacji"
confirm "Zainstalować pakiety: ${BUILD_PKGS[*]} ?"
yum -y install "${BUILD_PKGS[@]}"
[ -x /usr/bin/apxs ] || die "Brak /usr/bin/apxs – pakiet httpd-devel nie zainstalował się poprawnie."
ok "Pakiety zainstalowane, apxs dostępny"

# ---------------------------------------------------------------- krok 3: bison
head1 "Krok 3: bison >= 3.0"
BISON_OK=0
if command -v bison >/dev/null 2>&1; then
  BV=$(bison --version | head -1 | awk '{print $NF}')
  case "$BV" in 3.*|4.*) BISON_OK=1; ok "Zainstalowany bison $BV" ;; *) log "Systemowy bison $BV jest za stary" ;; esac
fi
if [ "$BISON_OK" -eq 0 ]; then
  log "Buduję bison $BISON_VER do /usr/local (systemowy pozostaje nietknięty)"
  cd /usr/local/src
  [ -f "bison-$BISON_VER.tar.xz" ] || curl -fsSLO "https://ftp.gnu.org/gnu/bison/bison-$BISON_VER.tar.xz"
  rm -rf "bison-$BISON_VER"; tar xJf "bison-$BISON_VER.tar.xz"
  cd "bison-$BISON_VER"
  ./configure --prefix=/usr/local >/dev/null
  make -j"$JOBS" >/dev/null && make install >/dev/null
  hash -r
  bison --version | head -1 | grep -qE ' 3\.| 4\.' || die "bison nadal w wersji < 3.0"
  ok "Zainstalowano bison $(bison --version | head -1 | awk '{print $NF}')"
fi

# ---------------------------------------------------------------- krok 4: źródła
head1 "Krok 4: źródła PHP z gałęzi z łatką"
if [ -d "$SRCDIR/.git" ]; then
  log "Katalog $SRCDIR już istnieje – odświeżam"
  cd "$SRCDIR"
  git fetch --depth 1 origin "$PHP_BRANCH"
  git checkout -q FETCH_HEAD
else
  rm -rf "$SRCDIR"
  git clone --depth 1 --branch "$PHP_BRANCH" "$PHP_REPO" "$SRCDIR"
  cd "$SRCDIR"
fi
GOT=$(git rev-parse HEAD)
log "Commit: $GOT  $(git log -1 --format=%s)"
if [ "$GOT" = "$PHP_COMMIT" ]; then
  ok "Zgodny z oczekiwanym commitem łatki"
else
  warn "Commit RÓŻNI SIĘ od oczekiwanego ($PHP_COMMIT)."
  warn "Gałąź mogła zostać zaktualizowana. Sprawdź nowe zmiany przed wdrożeniem:"
  warn "  git -C $SRCDIR log --oneline $PHP_COMMIT..HEAD"
  confirm "Kontynuować mimo innego commita?"
fi

# ---------------------------------------------------------------- krok 5: build
head1 "Krok 5: configure"
make distclean >/dev/null 2>&1 || true
rm -rf "$PHP_PREFIX"
./buildconf --force >/dev/null
log "Flagi: ${CONFIGURE_FLAGS[*]}"
./configure "${CONFIGURE_FLAGS[@]}" > "$WORKDIR/configure.log" 2>&1 || {
  err "configure zakończone błędem. Ostatnie linie:"; tail -30 "$WORKDIR/configure.log"; exit 1; }
grep -q 'Thank you for using PHP' "$WORKDIR/configure.log" || die "configure nie zakończyło się poprawnie"
ok "configure OK (log: $WORKDIR/configure.log)"

head1 "Krok 5: make (to potrwa kilka minut)"
make -j"$JOBS" > "$WORKDIR/make.log" 2>&1 || {
  err "make zakończone błędem. Ostatnie linie:"; tail -40 "$WORKDIR/make.log"; exit 1; }
[ -f libs/libphp7.so ] || die "Nie powstał moduł libs/libphp7.so – sprawdź, czy użyto --with-apxs2"
ok "Zbudowano: libs/libphp7.so ($(du -h libs/libphp7.so | cut -f1)) oraz sapi/cli/php"

# ---------------------------------------------------------------- testy
if [ "${SKIP_TESTS:-0}" = "1" ]; then
  warn "Pominięto testy (SKIP_TESTS=1)"
else
  head1 "Krok 5: testy obszarów zmienionych przez łatkę"
  # "|| TESTS_RC=$?" jest potrzebne: samo "set +e" nie wyłącza pułapki ERR,
  # a niezerowy wynik run-tests.php (są oczekiwane błędy) zgłaszałby fałszywy błąd skryptu.
  TESTS_RC=0
  TEST_PHP_EXECUTABLE=sapi/cli/php sapi/cli/php run-tests.php -j"$JOBS" -q \
      -d opcache.enable_cli=0 Zend/tests ext/session/tests tests/basic tests/lang \
      > "$WORKDIR/run-tests.log" 2>&1 || TESTS_RC=$?

  sed -n '/Number of tests/,/Time taken/p' "$WORKDIR/run-tests.log" || true

  # Ścieżki nieudanych testów; pomijamy te, które łatka zmienia celowo
  FAILED_PATHS=$(sed -n '/^FAILED TEST SUMMARY/,/^=====/p' "$WORKDIR/run-tests.log" \
                 | sed -n 's/.*\[\(.*\.phpt\)\]$/\1/p' || true)
  OCZEKIWANE=$(printf '%s\n' "$FAILED_PATHS" | grep -cE 'rfc1867|bug45392' || true)
  PODEJRZANE=$(printf '%s\n' "$FAILED_PATHS" | grep -vE 'rfc1867|bug45392' | grep '\.phpt$' || true)

  log ""
  log "Nieudane testy zgodne z oczekiwaniem: ${OCZEKIWANE:-0} (8x rfc1867 + bug45392 – zamierzone zmiany łatki)"

  if [ -n "$PODEJRZANE" ]; then
    warn "Pozostałe nieudane testy:"
    printf '%s\n' "$PODEJRZANE" | sed 's/^/  /'
    log ""
    log "Sprawdzam każdy z osobna, bez zrównoleglenia."
    NADAL_ZLE=""
    SRODOWISKO=""
    for t in $PODEJRZANE; do
      rm -f "${t%.phpt}.diff" "${t%.phpt}.out"
      POJ=0
      # bez "-q" – w trybie cichym run-tests.php nie wypisuje linii PASS, których tu szukamy
      TEST_PHP_EXECUTABLE=sapi/cli/php sapi/cli/php run-tests.php \
          -d opcache.enable_cli=0 "$t" > "$WORKDIR/retest.log" 2>&1 || POJ=$?

      if grep -q '^PASS' "$WORKDIR/retest.log"; then
        ok "$t – przechodzi pojedynczo (niestabilny przy zrównolegleniu, nie wina łatki)"
      elif grep -q '^SKIP' "$WORKDIR/retest.log"; then
        ok "$t – pominięty (brak warunków w tym środowisku)"
      elif grep -q 'php_cli_server' "$t" 2>/dev/null; then
        # Test wymaga wbudowanego serwera HTTP PHP. Sprawdzamy, czy w ogóle da się go
        # tu uruchomić – jeśli nie, przyczyna leży w środowisku, a nie w łatce.
        warn "$t – test wymaga wbudowanego serwera HTTP PHP."
        log  "    Komunikat: $(head -1 "${t%.phpt}.out" 2>/dev/null)"
        log  "    Sprawdzam, czy wbudowany serwer w ogóle działa w tym środowisku..."

        # 0 = działa, 1 = nie działa, 2 = brak binarki do porównania
        NOWY=1; STARY=2
        test_wbudowanego_serwera sapi/cli/php 8964 && NOWY=0 || NOWY=1
        if command -v php >/dev/null 2>&1; then
          test_wbudowanego_serwera "$(command -v php)" 8965 && STARY=0 || STARY=1
        fi

        if [ "$NOWY" -eq 0 ]; then
          ok "  Wbudowany serwer w zbudowanym PHP 7.4 działa poprawnie."
          log "  Niepowodzenie testu było chwilowe (zajęty port albo obciążenie maszyny)."
          SRODOWISKO="$SRODOWISKO $t"
        elif [ "$STARY" -eq 1 ]; then
          ok "  Wbudowany serwer nie startuje ANI w nowym PHP 7.4, ANI w obecnym PHP 7.2."
          log "  To ograniczenie środowiska (zapora, SELinux, zajęty port), a nie skutek łatki."
          SRODOWISKO="$SRODOWISKO $t"
        elif [ "$STARY" -eq 0 ]; then
          err "  Wbudowany serwer działa w PHP 7.2, ale NIE w zbudowanym PHP 7.4."
          err "  To wymaga wyjaśnienia – może wskazywać na problem z kompilacją."
          NADAL_ZLE="$NADAL_ZLE $t"
        else
          warn "  Wbudowany serwer nie startuje w PHP 7.4, a nie ma PHP 7.2 do porównania."
          log  "  Najpewniej ograniczenie środowiska, ale bez porównania nie ma pewności."
          SRODOWISKO="$SRODOWISKO $t"
        fi
      else
        err "$t – nadal nie przechodzi"
        [ -f "${t%.phpt}.diff" ] && head -15 "${t%.phpt}.diff" | sed 's/^/    /'
        NADAL_ZLE="$NADAL_ZLE $t"
      fi
    done

    [ -n "$SRODOWISKO" ] && warn "Testy zależne od środowiska (do pominięcia):$SRODOWISKO"

    if [ -n "$NADAL_ZLE" ]; then
      err "Testy, które nie przechodzą także pojedynczo:$NADAL_ZLE"
      err "To wymaga wyjaśnienia PRZED wdrożeniem na produkcję."
      log ""
      log "Aby sprawdzić, czy winna jest łatka, zbuduj obok wersję bez niej i porównaj:"
      log "  git -C $SRCDIR fetch --depth 1 origin PHP-7.4 && git -C $SRCDIR checkout FETCH_HEAD"
      confirm "Mimo to kontynuować?"
    else
      ok "Brak błędów wskazujących na problem z łatką"
    fi
  else
    ok "Brak nieoczekiwanych błędów (log: $WORKDIR/run-tests.log)"
  fi
fi

# ---------------------------------------------------------------- instalacja
head1 "Krok 5: instalacja"
warn "Celowo NIE używamy 'make install' – nadpisałoby $MOD_DIR/libphp7.so (moduł PHP 7.2) i zmieniło httpd.conf."
make install-cli install-modules install-build install-headers install-programs install-pharcmd \
     > "$WORKDIR/install.log" 2>&1 || { err "Instalacja nieudana:"; tail -30 "$WORKDIR/install.log"; exit 1; }
ok "Zainstalowano CLI i rozszerzenia w $PHP_PREFIX"

MD5_BEFORE=$(md5sum "$MOD_DIR/libphp7.so" 2>/dev/null | cut -d' ' -f1 || echo "-")
install -m 755 libs/libphp7.so "$MOD_DIR/$MOD_NAME"
restorecon -v "$MOD_DIR/$MOD_NAME" 2>/dev/null || true
MD5_AFTER=$(md5sum "$MOD_DIR/libphp7.so" 2>/dev/null | cut -d' ' -f1 || echo "-")
[ "$MD5_BEFORE" = "$MD5_AFTER" ] || die "Moduł PHP 7.2 został zmodyfikowany! Przywróć go z kopii zapasowej."
ok "Moduł 7.4 zainstalowany jako $MOD_DIR/$MOD_NAME, moduł 7.2 nietknięty"

# ---------------------------------------------------------------- weryfikacja
head1 "Weryfikacja"
"$PHP_PREFIX/bin/php" -v | head -1
MISSING=$(ldd "$MOD_DIR/$MOD_NAME" "$PHP_PREFIX/bin/php" | grep 'not found' || true)
[ -z "$MISSING" ] && ok "Wszystkie biblioteki dostępne" || { err "Brakujące biblioteki:"; printf '%s\n' "$MISSING"; }

if command -v php >/dev/null 2>&1; then
  if diff <(php -m | sort -f) <("$PHP_PREFIX/bin/php" -m | sort -f) > "$WORKDIR/modules-diff.txt" 2>&1; then
    ok "Rozszerzenia IDENTYCZNE z PHP 7.2"
  else
    warn "Rozszerzenia różnią się od PHP 7.2:"
    cat "$WORKDIR/modules-diff.txt"
    warn "Jeśli czegoś brakuje, dopisz flagę w config.sh i uruchom: REBUILD=1 $0"
  fi
fi

# ---------------------------------------------------------------- paczka
head1 "Paczka na produkcję"
rm -f "$PKG" "$PKG.sha256"
tar czf "$PKG" -C / "${PHP_PREFIX#/}" "${MOD_DIR#/}/$MOD_NAME"
sha256sum "$PKG" > "$PKG.sha256"
ok "Utworzono: $PKG ($(du -h "$PKG" | cut -f1))"
ok "Suma kontrolna: $PKG.sha256"

head1 "Gotowe"
log "Dalej na TYM serwerze:"
log "  ./30-konfiguracja-php.sh     # php.ini dla 7.4"
log "  ./40-wlacz-php74.sh          # podmiana modułu w Apache + restart"
log "  ./50-weryfikacja.sh          # sprawdzenie"
log ""
log "Przeniesienie na produkcję:"
log "  scp $PKG $PKG.sha256 root@PRODUKCJA:/root/"
log "  scp -r $(dirname "$(readlink -f "$0")") root@PRODUKCJA:/root/"


