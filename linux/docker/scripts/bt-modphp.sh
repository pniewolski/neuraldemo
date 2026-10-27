#!/bin/bash
# Backtrace segfaulta mod_php
yum -y -q install gdb >/dev/null 2>&1
echo '<?php echo "HELLO\n";' > /var/www/html/_min.php
sed -e 's/^Listen .*/Listen 8099/' /etc/httpd/conf/httpd.conf > /tmp/httpd-dbg.conf
echo 'PidFile /tmp/httpd-dbg.pid' >> /tmp/httpd-dbg.conf
cat > /tmp/gdbcmd <<'EOF'
set pagination off
set confirm off
run -f /tmp/httpd-dbg.conf -X -DFOREGROUND
bt 30
quit
EOF
( sleep 8; curl -s --max-time 10 http://127.0.0.1:8099/_min.php; echo "[curl done]" ) &
timeout 45 gdb -q -x /tmp/gdbcmd /usr/sbin/httpd 2>&1 | grep -vE '^\[Thread|Using host|Missing separate' | tail -45


