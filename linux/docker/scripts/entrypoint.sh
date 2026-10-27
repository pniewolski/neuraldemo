#!/bin/bash
# Uruchamia php-fpm dla każdej zainstalowanej wersji w /opt/php-*, potem Apache na pierwszym planie.
set -e
for p in /opt/php-*; do
  [ -x "$p/sbin/php-fpm" ] || continue
  rm -f "$p/var/run/php-fpm.pid"
  "$p/sbin/php-fpm" -y "$p/etc/php-fpm.conf" && echo "php-fpm $(cat "$p/.php-version") -> :$(cat "$p/.fpm-port")"
done
PORT=$(cat /etc/httpd/php-active-port)
echo "Apache -> PHP na porcie $PORT"
rm -f /run/httpd/httpd.pid
exec /usr/sbin/httpd -DFOREGROUND

