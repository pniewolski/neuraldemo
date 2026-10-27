#!/bin/bash
# Backtrace segfaulta mod_php
yum -y -q install gdb >/dev/null 2>&1
echo '<?php echo "HELLO\n";' > /var/www/html/_min.php
mkdir -p /tmp/cores && chmod 777 /tmp/cores
ulimit -c unlimited
# uruchom httpd w trybie jednoprocesowym pod gdb i wykonaj jedno żądanie
cat > /tmp/gdbcmd <<'EOF'
set pagination off
run -DFOREGROUND -DONE_PROCESS -X
bt 25
quit
EOF
( sleep 6; curl -s --max-time 8 http://127.0.0.1:8099/_min.php >/dev/null 2>&1 ) &
sed -e 's/^Listen .*/Listen 8099/' /etc/httpd/conf/httpd.conf > /tmp/httpd-dbg.conf
timeout 40 gdb -q -x /tmp/gdbcmd --args /usr/sbin/httpd -f /tmp/httpd-dbg.conf -X 2>&1 | tail -40

