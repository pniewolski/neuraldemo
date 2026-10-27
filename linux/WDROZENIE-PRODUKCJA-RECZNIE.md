# Wdrożenie PHP 7.4 z łatką na PRODUKCJI — instrukcja ręczna

Łatka: **CVE-2026-109618 / CVE-2026-109619**
System: **CentOS 7 + Apache 2.4.6 (prefork) + mod_php 7.2 (remi)**

Ta instrukcja odtwarza krok po kroku to, co robią przetestowane skrypty (`20`, `30`, `40`, `50`, `90`),
ale w pełni ręcznie — każde polecenie masz pod kontrolą.

**Zasada nadrzędna:** PHP 7.4 instalujemy **obok** PHP 7.2. Moduł 7.2 (`libphp7.so`) nie jest nadpisywany.
Przełączenie to podmiana jednej ścieżki w konfiguracji Apache + **pełny restart**. Powrót to przywrócenie kopii.

---

## Założenia i oznaczenia

| Co | Ścieżka |
|---|---|
| Paczka (już skopiowana) | `/root/php-7.4-patched-centos7.tgz` + `.sha256` |
| PHP 7.4 po rozpakowaniu | `/opt/php-7.4-patched` |
| Moduł Apache 7.4 | `/usr/lib64/httpd/modules/libphp74-patched.so` |
| Moduł Apache 7.2 (nietykany) | `/usr/lib64/httpd/modules/libphp7.so` |
| Konfiguracja `LoadModule` | `/etc/httpd/conf.modules.d/15-php.conf` (remi) |
| Katalog na kopie i notatki | `/root/php74-migracja` |

Wszystkie polecenia wykonujesz jako **root**. Jeśli pracujesz przez `sudo`, poprzedź je `sudo`.

> **Okno serwisowe:** krok 7 (restart Apache) powoduje kilkusekundową przerwę w działaniu strony.
> Reszta kroków niczego nie przełącza i jest bezpieczna do wykonania wcześniej.

---

## Krok 0 — Przygotowanie i kopia bezpieczeństwa

```bash
# Snapshot maszyny wirtualnej ZRÓB TERAZ (poziom hypervisora) – to najszybszy rollback.

# Katalog roboczy na kopie zapasowe i notatki
mkdir -p /root/php74-migracja

# Kopia całej konfiguracji Apache (wraca jednym poleceniem w razie czego)
tar czf /root/php74-migracja/backup-httpd-$(date +%Y%m%d-%H%M%S).tgz /etc/httpd
```

**Dlaczego:** snapshot i kopia `/etc/httpd` to dwie niezależne drogi powrotu, zanim cokolwiek zmienimy.

---

## Krok 1 — Sprawdzenie stanu wyjściowego

```bash
# Czy to na pewno prefork (mod_php tego wymaga)
httpd -V | grep -i 'Server MPM'
#  -> Server MPM: prefork

# Jaką wersję PHP Apache ma teraz (z logu ostatniego startu)
grep -o 'PHP/[0-9][^ ]*' /var/log/httpd/error_log | tail -1
#  -> PHP/7.2.34  (albo podobna 7.2.x)

# Gdzie jest dyrektywa LoadModule i jak wygląda
grep -rl 'LoadModule php7_module' /etc/httpd/conf.modules.d/
#  -> /etc/httpd/conf.modules.d/15-php.conf
cat /etc/httpd/conf.modules.d/15-php.conf
```

Plik z remi ma **dwie** dyrektywy `LoadModule` — to normalne:

```apache
<IfModule prefork.c>
    LoadModule php7_module modules/libphp7.so        # <- TEN podmienimy (prefork)
</IfModule>
<IfModule !prefork.c>
    LoadModule php7_module modules/libphp7-zts.so    # <- zostaje bez zmian
</IfModule>
```

Podmieniamy wyłącznie wariant `libphp7.so` (prefork). Wariant `-zts` dotyczy MPM wielowątkowych i na tym serwerze nie jest używany.

---

## Krok 2 — Zapis listy rozszerzeń PHP 7.2 (punkt odniesienia)

Zrób to **przed** przełączeniem — inaczej nie porównasz, czy 7.4 ma te same rozszerzenia.

```bash
# Ustal DocumentRoot działającej strony (gdzie Apache wykonuje PHP)
grep -rhE '^[[:space:]]*DocumentRoot' /etc/httpd/conf/httpd.conf /etc/httpd/conf.d/ 2>/dev/null
# Zapamiętaj ścieżkę, np. /var/www/html. Użyj jej poniżej jako DOCROOT.

DOCROOT=/var/www/html        # <-- ustaw zgodnie z powyższym

# Lista rozszerzeń widziana przez Apache (przez działający serwer, nie CLI)
cat > "$DOCROOT/_ext72.php" <<'PHP'
<?php echo implode("\n", get_loaded_extensions()), "\n";
PHP
curl -s http://localhost/_ext72.php | sort -f > /root/php74-migracja/php72-modules-apache.txt
rm -f "$DOCROOT/_ext72.php"

cat /root/php74-migracja/php72-modules-apache.txt
```

**Jeśli `curl http://localhost` nie zwraca listy** (zły vhost, zapora), użyj właściwego adresu/hosta,
np. `curl -s -H 'Host: twojadomena.pl' http://127.0.0.1/_ext72.php`. Lista musi zawierać nazwy jak
`curl`, `openssl`, `session`, `json` itd. — jeśli dostajesz HTML, trafiłeś w zły katalog.

---

## Krok 3 — Weryfikacja i rozpakowanie paczki

```bash
cd /root

# Suma kontrolna – paczka nie może być uszkodzona przy kopiowaniu
sha256sum -c /root/php-7.4-patched-centos7.tgz.sha256
#  -> /root/php-7.4-patched-centos7.tgz: OK

# Podejrzyj, co jest w środku – PRZED rozpakowaniem
tar tzf /root/php-7.4-patched-centos7.tgz | head -20
# Powinny być ścieżki: opt/php-7.4-patched/... oraz usr/lib64/httpd/modules/libphp74-patched.so

# Zapamiętaj sumę modułu 7.2 – sprawdzimy, że paczka go NIE rusza
md5sum /usr/lib64/httpd/modules/libphp7.so
```

Rozpakowanie (ścieżki w paczce są względem `/`):

```bash
tar xzf /root/php-7.4-patched-centos7.tgz -C /

# Sprawdź, że moduł PHP 7.2 ma NADAL tę samą sumę co przed chwilą
md5sum /usr/lib64/httpd/modules/libphp7.so
```

**Obie sumy `libphp7.so` muszą być identyczne.** Jeśli się różnią — paczka nadpisała moduł 7.2,
**przerwij** i zgłoś to (coś jest nie tak z zawartością paczki).

Powinny pojawić się nowe pliki:

```bash
ls -l /usr/lib64/httpd/modules/libphp74-patched.so
ls -ld /opt/php-7.4-patched
```

---

## Krok 4 — SELinux i biblioteki uruchomieniowe

```bash
# Nadaj właściwe etykiety SELinux nowym plikom (jeśli SELinux działa)
restorecon -Rv /usr/lib64/httpd/modules/libphp74-patched.so /opt/php-7.4-patched 2>/dev/null

getenforce        # Enforcing / Permissive / Disabled – dobrze wiedzieć
# Jeśli Enforcing, etykieta modułu powinna być httpd_modules_t:
ls -Z /usr/lib64/httpd/modules/libphp74-patched.so
```

Doinstaluj biblioteki, których wymaga PHP 7.4 (zwykle już są — `yum` nic nie zrobi):

```bash
yum -y install openssl-libs zlib libcurl bzip2-libs readline libxml2 ncurses-libs
```

Sprawdź, że moduł i binarka nie mają brakujących zależności:

```bash
ldd /usr/lib64/httpd/modules/libphp74-patched.so /opt/php-7.4-patched/bin/php | grep 'not found'
#  -> (brak wyniku = wszystko dostępne)

# Binarka PHP 7.4 się uruchamia
/opt/php-7.4-patched/bin/php -v | head -1
#  -> PHP 7.4.34-dev ...
```

**Jeśli `grep 'not found'` cokolwiek wypisze** — PHP nie wystartuje. Doinstaluj brakującą bibliotekę
i powtórz, zanim przejdziesz dalej.

---

## Krok 5 — Konfiguracja `php.ini` dla PHP 7.4

Bierzemy `php.ini` z działającego PHP 7.2 jako wzorzec.

```bash
# Gdzie jest php.ini obecnego PHP 7.2
php --ini | grep 'Loaded Configuration File'
#  -> Loaded Configuration File: /etc/php.ini   (zwykle tak)

SRC_INI=/etc/php.ini                      # <-- ustaw zgodnie z powyższym
DST_INI=/opt/php-7.4-patched/etc/php.ini

mkdir -p /opt/php-7.4-patched/etc/conf.d
cp "$SRC_INI" "$DST_INI"

# Rozszerzenia są WKOMPILOWANE w 7.4. Pliki .so z 7.2 nie wczytają się w 7.4,
# więc wyłączamy wpisy extension= / zend_extension= z odziedziczonego php.ini.
sed -i 's/^\s*extension\s*=/;&/; s/^\s*zend_extension\s*=/;&/' "$DST_INI"
```

Sprawdź, że PHP 7.4 startuje z tym `php.ini` bez ostrzeżeń:

```bash
/opt/php-7.4-patched/bin/php -c "$DST_INI" -r 'echo "PHP_OK\n";'
#  -> PHP_OK   (i ŻADNYCH linii "Unable to load" / "Warning")
```

Podejrzyj kluczowe ustawienia (powinny być takie jak w 7.2):

```bash
for k in memory_limit max_execution_time upload_max_filesize post_max_size \
         max_input_vars date.timezone session.save_path max_multipart_body_parts; do
  printf '  %-28s = %s\n' "$k" \
    "$(/opt/php-7.4-patched/bin/php -c "$DST_INI" -r "echo ini_get('$k');")"
done
```

Uwagi:
- `max_multipart_body_parts` pochodzi z łatki. Wartość `-1` oznacza `max_input_vars + max_file_uploads` (zalecane).
- `session.upload_progress` jest **wyłączony przez łatkę** niezależnie od ustawień.
- Pusty `session.save_path` jest OK — ścieżkę narzuca Apache (`php_value` w `php.conf`).

---

## Krok 6 — Test składni konfiguracji (jeszcze bez przełączania)

Zanim przełączymy, upewnij się, że sam Apache ma poprawną konfigurację **w obecnym stanie**:

```bash
httpd -t
#  -> Syntax OK
```

Komunikat `AH00558: ... fully qualified domain name` jest nieszkodliwy — liczy się `Syntax OK`.

---

## Krok 7 — Przełączenie Apache na PHP 7.4  ⚠️ OKNO SERWISOWE

Od tego miejsca następuje krótka przerwa w działaniu strony.

```bash
MODCONF=/etc/httpd/conf.modules.d/15-php.conf

# Kopia pliku DO ROLLBACKU (dokładnie ta nazwa – użyjemy jej w kroku 9)
cp -a "$MODCONF" /root/php74-migracja/15-php.conf.php72

# Podmiana TYLKO wariantu prefork: libphp7.so -> libphp74-patched.so
# (wzorzec 'libphp7\.so' nie pasuje do 'libphp7-zts.so', więc -zts zostaje nietknięty)
sed -i 's|modules/libphp7\.so|modules/libphp74-patched.so|' "$MODCONF"

# Sprawdź, że zmieniła się dokładnie JEDNA dyrektywa
cat "$MODCONF"
grep -c 'modules/libphp74-patched.so' "$MODCONF"   # -> 1
grep -c 'modules/libphp7-zts.so'       "$MODCONF"   # -> 1 (nietknięty)
```

Test składni z nowym modułem:

```bash
httpd -t
#  -> Syntax OK
```

Jeśli `httpd -t` zgłosi błąd — **nie restartuj**. Przywróć plik i przerwij:
```bash
cp -a /root/php74-migracja/15-php.conf.php72 "$MODCONF"
```

**PEŁNY restart** (stop + start). Nie używaj `reload`, `graceful` ani `httpd -k restart` —
przy podmianie mod_php powodują segfaulty:

```bash
systemctl restart httpd
sleep 2
systemctl is-active httpd        # -> active
```

---

## Krok 8 — Weryfikacja po przełączeniu

### 8a. Wersja i łatka (przez działający serwer)

```bash
DOCROOT=/var/www/html            # <-- ten sam co w kroku 2

cat > "$DOCROOT/_check.php" <<'PHP'
<?php
echo "VER="  . PHP_VERSION . "\n";
echo "SAPI=" . PHP_SAPI . "\n";
echo "INI="  . php_ini_loaded_file() . "\n";
echo "PATCH=" . var_export(ini_get('max_multipart_body_parts'), true) . "\n";
PHP
curl -s http://localhost/_check.php
rm -f "$DOCROOT/_check.php"
```

Oczekiwane:
```
VER=7.4.34-dev
SAPI=apache2handler
INI=/opt/php-7.4-patched/etc/php.ini
PATCH='-1'                        <- obecność tej dyrektywy = łatka aktywna
```

Gdyby `PATCH=false` — moduł jest bez łatki. Wykonaj rollback (krok 9) i zgłoś.

### 8b. Rozszerzenia 7.4 = 7.2

```bash
cat > "$DOCROOT/_ext74.php" <<'PHP'
<?php echo implode("\n", get_loaded_extensions()), "\n";
PHP
curl -s http://localhost/_ext74.php | sort -f > /root/php74-migracja/php74-modules-apache.txt
rm -f "$DOCROOT/_ext74.php"

diff -i /root/php74-migracja/php72-modules-apache.txt \
        /root/php74-migracja/php74-modules-apache.txt
#  -> (brak różnic = rozszerzenia identyczne)
```

### 8c. Test funkcjonalny (sesje, upload, zmienne żądania)

```bash
DOCROOT=/var/www/html
cat > "$DOCROOT/_smoke.php" <<'PHP'
<?php
header('Content-Type: text/plain');
$ok = true;
$t = function($n,$c) use (&$ok){ echo ($c?"OK   ":"FAIL ").$n."\n"; $ok=$ok&&$c; };
session_start();
$_SESSION['n'] = ($_SESSION['n'] ?? 0) + 1;
$t('sesja', $_SESSION['n'] >= 1);
$t('GET a[b][c]', ($_GET['a']['b']['c'] ?? null) === 'x');
$t('POST pole', ($_POST['field'] ?? null) === 'value');
$f = $_FILES['up'] ?? null;
$t('upload pliku', $f && $f['error']===UPLOAD_ERR_OK && file_get_contents($f['tmp_name'])==='hello');
$t('upload tablica', isset($_FILES['many']['name'][1]));
echo $ok ? "WSZYSTKO OK\n" : "SA BLEDY\n";
PHP
printf hello > /tmp/_up.txt
curl -sg "http://localhost/_smoke.php?a[b][c]=x" \
     -F field=value -F "up=@/tmp/_up.txt" \
     -F "many[]=@/tmp/_up.txt" -F "many[]=@/tmp/_up.txt"
rm -f "$DOCROOT/_smoke.php" /tmp/_up.txt
#  -> wszystkie linie OK, na końcu: WSZYSTKO OK
```

### 8d. Log Apache — brak segfaultów po starcie

```bash
# tylko wpisy po ostatnim starcie Apache
awk '/resuming normal operations/{buf="";next}{buf=buf$0"\n"}END{printf"%s",buf}' \
    /var/log/httpd/error_log | grep -i 'segmentation fault\|php7\?:error'
#  -> (brak wyniku = czysto)
```

Jeśli pojawią się segfaulty — prawie zawsze znaczy to, że Apache został **przeładowany**, a nie zrestartowany.
Wykonaj `systemctl restart httpd` (pełny restart).

### 8e. Sprawdzenie w aplikacji (ręcznie w przeglądarce)

- logowanie i sesje użytkowników
- upload plików (wiele naraz, duże pliki)
- formularze z dużą liczbą pól
- logi aplikacji: `Deprecated` / `Warning` / `Fatal` (różnice PHP 7.2 → 7.4)
- jeśli aplikacja używa **paska postępu uploadu** (`session.upload_progress`) — łatka go wyłącza

---

## Krok 9 — Rollback do PHP 7.2 (gdyby coś było nie tak)

Działa w każdej chwili po kroku 7. Przywraca moduł 7.2 i restartuje Apache.

```bash
MODCONF=/etc/httpd/conf.modules.d/15-php.conf

# Przywróć kopię sprzed przełączenia
cp -a /root/php74-migracja/15-php.conf.php72 "$MODCONF"

# Potwierdź, że wrócił wpis z libphp7.so
grep -n 'modules/libphp7\.so' "$MODCONF"

# Test składni i PEŁNY restart
httpd -t && systemctl restart httpd
sleep 2
systemctl is-active httpd        # -> active
```

Potwierdzenie powrotu do 7.2:

```bash
grep -o 'PHP/[0-9][^ ]*' /var/log/httpd/error_log | tail -1
#  -> PHP/7.2.34
```

PHP 7.4 zostaje zainstalowane — można je włączyć ponownie, powtarzając krok 7.

---

## Krok 10 — PHP w linii poleceń (cron) — do decyzji

Podatność dotyczy **żądań HTTP** obsługiwanych przez Apache, więc samo przełączenie modułu
zamyka temat dla ruchu webowego. `php` w konsoli i cron **nadal używają 7.2**:

```bash
php -v | head -1                      # -> PHP 7.2.x
/opt/php-7.4-patched/bin/php -v | head -1   # -> PHP 7.4.34-dev
```

To jest celowe i bezpieczne. Jeśli jednak chcesz, by cron też korzystał z 7.4, rób to świadomie
i po testach — np. w konkretnych wpisach crona podawaj pełną ścieżkę `/opt/php-7.4-patched/bin/php`.
Nie podmieniaj systemowego `/usr/bin/php` globalnie bez sprawdzenia zależności.

---

## Jak szybko sprawdzić, czy serwer jest podatny

```bash
# 1. Czy moduł faktycznie załadowany przez Apache zawiera łatkę:
grep -qa max_multipart_body_parts /usr/lib64/httpd/modules/libphp7.so \
  && echo "libphp7.so: z latka" || echo "libphp7.so: BEZ latki"

# 2. Co odpowiada działający serwer:
echo '<?php var_dump(ini_get("max_multipart_body_parts"));' > /var/www/html/_t.php
curl -s http://localhost/_t.php        # string(2) "-1" = zalatane, bool(false) = podatne
rm -f /var/www/html/_t.php

# 3. Jaką wersję zgłosił Apache przy starcie:
grep -o 'PHP/[0-9][^ ]*' /var/log/httpd/error_log | tail -1
```

---

## Ściąga — kolejność bez komentarzy

```bash
# 0. kopia
mkdir -p /root/php74-migracja
tar czf /root/php74-migracja/backup-httpd-$(date +%F-%H%M%S).tgz /etc/httpd

# 3. paczka
cd /root
sha256sum -c php-7.4-patched-centos7.tgz.sha256
md5sum /usr/lib64/httpd/modules/libphp7.so
tar xzf php-7.4-patched-centos7.tgz -C /
md5sum /usr/lib64/httpd/modules/libphp7.so        # musi być identyczny

# 4. libki
restorecon -Rv /usr/lib64/httpd/modules/libphp74-patched.so /opt/php-7.4-patched 2>/dev/null
yum -y install openssl-libs zlib libcurl bzip2-libs readline libxml2 ncurses-libs
ldd /usr/lib64/httpd/modules/libphp74-patched.so /opt/php-7.4-patched/bin/php | grep 'not found'
/opt/php-7.4-patched/bin/php -v | head -1

# 5. php.ini
cp /etc/php.ini /opt/php-7.4-patched/etc/php.ini
mkdir -p /opt/php-7.4-patched/etc/conf.d
sed -i 's/^\s*extension\s*=/;&/; s/^\s*zend_extension\s*=/;&/' /opt/php-7.4-patched/etc/php.ini
/opt/php-7.4-patched/bin/php -c /opt/php-7.4-patched/etc/php.ini -r 'echo "PHP_OK\n";'

# 7. przełączenie (OKNO SERWISOWE)
cp -a /etc/httpd/conf.modules.d/15-php.conf /root/php74-migracja/15-php.conf.php72
sed -i 's|modules/libphp7\.so|modules/libphp74-patched.so|' /etc/httpd/conf.modules.d/15-php.conf
httpd -t && systemctl restart httpd && sleep 2 && systemctl is-active httpd

# 8. weryfikacja
grep -o 'PHP/[0-9][^ ]*' /var/log/httpd/error_log | tail -1   # PHP/7.4...

# 9. ROLLBACK w razie czego
cp -a /root/php74-migracja/15-php.conf.php72 /etc/httpd/conf.modules.d/15-php.conf
httpd -t && systemctl restart httpd
```

