#!/bin/bash
echo "=== wersja PHP w Apache:"
echo '<?php echo PHP_VERSION," ",PHP_SAPI," ini=",php_ini_loaded_file(),"\n";' > /var/www/html/_ver.php
curl -s --max-time 5 http://127.0.0.1/_ver.php
echo "=== czy łatka jest aktywna (nowe ini z patcha):"
echo '<?php var_dump(ini_get("max_multipart_body_parts"));' > /var/www/html/_p.php
curl -s --max-time 5 http://127.0.0.1/_p.php
echo "=== smoke test (sesje, upload, tablice):"
smoke-test.sh
echo "=== rozszerzenia w Apache vs CLI:"
curl -s --max-time 5 "http://127.0.0.1/_e.php" >/dev/null 2>&1
echo '<?php echo implode("\n", get_loaded_extensions()),"\n";' > /var/www/html/_e.php
diff <(curl -s http://127.0.0.1/_e.php | sort -f) <(/opt/php-7.4-mod/bin/php -m | grep -v '^\[' | grep -v '^$' | sort -f) && echo "APACHE=CLI OK"
rm -f /var/www/html/_ver.php /var/www/html/_p.php /var/www/html/_e.php /var/www/html/_min.php
echo "=== biblioteki modułu:"
ldd /usr/lib64/httpd/modules/libphp74-patched.so | awk '{print $1}' | grep -E '^lib' | sort | tr '\n' ' '; echo
echo "=== error_log:"
tail -3 /var/log/httpd/error_log

