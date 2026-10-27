#!/bin/bash
# Test menu.sh – scenariusze nawigacji.
cd /root/deploy || exit 1
NOCOLOR='s/\x1b\[[0-9;]*m//g'

echo "############ 1. podmenu logow -> php.ini (poz. 8, 5) ############"
echo test > /root/php74-migracja/rola
printf '8\n5\n\n0\n0\n' | ./menu.sh 2>&1 | sed "$NOCOLOR" | sed -n '/Logi i pliki/,$p' | head -28

echo
echo "############ 2. rola PROD bez paczki (poz. 3) ############"
echo prod > /root/php74-migracja/rola
mv /root/php-7.4-patched-centos7.tgz /tmp/pkg.bak 2>/dev/null
printf '3\n\n0\n' | ./menu.sh 2>&1 | sed "$NOCOLOR" | sed -n '/Brak paczki/,/Naciśnij/p' | head -8
mv /tmp/pkg.bak /root/php-7.4-patched-centos7.tgz 2>/dev/null

echo
echo "############ 3. rola PROD – ekran glowny ############"
printf '0\n' | ./menu.sh 2>&1 | sed "$NOCOLOR" | grep -E 'Rola|^ +3\)|Paczka'

echo
echo "############ 4. ostrzezenie przed przelaczeniem na PROD (poz. 5, odmowa) ############"
printf '5\nn\n0\n' | ./menu.sh 2>&1 | sed "$NOCOLOR" | sed -n '/ZRESTARTOWANY/,/Kontynuowa/p' | head -6

echo
echo "############ 5. podsumowanie przy wyjsciu ############"
printf '0\n' | ./menu.sh 2>&1 | sed "$NOCOLOR" | tail -4
echo test > /root/php74-migracja/rola

