#!/bin/bash
cd /root/deploy || exit 1
sed -i 's|^SRCDIR=.*|SRCDIR="/usr/local/src/php-mod"|' config.sh
grep '^SRCDIR=' config.sh
echo "=== uruchomienie:"
./61-sprawdz-test-serwera.sh
echo "RC=$?"

