# Przebudowa PHP 7.4 jako moduł Apache (mod_php)

**Kiedy:** PHP 7.4 jest już zainstalowane w `/opt/php-7.4-patched`, ale zbudowane z php-fpm i z ogólnym zestawem rozszerzeń (gd, intl, mbstring, PDO itd.).
**Cel:** zbudować je od nowa jako **moduł Apache**, z rozszerzeniami identycznymi jak w PHP 7.2.

Obecne PHP 7.2 i Apache **nie są** dotykane — działają przez cały czas przebudowy.

---

## 1. Sprawdź, co już jest na serwerze

```bash
ls /opt/php-7.4-patched/sbin/php-fpm 2>/dev/null && echo "(build z php-fpm – do przebudowy)"
ls /opt/php-7.4-patched/etc/ 2>/dev/null                     # czy jest już konfiguracja z kroku 6
systemctl is-active php74-fpm 2>/dev/null                    # czy utworzono usługę php-fpm
ls /etc/httpd/conf.d/php74-fpm.conf 2>/dev/null              # czy Apache był przełączany na fpm
httpd -M 2>/dev/null | grep -i php                           # obecny moduł PHP w Apache
```

Dalsze kroki wykonaj w kolejności, pomijając te, które Cię nie dotyczą.

---

## 2. Cofnięcie tego, co dotyczyło php-fpm

```bash
# 2.1 Apache z powrotem na mod_php 7.2 (jeśli był przełączony na fpm)
if [ -f /etc/httpd/conf.d/php74-fpm.conf ]; then
  mv /etc/httpd/conf.d/php74-fpm.conf /root/php74-migracja/php74-fpm.conf.saved
  # przywróć pliki mod_php 7.2 (nazwa pliku wg Twojego serwera: 10- lub 15-)
  [ -f /etc/httpd/conf.modules.d/15-php.conf.disabled ] && mv /etc/httpd/conf.modules.d/15-php.conf.disabled /etc/httpd/conf.modules.d/15-php.conf
  [ -f /etc/httpd/conf.d/php.conf.disabled ] && mv /etc/httpd/conf.d/php.conf.disabled /etc/httpd/conf.d/php.conf
  httpd -t && systemctl restart httpd        # strona znowu działa na PHP 7.2
fi

# 2.2 usunięcie usługi php-fpm 7.4 (jeśli powstała)
if systemctl list-unit-files | grep -q '^php74-fpm'; then
  systemctl disable --now php74-fpm
  rm -f /etc/systemd/system/php74-fpm.service /etc/logrotate.d/php74-fpm
  systemctl daemon-reload
fi

# 2.3 reguła SELinux dla portu 9074 – już niepotrzebna
semanage port -d -t http_port_t -p tcp 9074 2>/dev/null

# kontrola: strona działa na 7.2
httpd -M 2>/dev/null | grep -i php
curl -s -o /dev/null http://localhost/ && echo "Apache odpowiada"
```

---

## 3. Przebudowa PHP 7.4 jako mod_php

```bash
cd /usr/local/src/php-7.4-patched

# 3.1 apxs i nagłówki Apache (bez tego nie zbuduje się moduł) + biblioteki rozszerzeń
yum -y install httpd-devel bzip2-devel readline-devel gettext-devel

# 3.2 kopia konfiguracji z kroku 6, jeśli była robiona
[ -d /opt/php-7.4-patched/etc ] && cp -a /opt/php-7.4-patched/etc /root/php74-migracja/php74-etc-backup

# 3.3 usunięcie poprzedniej kompilacji i instalacji
make distclean
rm -rf /opt/php-7.4-patched

# 3.4 configure – mod_php + rozszerzenia jak w 7.2
./buildconf --force

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

Na końcu `configure` musi być `Thank you for using PHP.`, bez linii `error:`.

```bash
# 3.5 kompilacja
make -j"$(nproc)"

# 3.6 testy obszarów zmienionych przez łatkę (ok. 1 min)
TEST_PHP_EXECUTABLE=sapi/cli/php sapi/cli/php run-tests.php -j"$(nproc)" -q \
    -d opcache.enable_cli=0 Zend/tests ext/session/tests tests/basic tests/lang
```

Oczekiwane FAIL to wyłącznie `ext/session/tests/rfc1867*` (8 testów) i `tests/lang/bug45392.phpt`.

```bash
# 3.7 instalacja – NIE używaj samego "make install", bo nadpisze moduł PHP 7.2
make install-cli install-modules install-build install-headers install-programs install-pharcmd
install -m 755 libs/libphp7.so /usr/lib64/httpd/modules/libphp74-patched.so
restorecon -v /usr/lib64/httpd/modules/libphp74-patched.so

# 3.8 kontrola
/opt/php-7.4-patched/bin/php -v
diff <(php -m | sort -f) <(/opt/php-7.4-patched/bin/php -m | sort -f) && echo "IDENTYCZNE"
ls -l /usr/lib64/httpd/modules/libphp7.so /usr/lib64/httpd/modules/libphp74-patched.so
```

---

## 4. php.ini

```bash
mkdir -p /opt/php-7.4-patched/etc/conf.d
cp /etc/php.ini /opt/php-7.4-patched/etc/php.ini
sed -i 's/^\s*extension\s*=/;&/; s/^\s*zend_extension\s*=/;&/' /opt/php-7.4-patched/etc/php.ini
/opt/php-7.4-patched/bin/php -c /opt/php-7.4-patched/etc/php.ini -r 'echo "OK\n";'
```

Jeśli w kroku 2.2 zachowałeś stary `php.ini` 7.4 i wprowadzałeś w nim własne zmiany, przenieś je ręcznie z `/root/php74-migracja/php74-etc-backup/php.ini`.
Pliki `php-fpm.conf` i `php-fpm.d/` z backupu są już niepotrzebne.

---

## 5. Dalej

Przejdź do **kroku 7** (SELinux) i **8** (podmiana `LoadModule` + `systemctl restart httpd`) w `WDROZENIE.md`.

Jeśli paczka `.tgz` na produkcję była już zrobiona, utwórz ją **od nowa** — stara zawiera build z php-fpm:

```bash
rm -f /root/php-7.4-patched-centos7.tgz /root/php-7.4-patched-centos7.tgz.sha256
tar czf /root/php-7.4-patched-centos7.tgz \
    -C / opt/php-7.4-patched usr/lib64/httpd/modules/libphp74-patched.so
sha256sum /root/php-7.4-patched-centos7.tgz > /root/php-7.4-patched-centos7.tgz.sha256
```

