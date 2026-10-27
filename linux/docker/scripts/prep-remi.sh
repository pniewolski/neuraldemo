#!/bin/bash
# Odtwarza warunki z serwera uzytkownika: dwie dyrektywy LoadModule (remi) + zly DOCROOT
set -e
install -m 755 /usr/local/src/php-mod/libs/libphp7.so /usr/lib64/httpd/modules/libphp74-patched.so
cp -f /usr/lib64/httpd/modules/libphp74-patched.so /usr/lib64/httpd/modules/libphp7.so
cp -f /usr/lib64/httpd/modules/libphp74-patched.so /usr/lib64/httpd/modules/libphp7-zts.so
cat > /etc/httpd/conf.modules.d/15-php.conf <<'EOF'
# Cannot load both php5 and php7 modules
<IfModule !mod_php5.c>
  <IfModule prefork.c>
    LoadModule php7_module modules/libphp7.so
  </IfModule>
  <IfModule !prefork.c>
    LoadModule php7_module modules/libphp7-zts.so
  </IfModule>
</IfModule>
EOF
# zly DOCROOT w config.sh – ma go wykryc auto_docroot
sed -i 's|^DOCROOT=.*|DOCROOT="/var/www/NIE-ISTNIEJE"|' /root/deploy/config.sh
sed -i 's|^TEST_URL=.*|TEST_URL="http://127.0.0.1"|' /root/deploy/config.sh
sed -i 's|^PHP_PREFIX=.*|PHP_PREFIX="/opt/php-7.4-mod"|' /root/deploy/config.sh
rm -f /root/php74-migracja/php72-modules-apache.txt
echo "=== przygotowano"
grep -E '^(DOCROOT|TEST_URL|PHP_PREFIX)=' /root/deploy/config.sh

