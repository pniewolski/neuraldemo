#!/bin/bash
# Backtrace segfaulta mod_php – zatrzymuje główny httpd, uruchamia pod gdb
yum -y -q install gdb >/dev/null 2>&1
echo '<?php echo "HELLO\n";' > /var/www/html/_min.php
pkill -9 httpd; sleep 2; rm -f /run/httpd/httpd.pid
cat > /tmp/gdbcmd <<'EOF'
set pagination off
set confirm off
handle SIGTERM nostop noprint
run -X -DFOREGROUND
bt 30
quit
EOF
( sleep 10; curl -s --max-time 10 http://127.0.0.1/_min.php; echo "[curl koniec]" ) &
timeout 45 gdb -q -x /tmp/gdbcmd /usr/sbin/httpd 2>&1 \
  | grep -vE 'Reading symbols|no debugging symbols|^\[Thread|Using host|Missing separate|^warning: Error disabling' \
  | tail -40
pkill -9 gdb httpd 2>/dev/null
sleep 1
/usr/sbin/httpd -DFOREGROUND &
sleep 2
echo "[httpd wznowiony]"

