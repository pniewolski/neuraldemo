#!/bin/bash
echo "== moduły PHP w Apache:"
httpd -M 2>/dev/null | grep -i php
echo "== LoadModule:"
cat /etc/httpd/conf.modules.d/15-php.conf
echo "== odpowiedź Apache:"
curl -s http://127.0.0.1/index.php | head -4
echo "== smoke test:"
smoke-test.sh
echo "== error_log:"
tail -3 /var/log/httpd/error_log

