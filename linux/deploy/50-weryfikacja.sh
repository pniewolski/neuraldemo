#!/bin/bash
# 50-weryfikacja.sh – krok 9: sprawdzenie, czy PHP 7.4 z łatką działa poprawnie w Apache.
# Nic nie zmienia. Można uruchamiać wielokrotnie, także po wdrożeniu.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_root
start_log "50-weryfikacja"

FAILED=0
check() { if [ "$2" = "1" ]; then ok "$1"; else err "$1"; FAILED=$((FAILED+1)); fi; }

head1 "Moduł PHP w Apache"
httpd -M 2>/dev/null | grep -i php | sed 's/^/  /'
MODCONF=$(find_php_module_conf) && sed 's/^/  /' "$MODCONF"
CUR=$(current_apache_php)
log "Skonfigurowana wersja: $CUR"

head1 "Wersja PHP obsługująca żądania"
INFO=$(php_probe '<?php echo PHP_VERSION,"|",PHP_SAPI,"|",php_ini_loaded_file();')
log "  $INFO"
case "$INFO" in
  7.4*) check "Apache używa PHP 7.4" 1 ;;
  "")   check "Apache odpowiada na $TEST_URL" 0; err "Brak odpowiedzi – sprawdź TEST_URL w config.sh i /var/log/httpd/error_log" ;;
  *)    check "Apache używa PHP 7.4 (jest: ${INFO%%|*})" 0 ;;
esac
case "$INFO" in *apache2handler*) check "SAPI: apache2handler (mod_php)" 1 ;; *) check "SAPI: apache2handler" 0 ;; esac
case "$INFO" in *"$PHP_PREFIX/etc/php.ini"*) check "Wczytany php.ini: $PHP_PREFIX/etc/php.ini" 1 ;;
                *) check "Wczytany php.ini z $PHP_PREFIX/etc (jest: ${INFO##*|})" 0 ;; esac

head1 "Czy łatka jest aktywna"
# max_multipart_body_parts istnieje wyłącznie w wersji z łatką
MP=$(php_probe '<?php $v=ini_get("max_multipart_body_parts"); echo $v===false?"BRAK":$v;')
log "  max_multipart_body_parts = ${MP:-(brak odpowiedzi)}"
case "$MP" in BRAK|"") check "Łatka CVE-2026-109618/109619 aktywna" 0 ;; *) check "Łatka CVE-2026-109618/109619 aktywna" 1 ;; esac

head1 "Rozszerzenia: Apache 7.4 vs zapisany stan 7.2"
REF="$WORKDIR/php72-modules-apache.txt"
if [ -f "$REF" ]; then
  NOW=$(mktemp); php_probe '<?php echo implode("\n", get_loaded_extensions()),"\n";' | sort -f > "$NOW"
  if diff -i "$REF" "$NOW" > "$WORKDIR/ext-diff.txt"; then
    check "Rozszerzenia identyczne jak w PHP 7.2" 1
  else
    check "Rozszerzenia identyczne jak w PHP 7.2" 0
    cat "$WORKDIR/ext-diff.txt" | sed 's/^/  /'
    log "  (< brakuje w 7.4, > nadmiarowe w 7.4)"
  fi
  rm -f "$NOW"
else
  warn "Brak $REF – uruchom 01-inwentaryzacja.sh przed przełączeniem, żeby mieć punkt odniesienia"
fi

head1 "Test funkcjonalny: sesje, upload, zmienne żądania"
# obszary zmienione przez łatkę
cat > "$DOCROOT/_smoke_$$.php" <<'PHPEOF'
<?php
header('Content-Type: text/plain');
$ok = true;
$t = function($n, $c) use (&$ok) { echo ($c ? "OK   " : "FAIL ") . $n . "\n"; $ok = $ok && $c; };
session_start();
$_SESSION['n'] = ($_SESSION['n'] ?? 0) + 1;
$t('sesja (zapis/odczyt)', $_SESSION['n'] >= 1);
$t('GET a[b][c]', ($_GET['a']['b']['c'] ?? null) === 'x');
$t('POST pole', ($_POST['field'] ?? null) === 'value');
$f = $_FILES['up'] ?? null;
$t('upload pliku', $f && $f['error'] === UPLOAD_ERR_OK && file_get_contents($f['tmp_name']) === 'hello');
$t('upload tablica plikow', isset($_FILES['many']['name'][1]));
$a = []; for ($i = 0; $i < 100000; $i++) { $a["k$i"] = $i; }
$t('duza tablica (100k)', count($a) === 100000);
$t('alokacja 10MB', strlen(str_repeat('x', 10485760)) === 10485760);
echo $ok ? "WSZYSTKO OK\n" : "SA BLEDY\n";
PHPEOF
printf hello > /tmp/_up_$$.txt
RES=$(curl -sg --max-time 20 "$TEST_URL/_smoke_$$.php?a[b][c]=x" \
      -F field=value -F "up=@/tmp/_up_$$.txt" \
      -F "many[]=@/tmp/_up_$$.txt" -F "many[]=@/tmp/_up_$$.txt" 2>/dev/null || true)
rm -f "$DOCROOT/_smoke_$$.php" /tmp/_up_$$.txt
printf '%s\n' "$RES" | sed 's/^/  /'
case "$RES" in *"WSZYSTKO OK"*) check "Test funkcjonalny" 1 ;; *) check "Test funkcjonalny" 0 ;; esac

head1 "Błędy w logu Apache"
SEG=$(tail -500 /var/log/httpd/error_log 2>/dev/null | grep -c 'Segmentation fault' || true)
PHPERR=$(tail -500 /var/log/httpd/error_log 2>/dev/null | grep -ci 'php7\?:error\|Unable to load' || true)
[ "${SEG:-0}" -eq 0 ] && check "Brak segfaultów w ostatnich 500 liniach logu" 1 \
                      || { check "Brak segfaultów w ostatnich 500 liniach logu" 0
                           tail -500 /var/log/httpd/error_log | grep 'Segmentation fault' | tail -3 | sed 's/^/  /'
                           err "Segfaulty najczęściej oznaczają przeładowanie zamiast restartu – użyj: systemctl restart httpd"; }
[ "${PHPERR:-0}" -eq 0 ] && ok "Brak błędów PHP w logu" \
                         || { warn "Błędy PHP w logu ($PHPERR):"
                              tail -500 /var/log/httpd/error_log | grep -i 'php7\?:error\|Unable to load' | tail -5 | sed 's/^/  /'; }

head1 "PHP w linii poleceń (cron, skrypty)"
log "  php -v      -> $(php -v 2>/dev/null | head -1)"
log "  $PHP_PREFIX/bin/php -v -> $("$PHP_PREFIX/bin/php" -v 2>/dev/null | head -1)"
php -v 2>/dev/null | head -1 | grep -q '^PHP 7\.4' \
  && ok "CLI używa PHP 7.4" \
  || warn "CLI nadal używa PHP 7.2 – podatność dotyczy HTTP, ale rozważ przeniesienie crona (krok 10 w WDROZENIE.md)"

head1 "Podsumowanie"
if [ "$FAILED" -eq 0 ]; then
  ok "Wszystkie sprawdzenia zakończone pomyślnie"
  log ""
  log "Do sprawdzenia ręcznie w aplikacji:"
  log "  - logowanie i sesje użytkowników"
  log "  - upload plików (wiele naraz, duże pliki)"
  log "  - formularze z dużą liczbą pól"
  log "  - logi aplikacji: Deprecated / Warning / Fatal (zmiany PHP 7.2 -> 7.4)"
  log "  - czy aplikacja nie używa paska postępu uploadu (session.upload_progress) – łatka go wyłącza"
  exit 0
else
  err "Nieudane sprawdzenia: $FAILED"
  log "W razie problemów cofnij zmianę: ./90-rollback-php72.sh"
  exit 1
fi

