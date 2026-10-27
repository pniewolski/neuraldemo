#!/bin/bash
# Test skryptu 60-czy-podatny.sh w trzech scenariuszach
cd /root/deploy || exit 1
BAK=/tmp/libphp7-oryginal.so
cp -f /usr/lib64/httpd/modules/libphp7.so $BAK

echo "############ A. modul Z LATKA (stan prawidlowy po wdrozeniu)"
./60-czy-podatny.sh > /tmp/a.out 2>&1; echo "RC=$?"
sed -n '/WERDYKT/,$p' /tmp/a.out | head -6

echo
echo "############ B. modul BEZ LATKI na dysku (Apache wciaz ma stary w pamieci)"
cp -f /tmp/libphp7-vanilla.so /usr/lib64/httpd/modules/libphp7.so
./60-czy-podatny.sh > /tmp/b.out 2>&1; echo "RC=$?"
sed -n '/== 2\./,/== 3\./p' /tmp/b.out | head -4
sed -n '/WERDYKT/,$p' /tmp/b.out | head -8

echo
echo "############ C. przywrocenie modulu z latka"
cp -f $BAK /usr/lib64/httpd/modules/libphp7.so
./60-czy-podatny.sh > /tmp/c.out 2>&1; echo "RC=$?"
sed -n '/WERDYKT/,$p' /tmp/c.out | head -4

