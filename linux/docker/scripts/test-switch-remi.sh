#!/bin/bash
# Test podmiany modulu przy dwoch dyrektywach LoadModule (uklad remi)
cd /root/deploy || exit 1
echo "=== PRZED:"
cat /etc/httpd/conf.modules.d/15-php.conf
echo
echo "=== podmiana (bez restartu – kontener nie ma systemd):"
MODCONF=/etc/httpd/conf.modules.d/15-php.conf
cp -a $MODCONF /root/php74-migracja/15-php.conf.php72
sed -i 's|modules/libphp7\.so|modules/libphp74-patched.so|' $MODCONF
echo "=== PO:"
cat $MODCONF
echo
echo "=== ile dyrektyw na nowy modul (ma byc 1):"
grep -c 'modules/libphp74-patched.so' $MODCONF
echo "=== czy zts pozostal nietkniety (ma byc 1):"
grep -c 'modules/libphp7-zts.so' $MODCONF
echo "=== httpd -t:"
httpd -t
echo "=== wykryta wersja wg skryptow:"
source ./lib.sh 2>/dev/null; current_apache_php
echo
echo "=== rollback przez przywrocenie kopii:"
cp -a /root/php74-migracja/15-php.conf.php72 $MODCONF
cat $MODCONF
source ./lib.sh 2>/dev/null; echo "wykryta wersja: $(current_apache_php)"

