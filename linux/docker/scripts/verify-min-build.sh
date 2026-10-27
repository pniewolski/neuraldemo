#!/bin/bash
# Weryfikacja configure z KROK5-ROZSZERZENIA.md (zestaw rozszerzeń jak PHP 7.2 na serwerze).
set -e
yum -y -q install bzip2-devel readline-devel gettext-devel >/dev/null
rm -rf /usr/local/src/php-min && cp -a /usr/local/src/php-build-php-7.4-patched /usr/local/src/php-min
cd /usr/local/src/php-min
make distclean >/dev/null 2>&1 || true
./buildconf --force >/dev/null 2>&1
./configure \
  --prefix=/opt/php-7.4-min \
  --with-config-file-path=/opt/php-7.4-min/etc \
  --with-config-file-scan-dir=/opt/php-7.4-min/etc/conf.d \
  --enable-fpm --with-fpm-user=apache --with-fpm-group=apache \
  --with-openssl --with-zlib --with-curl --with-bz2 \
  --enable-calendar --enable-exif --enable-ftp --with-gettext \
  --enable-sockets --enable-pcntl --with-readline \
  --enable-opcache \
  --disable-dom --disable-simplexml --disable-xml --disable-xmlreader --disable-xmlwriter \
  --disable-pdo --without-pdo-sqlite --without-sqlite3 \
  --disable-posix --disable-mbstring > configure.log 2>&1 || { tail -30 configure.log; exit 1; }
grep -q 'Thank you for using PHP' configure.log && echo "CONFIGURE OK"
make -j"$(nproc)" > make.log 2>&1 || { tail -40 make.log; exit 1; }
echo "MAKE OK"
make install > install.log 2>&1
cat > /tmp/php72-modules.txt <<'EOF'
[PHP Modules]
bz2
calendar
Core
ctype
curl
date
exif
fileinfo
filter
ftp
gettext
hash
iconv
json
libxml
openssl
pcntl
pcre
Phar
readline
Reflection
session
sockets
SPL
standard
tokenizer
zlib

[Zend Modules]

EOF
if diff <(sort -f /tmp/php72-modules.txt) <(/opt/php-7.4-min/bin/php -m | sort -f); then echo "MODULES IDENTYCZNE"; fi
ldd /opt/php-7.4-min/sbin/php-fpm | awk '{print $1}' | sort | tr '\n' ' '; echo

