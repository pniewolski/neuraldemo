#!/bin/bash
# Przygotowanie kontenera do testu skryptów deploy:
# odtwarza moduł mod_php 7.4 i ustawia config.sh na ścieżki z kontenera.
set -e
install -m 755 /usr/local/src/php-mod/libs/libphp7.so /usr/lib64/httpd/modules/libphp74-patched.so
# atrapa modułu "PHP 7.2", żeby dało się przetestować przełączanie i rollback
cp -n /usr/lib64/httpd/modules/libphp74-patched.so /usr/lib64/httpd/modules/libphp7.so
sed -i 's|^PHP_PREFIX=.*|PHP_PREFIX="/opt/php-7.4-mod"|' /root/deploy/config.sh
sed -i 's|^TEST_URL=.*|TEST_URL="http://127.0.0.1"|' /root/deploy/config.sh
cat > /etc/httpd/conf.modules.d/15-php.conf <<'EOF'
<IfModule prefork.c>
  LoadModule php7_module modules/libphp7.so
</IfModule>
EOF
echo "=== sprawdzenie skladni skryptow:"
cd /root/deploy
for f in *.sh; do
  if bash -n "$f" 2>/tmp/e; then echo "  OK    $f"; else echo "  BLAD  $f"; cat /tmp/e; fi
done
echo "=== gotowe"

