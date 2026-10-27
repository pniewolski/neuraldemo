#!/bin/bash
# Diagnoza: dlaczego test HTTP ze skryptow nie dziala.
# Nic nie zmienia - tylko sprawdza i wypisuje.
echo "=== 1. Czy httpd dziala i na czym nasluchuje"
systemctl is-active httpd 2>/dev/null || echo "(systemctl: brak odpowiedzi)"
ss -ltnp 2>/dev/null | grep -i httpd || echo "  (brak nasluchu httpd!)"

echo
echo "=== 2. Czy localhost sie rozwiazuje"
getent hosts localhost || echo "  (localhost NIE rozwiazuje sie!)"

echo
echo "=== 3. Proba polaczenia na rozne adresy (kod HTTP)"
for U in http://localhost http://127.0.0.1 http://127.0.0.1:80 "http://$(hostname -f 2>/dev/null)"; do
  [ -z "${U#http://}" ] && continue
  C=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$U/" 2>/dev/null)
  printf '  %-40s -> %s\n' "$U/" "${C:-brak odpowiedzi}"
done

echo
echo "=== 4. Czy zapora blokuje polaczenia lokalne"
systemctl is-active firewalld 2>/dev/null
iptables -L INPUT -n 2>/dev/null | head -8

echo
echo "=== 5. Test wykonania PHP przez Apache"
T=/var/www/html/_diagnoza_$$.php
printf '<?php echo "PHP-DZIALA|",PHP_VERSION,"|",PHP_SAPI;' > "$T" 2>/dev/null \
  && echo "  plik testowy utworzony: $T" \
  || echo "  NIE MOZNA zapisac w /var/www/html"
ls -Z "$T" 2>/dev/null
for U in http://localhost http://127.0.0.1; do
  echo "  --- $U/$(basename $T)"
  curl -s -i --max-time 5 "$U/$(basename $T)" 2>/dev/null | head -12 | sed 's/^/     /'
done
rm -f "$T"

echo
echo "=== 6. DocumentRoot i vhosty"
grep -rhE '^[[:space:]]*(DocumentRoot|ServerName|Listen)' \
     /etc/httpd/conf/httpd.conf /etc/httpd/conf.d/ 2>/dev/null | sed 's/^[[:space:]]*/  /' | sort -u
echo "  --- httpd -S:"
httpd -S 2>&1 | sed 's/^/  /' | head -20

echo
echo "=== 7. SELinux"
getenforce 2>/dev/null
ls -Z /usr/lib64/httpd/modules/libphp74-patched.so 2>/dev/null
getsebool httpd_can_network_connect 2>/dev/null

