#!/bin/bash
# Weryfikacja, ze polecenia z instrukcji recznej dzialaja 1:1
DOCROOT=/var/www/html

echo "=== 8a. test wersji i latki (_check.php):"
cat > "$DOCROOT/_check.php" <<'PHP'
<?php
echo "VER="  . PHP_VERSION . "\n";
echo "SAPI=" . PHP_SAPI . "\n";
echo "INI="  . php_ini_loaded_file() . "\n";
echo "PATCH=" . var_export(ini_get('max_multipart_body_parts'), true) . "\n";
PHP
curl -s http://localhost/_check.php
rm -f "$DOCROOT/_check.php"

echo
echo "=== 8c. smoke test (sesje, upload, GET/POST):"
cat > "$DOCROOT/_smoke.php" <<'PHP'
<?php
header('Content-Type: text/plain');
$ok = true;
$t = function($n,$c) use (&$ok){ echo ($c?"OK   ":"FAIL ").$n."\n"; $ok=$ok&&$c; };
session_start();
$_SESSION['n'] = ($_SESSION['n'] ?? 0) + 1;
$t('sesja', $_SESSION['n'] >= 1);
$t('GET a[b][c]', ($_GET['a']['b']['c'] ?? null) === 'x');
$t('POST pole', ($_POST['field'] ?? null) === 'value');
$f = $_FILES['up'] ?? null;
$t('upload pliku', $f && $f['error']===UPLOAD_ERR_OK && file_get_contents($f['tmp_name'])==='hello');
$t('upload tablica', isset($_FILES['many']['name'][1]));
echo $ok ? "WSZYSTKO OK\n" : "SA BLEDY\n";
PHP
printf hello > /tmp/_up.txt
curl -sg "http://localhost/_smoke.php?a[b][c]=x" \
     -F field=value -F "up=@/tmp/_up.txt" \
     -F "many[]=@/tmp/_up.txt" -F "many[]=@/tmp/_up.txt"
rm -f "$DOCROOT/_smoke.php" /tmp/_up.txt

echo
echo "=== wykrywanie latki w pliku modulu:"
grep -qa max_multipart_body_parts /usr/lib64/httpd/modules/libphp7.so \
  && echo "libphp7.so: z latka" || echo "libphp7.so: BEZ latki"

echo
echo "=== sed na php.ini (komentowanie extension=):"
printf 'extension=foo.so\n  zend_extension=bar.so\nmemory_limit=128M\n' > /tmp/test.ini
sed -i 's/^\s*extension\s*=/;&/; s/^\s*zend_extension\s*=/;&/' /tmp/test.ini
cat /tmp/test.ini
rm -f /tmp/test.ini

