#!/bin/bash
# Diagnostyka segfaulta mod_php 7.4
echo "== CLI działa?"
/opt/php-7.4-mod/bin/php -r 'echo "CLI OK\n";'
echo "== php.ini dla modułu:"
ls -l /opt/php-7.4-mod/etc/php.ini
echo "== najprostszy skrypt przez Apache:"
echo '<?php echo "HELLO\n";' > /var/www/html/_min.php
curl -s http://127.0.0.1/_min.php; echo "(koniec odpowiedzi)"
echo "== biblioteki wspólne Apache i modułu PHP (potencjalne konflikty):"
APRLIBS=$(ldd /usr/sbin/httpd | awk '{print $1}' | sort)
PHPLIBS=$(ldd /usr/lib64/httpd/modules/libphp74-patched.so | awk '{print $1}' | sort)
comm -12 <(echo "$APRLIBS") <(echo "$PHPLIBS") | tr '\n' ' '; echo
echo "== wersje pcre:"
ldd /usr/sbin/httpd | grep -i pcre
ldd /usr/lib64/httpd/modules/libphp74-patched.so | grep -i pcre
echo "== moduły Apache:"
httpd -M 2>/dev/null | grep -Ei 'php|proxy_fcgi|mpm'
echo "== ostatnie błędy:"
tail -5 /var/log/httpd/error_log

