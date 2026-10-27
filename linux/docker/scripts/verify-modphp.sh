#!/bin/bash
# Weryfikacja wariantu mod_php: PHP 7.4 (łatka CVE) jako moduł Apache zamiast php-fpm.
set -e
yum -y -q install httpd-devel bzip2-devel readline-devel gettext-devel >/dev/null
echo "MPM: $(httpd -V 2>/dev/null | awk -F': *' '/Server MPM/{print $2}')"

SRC=/usr/local/src/php-mod
rm -rf $SRC && cp -a /usr/local/src/php-build-php-7.4-patched $SRC && cd $SRC
make distclean >/dev/null 2>&1 || true
./buildconf --force >/dev/null 2>&1
./configure \
  --prefix=/opt/php-7.4-mod \
  --with-config-file-path=/opt/php-7.4-mod/etc \
  --with-config-file-scan-dir=/opt/php-7.4-mod/etc/conf.d \
  --with-apxs2=/usr/bin/apxs \
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
ls -l libs/libphp7.so

# instalacja BEZ apxs (nie dotyka /usr/lib64/httpd/modules/libphp7.so ani httpd.conf)
make install-cli install-modules install-build install-headers install-programs install-pharcmd > install.log 2>&1 || { tail -30 install.log; exit 1; }
echo "INSTALL OK"
ls /usr/lib64/httpd/modules/ | grep -i php || echo "(brak innych libphp w modules – OK)"
install -m 755 libs/libphp7.so /usr/lib64/httpd/modules/libphp74-patched.so
mkdir -p /opt/php-7.4-mod/etc/conf.d
cp php.ini-production /opt/php-7.4-mod/etc/php.ini
mkdir -p /var/lib/php/session /var/lib/php/wsdlcache && chown apache:apache /var/lib/php/session /var/lib/php/wsdlcache

# konfiguracja Apache jak w remi php72 (mod_php)
mv -f /etc/httpd/conf.d/php-fpm.conf /root/php-fpm.conf.disabled 2>/dev/null || true
cat > /etc/httpd/conf.modules.d/15-php.conf <<'EOF'
<IfModule prefork.c>
  LoadModule php7_module modules/libphp74-patched.so
</IfModule>
EOF
cat > /etc/httpd/conf.d/php.conf <<'EOF'
<Files ".user.ini">
    Require all denied
</Files>
AddType text/html .php
DirectoryIndex index.php
<IfModule  mod_php7.c>
    <FilesMatch \.(php|phar)$>
        SetHandler application/x-httpd-php
    </FilesMatch>
    php_value session.save_handler "files"
    php_value session.save_path    "/var/lib/php/session"
    php_value soap.wsdl_cache_dir  "/var/lib/php/wsdlcache"
</IfModule>
EOF
httpd -t
httpd -M 2>/dev/null | grep -i php
httpd -k restart; sleep 2
smoke-test.sh
echo; curl -s http://127.0.0.1/index.php | head -2
tail -5 /var/log/httpd/error_log

