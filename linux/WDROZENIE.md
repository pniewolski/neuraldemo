# Wdrożenie PHP 7.4 z łatką CVE-2026-109618 / CVE-2026-109619 na CentOS 7

Instrukcja dla serwera **testowego**, a potem **produkcyjnego**. Zakładany stan serwera:
CentOS 7 (Core), Apache 2.4.6 z paczek systemowych, PHP 7.2.22.

Docelowo:

- PHP z gałęzi `PHP-7.4-CVE-2026-109618-109619` instalujemy **obok** PHP 7.2, w `/opt/php-7.4-patched`.
- Apache obsługuje pliki `.php` przez **php-fpm** (`mod_proxy_fcgi`, `127.0.0.1:9074`).
- PHP 7.2 zostaje na dysku. Powrót do niego to zmiana jednego pliku i `reload` Apache.

> Wszystkie polecenia uruchamiaj jako `root` (albo przez `sudo`).
> Kroki oznaczone **[TEST]** wykonujesz tylko na serwerze testowym (budowanie).
> Kroki oznaczone **[PROD]** wykonujesz tylko na produkcji (instalacja gotowej paczki).
> Pozostałe kroki wykonujesz na obu serwerach.

---

## 0. Przygotowanie i kopia zapasowa

```bash
# Zrób snapshot maszyny (VMware/Proxmox/Hyper-V/chmura) – najszybszy sposób na rollback.

# Zapisz informacje o obecnym PHP i Apache (przydadzą się do porównania i odtworzenia)
mkdir -p /root/php74-migracja && cd /root/php74-migracja
php -v                         > php72-version.txt   # wersja PHP CLI
php -m                         > php72-modules.txt   # lista rozszerzeń – nowe PHP musi mieć te same
php -i | grep -i 'configure'   > php72-configure.txt # flagi kompilacji (jeśli PHP było budowane ze źródeł)
php --ini                      > php72-ini.txt       # które pliki php.ini są ładowane
rpm -qa | grep -i php | sort   > php72-rpms.txt      # czy PHP jest z paczek (np. remi/ius/webtatic)
httpd -V                       > httpd-V.txt         # wersja i MPM Apache (prefork/worker/event)
httpd -M                       > httpd-modules.txt   # załadowane moduły Apache

# Kopia konfiguracji Apache i PHP
tar czf /root/php74-migracja/backup-etc-$(date +%F).tgz /etc/httpd /etc/php.ini /etc/php.d 2>/dev/null
```

Sprawdź, **jak dziś działa PHP 7.2** w Apache:

```bash
httpd -M 2>/dev/null | grep -i php     # "php7_module" => mod_php (PHP wbudowane w Apache)
systemctl list-units | grep -i fpm     # jeśli jest np. php-fpm.service => PHP już działa przez FPM
grep -Ri 'proxy:fcgi\|php7_module\|AddHandler.*php' /etc/httpd/ # gdzie jest konfiguracja PHP w Apache
```

Dalsza instrukcja zakłada **mod_php**, czyli najczęstszy wariant. Jeśli serwer już używa FPM, w kroku 8 zmieniasz tylko port w `SetHandler`.

### Dyrektywy `php_value` / `php_flag`

Po przejściu z mod_php na FPM dyrektywy `php_value`, `php_flag`, `php_admin_value` i `php_admin_flag` w konfiguracji Apache i w `.htaccess` powodują **błąd 500**. Wyszukaj je wcześniej:

```bash
grep -Rn 'php_value\|php_flag\|php_admin' /etc/httpd/ /var/www/ --include='*.conf' --include='.htaccess'
```

Każde trafienie trzeba przenieść:

- dla całego serwera: do `/opt/php-7.4-patched/etc/php-fpm.d/www.conf` jako `php_admin_value[...]` (krok 6),
- dla katalogu: do pliku `.user.ini` w tym katalogu (składnia php.ini).

---

## 1. Repozytoria yum (CentOS 7 jest EOL)

Od lipca 2024 `mirror.centos.org` nie działa. Jeśli `yum` zgłasza błędy, przełącz repozytoria na archiwum:

```bash
# Ustaw stałą wersję wydania (vault nie ma katalogu "7")
echo "7.9.2009" > /etc/yum/vars/releasever

# mirrorlist -> wyłączony, baseurl -> vault.centos.org
sed -i -e 's|^mirrorlist=|#mirrorlist=|g' \
       -e 's|^#\s*baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' \
       /etc/yum.repos.d/CentOS-*.repo

# EPEL (potrzebny dla oniguruma = mbstring w PHP 7.4)
yum -y install epel-release
sed -i -e 's|^metalink=|#metalink=|g' \
       -e 's|^#\s*baseurl=http://download.fedoraproject.org/pub/epel/7|baseurl=https://dl.fedoraproject.org/pub/archive/epel/7|g' \
       /etc/yum.repos.d/epel*.repo

yum clean all && yum makecache   # odświeżenie metadanych – nie może być błędów
```

---

## 2. [TEST] Narzędzia i biblioteki do kompilacji

```bash
yum -y install gcc gcc-c++ make autoconf automake libtool re2c pkgconfig git patch \
    libxml2-devel openssl-devel zlib-devel libcurl-devel libicu-devel \
    libpng-devel libjpeg-turbo-devel freetype-devel sqlite-devel \
    oniguruma-devel libxslt-devel
```

| Pakiet | Do czego |
|---|---|
| `gcc gcc-c++ make autoconf automake libtool` | kompilator i narzędzia budowania (`gcc-c++` dla ext/intl) |
| `re2c`, bison (krok 3) | generatory parsera/leksera – wymagane przy budowaniu z gita |
| `git` | pobranie źródeł z gałęzi |
| `*-devel` | nagłówki bibliotek dla rozszerzeń: xml, openssl, zlib, curl, intl, gd, sqlite, mbstring, xsl |

Jeśli `php72-modules.txt` z kroku 0 zawiera rozszerzenia, których tu nie ma (np. `ldap`, `pgsql`, `imap`, `bz2`, `gmp`), doinstaluj ich paczki `-devel` i dodaj flagi w kroku 5.

## 3. [TEST] Bison 3.x

CentOS 7 ma bison 2.7, a PHP 7.4 budowane z gita wymaga wersji ≥ 3.0. Instalujemy go do `/usr/local`, nie ruszając systemowego:

```bash
cd /usr/local/src
curl -fsSLO https://ftp.gnu.org/gnu/bison/bison-3.0.5.tar.xz   # pobranie źródeł
tar xJf bison-3.0.5.tar.xz && cd bison-3.0.5
./configure --prefix=/usr/local && make -j"$(nproc)" && make install
hash -r && bison --version | head -1    # musi pokazać 3.0.5 (/usr/local/bin jest w PATH przed /usr/bin)
```

---

## 4. [TEST] Pobranie źródeł PHP z łatką

```bash
cd /usr/local/src
git clone --depth 1 --branch PHP-7.4-CVE-2026-109618-109619 \
    https://github.com/php/php-src.git php-7.4-patched     # tylko ta gałąź, bez historii
cd php-7.4-patched
git log -1 --format='%H %s'
```

Weryfikacja: oczekiwany wynik to
`712e60f9edfd03f0960fc4fc3c2c375f42b90aa2 Avoid state corruption via bailout`.
Inny hash oznacza, że gałąź się zmieniła. Wtedy przed dalszymi krokami przeczytaj nowe commity.

```bash
./buildconf --force    # generuje skrypt ./configure (wymagany przy źródłach z gita)
```

---

## 5. [TEST] Konfiguracja, kompilacja, testy, instalacja

```bash
./configure \
  --prefix=/opt/php-7.4-patched \
  --with-config-file-path=/opt/php-7.4-patched/etc \
  --with-config-file-scan-dir=/opt/php-7.4-patched/etc/conf.d \
  --enable-fpm --with-fpm-user=apache --with-fpm-group=apache \
  --with-openssl --with-zlib --with-curl --with-xsl \
  --enable-mbstring --enable-intl --enable-soap --enable-bcmath \
  --enable-sockets --enable-opcache --enable-exif --enable-calendar \
  --with-mysqli=mysqlnd --with-pdo-mysql=mysqlnd --with-pdo-sqlite \
  --enable-gd --with-jpeg --with-freetype
```

| Opcja | Znaczenie |
|---|---|
| `--prefix=/opt/php-7.4-patched` | wszystko trafia do osobnego katalogu i nie nadpisuje PHP 7.2 |
| `--with-config-file-path` / `-scan-dir` | własny `php.ini` i `conf.d`, niezależne od `/etc/php.ini` |
| `--enable-fpm --with-fpm-user=apache` | buduje php-fpm, procesy działają jako użytkownik Apache |
| pozostałe | rozszerzenia; **porównaj z `php72-modules.txt`** i dodaj brakujące |

`ext/zip` w PHP 7.4 wymaga libzip ≥ 0.11, a CentOS 7 ma 0.10, więc rozszerzenie jest pominięte. Jeśli aplikacja go potrzebuje, trzeba zbudować nowszą libzip.

```bash
make -j"$(nproc)"     # kompilacja (kilka–kilkanaście minut)

# Testy obszarów zmienionych przez łatkę (ok. 1 min).
# Oczekiwane: 9 FAIL – 8x ext/session/tests/rfc1867* i tests/lang/bug45392 (zamierzone zmiany łatki).
TEST_PHP_EXECUTABLE=sapi/cli/php sapi/cli/php run-tests.php -j"$(nproc)" -q \
    -d opcache.enable_cli=0 Zend/tests ext/session/tests tests/basic tests/lang

make install          # instalacja do /opt/php-7.4-patched
/opt/php-7.4-patched/bin/php -v     # PHP 7.4.34-dev
/opt/php-7.4-patched/bin/php -m     # porównaj z php72-modules.txt
```

### Paczka na produkcję

Dzięki paczce na produkcji nie trzeba instalować kompilatorów:

```bash
tar czf /root/php-7.4-patched-centos7.tgz -C /opt php-7.4-patched
sha256sum /root/php-7.4-patched-centos7.tgz > /root/php-7.4-patched-centos7.tgz.sha256
```

---

## 5P. [PROD] Instalacja gotowej paczki

```bash
# skopiuj z serwera testowego (scp/rsync) oba pliki do /root, następnie:
cd /root && sha256sum -c php-7.4-patched-centos7.tgz.sha256    # integralność paczki – musi być OK
tar xzf php-7.4-patched-centos7.tgz -C /opt                     # rozpakowanie do /opt/php-7.4-patched

# biblioteki uruchomieniowe (bez -devel), m.in. oniguruma z EPEL
yum -y install libxml2 openssl-libs zlib libcurl libicu libpng libjpeg-turbo freetype \
    sqlite oniguruma libxslt

# czy wszystkie biblioteki są dostępne – wynik musi być PUSTY
ldd /opt/php-7.4-patched/sbin/php-fpm /opt/php-7.4-patched/bin/php | grep 'not found'
/opt/php-7.4-patched/bin/php -v
```

---

## 6. Konfiguracja PHP i php-fpm

### php.ini

Wyjdź od obecnej konfiguracji produkcyjnej, żeby zachować limity, strefę czasową, `upload_max_filesize` itd.:

```bash
mkdir -p /opt/php-7.4-patched/etc/conf.d /opt/php-7.4-patched/etc/php-fpm.d /var/log/php74-fpm
cp /etc/php.ini /opt/php-7.4-patched/etc/php.ini       # ścieżka wg php72-ini.txt
echo 'zend_extension=opcache.so' > /opt/php-7.4-patched/etc/conf.d/10-opcache.ini

# Usunięcie wpisów ładujących rozszerzenia 7.2 (są wkompilowane albo mają inne ścieżki)
sed -i 's/^\s*extension\s*=/;&/; s/^\s*zend_extension\s*=/;&/' /opt/php-7.4-patched/etc/php.ini

# Kontrola składni i czy nie ma ostrzeżeń przy starcie
/opt/php-7.4-patched/bin/php -c /opt/php-7.4-patched/etc/php.ini -r 'echo "OK\n";'
```

Wartości do sprawdzenia w `/opt/php-7.4-patched/etc/php.ini`:

| Ustawienie | Uwagi |
|---|---|
| `session.save_path` | ustaw na katalog, w którym są sesje 7.2 (zwykle `/var/lib/php/session`). Katalog musi należeć do `apache`, inaczej użytkownikom unieważnią się sesje. |
| `session.upload_progress.enabled` | **łatka wyłącza tę funkcję na stałe**, niezależnie od ustawienia |
| `max_multipart_body_parts` | nowe ustawienie z łatki. Domyślnie `-1` oznacza `max_input_vars + max_file_uploads`. Zwykle zostawiasz domyślną wartość. |
| `error_log` | np. `/var/log/php74-fpm/php-error.log` |

```bash
ls -ld /var/lib/php/session              # właściciel powinien być apache (lub grupa apache z prawem zapisu)
```

### php-fpm

```bash
cat > /opt/php-7.4-patched/etc/php-fpm.conf <<'EOF'
[global]
pid = /run/php74-fpm.pid
error_log = /var/log/php74-fpm/error.log
include = /opt/php-7.4-patched/etc/php-fpm.d/*.conf
EOF

cat > /opt/php-7.4-patched/etc/php-fpm.d/www.conf <<'EOF'
[www]
user = apache
group = apache
listen = 127.0.0.1:9074
listen.allowed_clients = 127.0.0.1

; liczba procesów – dobierz do RAM: max_children ≈ (RAM dla PHP) / (średnie zużycie procesu, np. 40–80 MB)
pm = dynamic
pm.max_children = 20
pm.start_servers = 4
pm.min_spare_servers = 2
pm.max_spare_servers = 6
pm.max_requests = 500

; czas życia żądania – powinien odpowiadać max_execution_time
request_terminate_timeout = 300
catch_workers_output = yes
php_admin_value[error_log] = /var/log/php74-fpm/www-error.log
php_admin_flag[log_errors] = on
; tu przenieś php_value/php_flag z konfiguracji Apache (krok 0), np.:
; php_admin_value[memory_limit] = 256M
EOF

chown apache:apache /var/log/php74-fpm
/opt/php-7.4-patched/sbin/php-fpm -t -y /opt/php-7.4-patched/etc/php-fpm.conf   # test konfiguracji FPM
```

---

## 7. Usługa systemd

```bash
cat > /etc/systemd/system/php74-fpm.service <<'EOF'
[Unit]
Description=PHP 7.4 (CVE-2026-109618/109619 patched) FastCGI Process Manager
After=network.target

[Service]
Type=simple
ExecStart=/opt/php-7.4-patched/sbin/php-fpm --nodaemonize -y /opt/php-7.4-patched/etc/php-fpm.conf
ExecReload=/bin/kill -USR2 $MAINPID
Restart=on-failure
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload                 # wczytanie nowego pliku usługi
systemctl enable --now php74-fpm        # start i autostart po restarcie serwera
systemctl status php74-fpm --no-pager   # musi być "active (running)"
ss -ltnp | grep 9074                    # FPM nasłuchuje na 127.0.0.1:9074
```

Uwaga do `PrivateTmp=true`: Apache z paczki też używa PrivateTmp, więc `/tmp` FPM i Apache są od siebie odseparowane. Jeśli aplikacja wymienia pliki przez `/tmp` z innymi procesami, usuń tę linię.

Rotacja logów:

```bash
cat > /etc/logrotate.d/php74-fpm <<'EOF'
/var/log/php74-fpm/*.log {
    weekly
    rotate 8
    missingok
    notifempty
    compress
    delaycompress
    postrotate
        /bin/systemctl reload php74-fpm >/dev/null 2>&1 || true
    endscript
}
EOF
```

---

## 8. SELinux

```bash
getenforce      # Enforcing / Permissive / Disabled
```

Jeśli wynik to `Enforcing`, Apache domyślnie nie może łączyć się z portem 9074:

```bash
yum -y install policycoreutils-python                   # dostarcza polecenie semanage
semanage port -a -t http_port_t -p tcp 9074             # pozwala httpd łączyć się z portem 9074
semanage port -l | grep -w 9074                         # weryfikacja
```

Po przełączeniu (krok 9) sprawdź odmowy:
`ausearch -m avc -ts recent | grep -i 'php\|9074'`. Wynik powinien być pusty.

---

## 9. Przełączenie Apache z mod_php 7.2 na php-fpm 7.4

> Na **produkcji** zrób to w oknie serwisowym. Przełączenie trwa sekundy, a `reload` nie zrywa trwających połączeń.

```bash
# 9.1 Wyłączenie mod_php 7.2 (pliki zostają z sufiksem .disabled – rollback = zmiana nazwy)
ls /etc/httpd/conf.modules.d/ | grep -i php           # zwykle 10-php.conf (albo 15-php.conf)
ls /etc/httpd/conf.d/ | grep -i php                   # zwykle php.conf
mv /etc/httpd/conf.modules.d/10-php.conf /etc/httpd/conf.modules.d/10-php.conf.disabled
mv /etc/httpd/conf.d/php.conf            /etc/httpd/conf.d/php.conf.disabled

# 9.2 Nowa obsługa .php przez FPM
cat > /etc/httpd/conf.d/php74-fpm.conf <<'EOF'
# PHP 7.4 (patched) przez php-fpm
DirectoryIndex index.php index.html

# przekazanie nagłówka Authorization (Basic/Bearer) do PHP – mod_php robił to sam
SetEnvIf Authorization "(.*)" HTTP_AUTHORIZATION=$1

<FilesMatch \.php$>
    SetHandler "proxy:fcgi://127.0.0.1:9074"
</FilesMatch>

# zgodne z request_terminate_timeout
ProxyTimeout 300

# blokada dostępu do plików konfiguracyjnych PHP
<Files ".user.ini">
    Require all denied
</Files>
EOF

# 9.3 Sprawdzenie, że wymagane moduły są załadowane (standardowo są w 00-proxy.conf)
httpd -M 2>/dev/null | grep -E 'proxy_module|proxy_fcgi_module'

# 9.4 Test składni i przeładowanie
httpd -t                    # musi być "Syntax OK"
systemctl reload httpd
```

Jeśli `php_value` / `php_flag` występowały w `<VirtualHost>` lub w `.htaccess`, przenieś je **przed** `reload` (krok 0 i 6). Inaczej strony zwrócą błąd 500.

---

## 10. Weryfikacja

```bash
# Tymczasowa strona testowa (USUŃ po teście!)
echo '<?php echo PHP_VERSION," ",PHP_SAPI,"\n";' > /var/www/html/_ver.php
curl -s http://localhost/_ver.php            # oczekiwane: 7.4.34-dev fpm-fcgi
rm -f /var/www/html/_ver.php

# Logi – szukamy błędów 500, "Primary script unknown", AH01071, AVC
tail -f /var/log/httpd/error_log /var/log/php74-fpm/*.log
```

Do sprawdzenia w aplikacji, najpierw na serwerze **testowym**:

- logowanie i sesje: czy użytkownicy nie są wylogowywani (`session.save_path`),
- upload plików, także wielu naraz i dużych,
- formularze z dużą liczbą pól (`max_input_vars` / `max_multipart_body_parts`),
- zadania i API z autoryzacją przez nagłówek `Authorization`,
- logi pod kątem `Deprecated` / `Fatal` – zmiany między PHP 7.2 a 7.4,
- czy aplikacja nie korzysta z paska postępu uploadu (`session.upload_progress`), który łatka wyłącza.

---

## 11. PHP CLI i cron

Polecenie `php` (`/usr/bin/php`) **nadal uruchamia 7.2**. To samo dotyczy crona i skryptów konsolowych. Podatność dotyczy obsługi żądań HTTP, ale docelowo warto przenieść także CLI:

```bash
crontab -l -u apache; ls /etc/cron.d/; grep -Rn 'bin/php' /etc/cron* /var/spool/cron 2>/dev/null   # gdzie używane jest php

# wersja 7.4 dla CLI wywoływana jawnie:
/opt/php-7.4-patched/bin/php /sciezka/do/skryptu.php
```

Opcjonalnie, po testach, możesz podmienić domyślne `php` na wersję 7.4. Ścieżka `/usr/local/bin` ma pierwszeństwo przed `/usr/bin`:

```bash
ln -s /opt/php-7.4-patched/bin/php /usr/local/bin/php && hash -r && php -v
```

---

## 12. Rollback do PHP 7.2

```bash
rm -f /etc/httpd/conf.d/php74-fpm.conf
mv /etc/httpd/conf.modules.d/10-php.conf.disabled /etc/httpd/conf.modules.d/10-php.conf
mv /etc/httpd/conf.d/php.conf.disabled            /etc/httpd/conf.d/php.conf
httpd -t && systemctl reload httpd                 # Apache znowu używa mod_php 7.2
systemctl disable --now php74-fpm                  # opcjonalnie – zatrzymanie FPM 7.4
rm -f /usr/local/bin/php                           # jeśli w kroku 11 podmieniono CLI
```

Rollback nie zmienia plików PHP 7.2 ani `/etc/php.ini`, bo przez cały czas pozostają nietknięte.

---

## Skrót kolejności

| # | Test | Prod |
|---|---|---|
| 0 | backup, inwentaryzacja, `php_value` | to samo |
| 1 | repozytoria vault + EPEL | to samo |
| 2–5 | kompilacja + testy + paczka `.tgz` | **5P**: rozpakowanie paczki + biblioteki runtime |
| 6–8 | php.ini, FPM, systemd, SELinux | to samo |
| 9–10 | przełączenie Apache + testy aplikacji | to samo, w oknie serwisowym |
| 11 | CLI/cron (opcjonalnie) | to samo |
| 12 | rollback w razie problemów | to samo |

