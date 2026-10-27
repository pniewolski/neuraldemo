#!/bin/bash
echo '<?php echo "HELLO\n";' > /var/www/html/_min.php
echo "=== główny httpd, port 80:"
curl -s --max-time 5 http://127.0.0.1/_min.php; echo "[koniec odpowiedzi]"
echo "=== error_log:"
tail -4 /var/log/httpd/error_log
echo "=== procesy:"
ps -eo pid,comm | grep -E 'httpd|php-fpm' | head -10
echo "=== czy php-fpm nasłuchuje:"
ss -ltn 2>/dev/null | grep -E '907[0-9]' || echo "(brak php-fpm)"

