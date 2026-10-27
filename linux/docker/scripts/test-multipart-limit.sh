#!/bin/bash
# Weryfikuje nowy limit max_multipart_body_parts (dodany przez łatkę) na aktywnym PHP.
P=${1:-/opt/php-7.4-patched}
reload() { kill -USR2 "$(cat "$P/var/run/php-fpm.pid")"; sleep 1; }
echo 'max_multipart_body_parts=2' > "$P/etc/conf.d/99-test.ini"; reload
echo "== limit=2 (oczekiwane: FAIL dla POST/upload + warning w logu)"
smoke-test.sh | grep -E '^PHP|POST|upload|ALL|FAILURES'
grep -h 'body parts limit' "$P/var/log/"*.log 2>/dev/null | tail -1
rm -f "$P/etc/conf.d/99-test.ini"; reload
echo "== domyślnie"
smoke-test.sh | tail -1

