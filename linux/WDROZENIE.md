# Wdrożenie PHP 7.4 z łatką CVE-2026-109618 / CVE-2026-109619 na CentOS 7 (mod_php)

Instrukcja dla serwera **testowego**, a potem **produkcyjnego**.

Stan serwera:

- CentOS 7 (Core),
- Apache 2.4.6, MPM `prefork`,
- PHP 7.2.22 z repozytorium **remi** jako moduł Apache (`httpd -M` pokazuje `php7_module (shared)`).

Docelowo:

- PHP z gałęzi `PHP-7.4-CVE-2026-109618-109619` budujemy jako **moduł Apache**, z **tym samym zestawem rozszerzeń** co obecne PHP 7.2.
- Nowy moduł dostaje własną nazwę pliku: `/usr/lib64/httpd/modules/libphp74-patched.so`. Moduł 7.2 z remi (`libphp7.so`) **zostaje nietknięty**.
- Przełączenie to zmiana jednej linii `LoadModule` i restart Apache. Powrót to przywrócenie tej linii.
- Konfiguracja Apache dla PHP (`/etc/httpd/conf.d/php.conf`, `php_value` w vhostach i `.htaccess`) **działa bez zmian**. Nie ma php-fpm, portów ani usług systemd.
- PHP 7.4 ma własny `php.ini` w `/opt/php-7.4-patched/etc/`. Nie czyta `/etc/php.ini` ani `/etc/php.d/`, gdzie są rozszerzenia skompilowane dla 7.2.

> Polecenia uruchamiaj jako `root`.
> **[TEST]** – tylko na serwerze testowym (budowanie).
> **[PROD]** – tylko na produkcji (instalacja gotowej paczki).
> Pozostałe kroki – na obu serwerach.
>
> Kopiuj polecenia z pliku otwartego jako **zwykły tekst** (np. `less` na serwerze), a nie z przeglądarki, Teams czy Outlooka — te narzędzia zamieniają `'` na `%27`.

---

## 0. Przygotowanie i kopia zapasowa

Zrób **snapshot maszyny**. To najszybszy sposób na powrót, gdyby coś poszło nie tak.

```bash
mkdir -p /root/php74-migracja && cd /root/php74-migracja
php -v                         > php72-version.txt   # wersja PHP
php -m                         > php72-modules.txt   # rozszerzenia – nowe PHP będzie miało identyczne
php --ini                      > php72-ini.txt       # które pliki .ini są ładowane
rpm -qa | grep -i php | sort   > php72-rpms.txt      # paczki PHP (remi)
httpd -V                       > httpd-V.txt         # wersja Apache i MPM
httpd -M                       > httpd-modules.txt   # moduły Apache

tar czf /root/php74-migracja/backup-etc-$(date +%F).tgz /etc/httpd /etc/php.ini /etc/php.d
```

Sprawdzenie trzech rzeczy, na których opiera się ta instrukcja:

```bash
httpd -V | grep -i 'Server MPM'                    # musi być: prefork
grep -Rn 'php7_module' /etc/httpd/conf.modules.d/  # plik z LoadModule – zwykle 15-php.conf (remi)
ls -l /usr/lib64/httpd/modules/libphp7.so          # moduł PHP 7.2 z remi
```

Jeśli `LoadModule php7_module` jest w innym pliku niż `15-php.conf`, użyj tej nazwy w krokach 8 i 11.

### Rozszerzenia działające w Apache

`php -m` pokazuje rozszerzenia CLI. Sprawdzamy, czy Apache nie ładuje innych:

```bash
echo '<?php echo implode("\n", get_loaded_extensions()), "\n";' > /var/www/html/_ext.php
curl -s http://localhost/_ext.php | sort -f > /root/php74-migracja/php72-modules-apache.txt
rm -f /var/www/html/_ext.php                              # usuń stronę testową od razu
diff -i <(php -m | grep -v '^\[' | grep -v '^$' | sort -f) /root/php74-migracja/php72-modules-apache.txt
```

Oczekiwane różnice: `apache2handler` tylko po stronie Apache, a `pcntl` i `readline` tylko w CLI. Inne różnice dopisz do `configure` w kroku 5.
Jeśli `localhost` trafia na inny vhost, podmień adres na właściwą domenę.

---

## 1. Repozytoria yum (CentOS 7 jest EOL)

Procedura naprawy, gdy `yum` już zgłasza błędy: `KROK1-NAPRAWA-EPEL.md`.

```bash
echo "7.9.2009" > /etc/yum/vars/releasever      # stała wersja wydania (vault nie ma katalogu "7")

sed -i -e 's|^mirrorlist=|#mirrorlist=|g' \
       -e 's|^#\s*baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' \
       /etc/yum.repos.d/CentOS-*.repo          # repozytoria CentOS -> archiwum vault

yum clean all && yum makecache                 # nie może być błędów
yum repolist enabled
```

EPEL **nie jest potrzebny** przy tym zestawie rozszerzeń. Jeśli `epel.repo` jest na serwerze i powoduje błędy, napraw go według `KROK1-NAPRAWA-EPEL.md` albo wyłącz: `yum-config-manager --disable epel`.

> **Nie uruchamiaj `yum update` na całym systemie.** Z repozytorium `remi-php72` zaktualizowałoby się obecne PHP 7.2.
> Instaluj tylko pakiety wskazane w krokach.

---

## 2. [TEST] Narzędzia i biblioteki do kompilacji

```bash
yum -y install gcc make autoconf automake libtool re2c pkgconfig git patch \
    httpd-devel libxml2-devel openssl-devel zlib-devel libcurl-devel \
    bzip2-devel readline-devel gettext-devel
```

| Pakiet | Do czego |
|---|---|
| `gcc make autoconf automake libtool` | kompilator i narzędzia budowania |
| `re2c`, bison (krok 3) | generatory parsera i leksera, wymagane przy budowaniu z gita |
| `git` | pobranie źródeł z gałęzi |
| `httpd-devel` | `apxs` i nagłówki Apache – bez tego nie zbuduje się moduł `libphp7.so` |
| `libxml2-devel openssl-devel zlib-devel libcurl-devel` | libxml, openssl, zlib, curl |
| `bzip2-devel readline-devel gettext-devel` | bz2, readline, gettext |

Te paczki instalujemy **tylko na serwerze testowym**. Na produkcję trafia gotowa paczka.

---

## 3. [TEST] Bison 3.x

CentOS 7 ma bison 2.7, a PHP 7.4 z gita wymaga ≥ 3.0. Instalujemy do `/usr/local`, nie ruszając systemowego:

```bash
cd /usr/local/src
curl -fsSLO https://ftp.gnu.org/gnu/bison/bison-3.0.5.tar.xz
tar xJf bison-3.0.5.tar.xz && cd bison-3.0.5
./configure --prefix=/usr/local && make -j"$(nproc)" && make install
hash -r && bison --version | head -1    # musi pokazać 3.0.5
```

---

## 4. [TEST] Pobranie źródeł PHP z łatką

```bash
cd /usr/local/src
git clone --depth 1 --branch PHP-7.4-CVE-2026-109618-109619 \
    https://github.com/php/php-src.git php-7.4-patched
cd php-7.4-patched
git log -1 --format='%H %s'
```

Oczekiwany wynik:
`712e60f9edfd03f0960fc4fc3c2c375f42b90aa2 Avoid state corruption via bailout`.
Inny hash oznacza, że gałąź się zmieniła — przeczytaj nowe commity przed dalszymi krokami.

---

## 5. [TEST] Konfiguracja, kompilacja, testy, instalacja

Zestaw rozszerzeń jest **identyczny jak w PHP 7.2** na tym serwerze (porównanie: `KROK5-ROZSZERZENIA.md`).

```bash
cd /usr/local/src/php-7.4-patched
./buildconf --force     # generuje ./configure (wymagane przy źródłach z gita)

./configure \
  --prefix=/opt/php-7.4-patched \
  --with-config-file-path=/opt/php-7.4-patched/etc \
  --with-config-file-scan-dir=/opt/php-7.4-patched/etc/conf.d \
  --with-apxs2=/usr/bin/apxs \
  --with-openssl --with-zlib --with-curl --with-bz2 \
  --enable-calendar --enable-exif --enable-ftp --with-gettext \
  --enable-sockets --enable-pcntl --with-readline \
  --enable-opcache \
  --disable-dom --disable-simplexml --disable-xml --disable-xmlreader --disable-xmlwriter \
  --disable-pdo --without-pdo-sqlite --without-sqlite3 \
  --disable-posix --disable-mbstring
```

| Opcja | Znaczenie |
|---|---|
| `--prefix=/opt/php-7.4-patched` | CLI, nagłówki i konfiguracja w osobnym katalogu |
| `--with-config-file-path` / `-scan-dir` | moduł czyta `/opt/php-7.4-patched/etc/php.ini`, a nie `/etc/php.ini` |
| `--with-apxs2=/usr/bin/apxs` | buduje moduł Apache (mod_php), jak obecne PHP 7.2 |
| `--with-*` / `--enable-*` | rozszerzenia obecne w 7.2: openssl, zlib, curl, bz2, calendar, exif, ftp, gettext, sockets, pcntl, readline |
| `--enable-opcache` | buduje `opcache.so`, ale go **nie włącza** (7.2 działa bez opcache) |
| `--disable-*` / `--without-*` | wyłącza rozszerzenia domyślnie włączone w 7.4, których nie ma w 7.2 |

Na końcu `configure` musi być `Thank you for using PHP.`, bez linii `error:`.

```bash
make -j"$(nproc)"       # kompilacja, kilka minut; wynik: libs/libphp7.so i sapi/cli/php

# testy obszarów zmienionych przez łatkę (ok. 1 min)
TEST_PHP_EXECUTABLE=sapi/cli/php sapi/cli/php run-tests.php -j"$(nproc)" -q \
    -d opcache.enable_cli=0 Zend/tests ext/session/tests tests/basic tests/lang
```

Oczekiwane FAIL to wyłącznie `ext/session/tests/rfc1867*` (8 testów) i `tests/lang/bug45392.phpt`. Wynikają z zamierzonych zmian łatki: wyłączenia `session.upload_progress` i zmiany formatu komunikatu o braku pamięci.

Może pojawić się jeszcze `tests/basic/bug67198.phpt` z komunikatem `Server is not accepting connections after 6 seconds`. Ten test uruchamia wbudowany serwer HTTP PHP i zawodzi, gdy port jest zajęty albo serwer wstaje za wolno. Sprawdziłem go na kompilacji z łatką i bez niej — zawodzi tak samo w obu, więc **nie ma związku z łatką**.

Jeśli zobaczysz inny nieudany test, sprawdź go pojedynczo (bez `-j`), a w razie potrzeby porównaj z kompilacją gałęzi `PHP-7.4` bez łatki.

### Instalacja — **nie** używaj samego `make install`

Przy `--with-apxs2` polecenie `make install` **nadpisałoby** `/usr/lib64/httpd/modules/libphp7.so`, czyli moduł PHP 7.2 z remi, i zmodyfikowałoby `httpd.conf`. Instalujemy więc części osobno:

```bash
# CLI, opcache.so, nagłówki, phpize/php-config, phar -> /opt/php-7.4-patched
make install-cli install-modules install-build install-headers install-programs install-pharcmd

# moduł Apache pod WŁASNĄ nazwą, obok modułu 7.2
install -m 755 libs/libphp7.so /usr/lib64/httpd/modules/libphp74-patched.so
restorecon -v /usr/lib64/httpd/modules/libphp74-patched.so   # etykieta SELinux httpd_modules_t

# kontrola
/opt/php-7.4-patched/bin/php -v                              # PHP 7.4.34-dev
diff <(php -m | sort -f) <(/opt/php-7.4-patched/bin/php -m | sort -f) && echo "IDENTYCZNE"
ls -l /usr/lib64/httpd/modules/libphp7.so /usr/lib64/httpd/modules/libphp74-patched.so   # oba pliki istnieją
```

### Paczka na produkcję

Dzięki niej na produkcji nie trzeba instalować kompilatorów. Zrób ją **przed** krokiem 6, wtedy nie zawiera konfiguracji z testu:

```bash
tar czf /root/php-7.4-patched-centos7.tgz \
    -C / opt/php-7.4-patched usr/lib64/httpd/modules/libphp74-patched.so
sha256sum /root/php-7.4-patched-centos7.tgz > /root/php-7.4-patched-centos7.tgz.sha256
tar tzf /root/php-7.4-patched-centos7.tgz | grep -E 'libphp74|bin/php$'    # kontrola zawartości
```

---

## 5P. [PROD] Instalacja gotowej paczki

```bash
# skopiuj oba pliki z serwera testowego do /root (scp/rsync), następnie:
cd /root && sha256sum -c php-7.4-patched-centos7.tgz.sha256   # musi być: OK
tar xzf php-7.4-patched-centos7.tgz -C /                       # -> /opt/php-7.4-patched i moduł Apache
restorecon -Rv /usr/lib64/httpd/modules/libphp74-patched.so /opt/php-7.4-patched

# biblioteki uruchomieniowe (zwykle już są w systemie)
yum -y install openssl-libs zlib libcurl bzip2-libs readline libxml2 ncurses-libs

# czy wszystkie biblioteki są dostępne – wynik musi być PUSTY
ldd /usr/lib64/httpd/modules/libphp74-patched.so /opt/php-7.4-patched/bin/php | grep 'not found'
/opt/php-7.4-patched/bin/php -v
```

---

## 6. php.ini dla PHP 7.4

Punkt wyjścia to obecny `/etc/php.ini` z PHP 7.2, żeby zachować limity, strefę czasową, `upload_max_filesize` itd.:

```bash
mkdir -p /opt/php-7.4-patched/etc/conf.d
cp /etc/php.ini /opt/php-7.4-patched/etc/php.ini

# zakomentowanie wpisów ładujących rozszerzenia – 7.4 ma je wkompilowane, a pliki .so od 7.2 nie zadziałają
sed -i 's/^\s*extension\s*=/;&/; s/^\s*zend_extension\s*=/;&/' /opt/php-7.4-patched/etc/php.ini

# kontrola – nie może być ostrzeżeń "Unable to load dynamic library"
/opt/php-7.4-patched/bin/php -c /opt/php-7.4-patched/etc/php.ini -r 'echo "OK\n";'
```

Opcache **nie jest** włączany, bo PHP 7.2 na tym serwerze działa bez niego. W `conf.d/` nie tworzymy żadnych plików.

Czego **nie trzeba** zmieniać, bo mod_php 7.4 to rozumie tak samo jak 7.2:

- `/etc/httpd/conf.d/php.conf` z remi (`SetHandler application/x-httpd-php`, `php_value session.save_path` itd.),
- `php_value` / `php_flag` w vhostach i `.htaccess`.

Wartości w `/opt/php-7.4-patched/etc/php.ini` do przejrzenia:

| Ustawienie | Uwagi |
|---|---|
| `session.upload_progress.enabled` | **łatka wyłącza tę funkcję na stałe**, niezależnie od ustawienia |
| `max_multipart_body_parts` | nowe ustawienie z łatki. Domyślnie `-1`, czyli `max_input_vars + max_file_uploads`. Zwykle zostaw domyślne. |
| `error_log`, `date.timezone`, `memory_limit` | przeniesione z 7.2 – sprawdź, czy pasują |

---

## 7. SELinux

```bash
getenforce
ls -Z /usr/lib64/httpd/modules/libphp74-patched.so   # powinno być: httpd_modules_t
```

Jeśli etykieta jest inna, uruchom `restorecon -v /usr/lib64/httpd/modules/libphp74-patched.so`.
Dla mod_php nie trzeba otwierać portów ani dodawać reguł SELinux.

---

## 8. Przełączenie Apache z PHP 7.2 na PHP 7.4

> Na **produkcji** zrób to w oknie serwisowym. Wymagany jest **pełny restart** Apache (kilka sekund przerwy).

> ⚠️ **Użyj `systemctl restart httpd`, nigdy `reload`, `graceful` ani `httpd -k restart`.**
> Przy przeładowaniu Apache odłącza i ponownie ładuje moduł w istniejącym procesie, a mod_php tego nie przeżywa —
> efektem są błędy `child pid NNN exit signal Segmentation fault (11)` i brak odpowiedzi strony.
> Sprawdziłem to na środowisku testowym: po `httpd -k restart` każde żądanie kończyło się segfaultem,
> a po pełnym restarcie procesu wszystko działa poprawnie.

```bash
# kopia obecnego pliku z LoadModule (nazwa wg kroku 0)
cp -a /etc/httpd/conf.modules.d/15-php.conf /root/php74-migracja/15-php.conf.php72

cat /etc/httpd/conf.modules.d/15-php.conf
# oczekiwane (remi):
#   <IfModule prefork.c>
#     LoadModule php7_module modules/libphp7.so
#   </IfModule>

# podmiana ścieżki modułu na wersję 7.4 z łatką
sed -i 's|modules/libphp7\.so|modules/libphp74-patched.so|' /etc/httpd/conf.modules.d/15-php.conf
grep -n 'php7_module' /etc/httpd/conf.modules.d/15-php.conf   # musi wskazywać libphp74-patched.so

httpd -t                      # musi być "Syntax OK"
systemctl restart httpd       # PEŁNY restart, nie reload
systemctl status httpd --no-pager
```

Jeśli `httpd -t` zgłosi błąd, **nie restartuj**. Przywróć plik:
`cp -a /root/php74-migracja/15-php.conf.php72 /etc/httpd/conf.modules.d/15-php.conf`.

W logu po starcie powinna pojawić się linia:
`Apache/2.4.6 (CentOS) PHP/7.4.34-dev configured -- resuming normal operations`.

---

## 9. Weryfikacja

```bash
# wersja PHP w Apache (tymczasowa strona – USUŃ po teście)
echo '<?php echo PHP_VERSION," ",PHP_SAPI," ",php_ini_loaded_file(),"\n";' > /var/www/html/_ver.php
curl -s http://localhost/_ver.php
# oczekiwane: 7.4.34-dev apache2handler /opt/php-7.4-patched/etc/php.ini

# czy łatka jest aktywna – to ustawienie istnieje tylko w wersji z łatką
echo '<?php var_dump(ini_get("max_multipart_body_parts"));' > /var/www/html/_p.php
curl -s http://localhost/_p.php            # oczekiwane: string(2) "-1"

# rozszerzenia w Apache – porównanie z 7.2 (krok 0)
echo '<?php echo implode("\n", get_loaded_extensions()), "\n";' > /var/www/html/_ext.php
diff -i <(curl -s http://localhost/_ext.php | sort -f) /root/php74-migracja/php72-modules-apache.txt && echo "IDENTYCZNE"

rm -f /var/www/html/_ver.php /var/www/html/_p.php /var/www/html/_ext.php

# logi – błędy PHP, segfaulty, "Unable to load"
tail -n 50 /var/log/httpd/error_log
```

Do sprawdzenia w aplikacji, najpierw na serwerze **testowym**:

- logowanie i sesje,
- upload plików, także wielu naraz i dużych,
- formularze z dużą liczbą pól (`max_input_vars` / `max_multipart_body_parts`),
- logi pod kątem `Deprecated` / `Warning` / `Fatal`, czyli zmian między PHP 7.2 a 7.4,
- czy aplikacja nie korzysta z paska postępu uploadu przez sesję (`session.upload_progress`), który łatka wyłącza.

Przez kilka dni po wdrożeniu obserwuj `error_log` pod kątem `exit signal Segmentation fault`.

---

## 10. PHP CLI i cron

Polecenie `php` (`/usr/bin/php` z remi) **nadal uruchamia 7.2**, podobnie cron i skrypty konsolowe. Podatność dotyczy obsługi żądań HTTP, ale docelowo warto przenieść też CLI:

```bash
grep -Rn 'php' /etc/crontab /etc/cron.d/ /var/spool/cron/ 2>/dev/null   # gdzie cron używa php

/opt/php-7.4-patched/bin/php /sciezka/do/skryptu.php                     # jawne wywołanie 7.4
```

Opcjonalnie, po testach, możesz podmienić domyślne `php` — `/usr/local/bin` ma pierwszeństwo przed `/usr/bin`:

```bash
ln -s /opt/php-7.4-patched/bin/php /usr/local/bin/php && hash -r && php -v
```

CLI 7.4 czyta `/opt/php-7.4-patched/etc/php.ini` z kroku 6.

---

## 11. Powrót do PHP 7.2 (rollback)

```bash
cp -a /root/php74-migracja/15-php.conf.php72 /etc/httpd/conf.modules.d/15-php.conf   # LoadModule -> libphp7.so (7.2)
httpd -t && systemctl restart httpd        # znowu PEŁNY restart
curl -s http://localhost/ >/dev/null && tail -n 5 /var/log/httpd/error_log
rm -f /usr/local/bin/php                   # jeśli w kroku 10 podmieniono CLI
```

Moduł 7.2, `/etc/php.ini` i `/etc/php.d/` nie były zmieniane, więc powrót jest natychmiastowy.

---

## Skrót kolejności

| # | Test | Prod |
|---|---|---|
| 0 | snapshot, inwentaryzacja | to samo |
| 1 | repozytoria (vault) | to samo |
| 2–5 | kompilacja, testy, paczka `.tgz` | **5P**: rozpakowanie paczki |
| 6–7 | php.ini, SELinux | to samo |
| 8–9 | podmiana modułu, restart, testy aplikacji | to samo, w oknie serwisowym |
| 10 | CLI i cron (opcjonalnie) | to samo |
| 11 | rollback w razie problemów | to samo |

---

## Sprawdzone na środowisku testowym (2026-10-26)

CentOS 7.9 + Apache 2.4.6 (prefork) + PHP 7.4.34-dev z gałęzi z łatką, zbudowane jako mod_php:

| Sprawdzenie | Wynik |
|---|---|
| `configure` + `make` z flagami z kroku 5 | OK |
| instalacja bez nadpisania `libphp7.so` (7.2) | OK, oba moduły obok siebie |
| start Apache z nowym modułem | `Apache/2.4.6 (CentOS) PHP/7.4.34-dev` |
| `PHP_SAPI` / wczytany `php.ini` | `apache2handler`, `/opt/php-7.4-patched/etc/php.ini` |
| sesje, upload pojedynczy i tablicowy, `$_GET`/`$_POST`, duże tablice, alokator | wszystko OK |
| nowe `max_multipart_body_parts` | `-1` (łatka aktywna) |
| rozszerzenia Apache vs CLI | zgodne (różnica tylko `apache2handler`, `pcntl`, `readline`) |
| `httpd -k restart` / `reload` | **segfault** — dlatego w kroku 8 jest `systemctl restart` |

