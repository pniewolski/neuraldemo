#!/bin/bash
# Backtrace segfaulta mod_php – zatrzymuje główny httpd, uruchamia pod gdb
yum -y -q install gdb >/dev/null 2>&1
echo '<?php echo "HELLO\n";' > /var/www/html/_min.php
# osobna, minimalna instancja httpd na porcie 8099 (główny httpd = PID 1 zostaje nietknięty)
cat > /tmp/httpd-dbg.conf <<'EOF'
ServerRoot /etc/httpd
Listen 8099
PidFile /tmp/httpd-dbg.pid
ErrorLog /tmp/httpd-dbg-error.log
ServerName dbg
User apache
Group apache
DocumentRoot /var/www/html
TypesConfig /etc/mime.types
Include conf.modules.d/*.conf
Include conf.d/php.conf
<Directory /var/www/html>
    Require all granted
</Directory>
EOF
cat > /tmp/gdbcmd <<'EOF'
set pagination off
set confirm off
run -f /tmp/httpd-dbg.conf -X -DFOREGROUND
bt 30
quit
EOF
( sleep 10; curl -s --max-time 10 http://127.0.0.1:8099/_min.php; echo "[curl koniec]" ) &
timeout 45 gdb -q -x /tmp/gdbcmd /usr/sbin/httpd 2>&1 \
  | grep -vE 'Reading symbols|no debugging symbols|^\[Thread|Using host|Missing separate|^warning: Error disabling' \
  | tail -40



