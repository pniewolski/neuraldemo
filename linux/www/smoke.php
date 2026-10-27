<?php
// Smoke test obszarów zmienionych przez łatkę CVE-2026-109618/109619:
// sesje, upload multipart (rfc1867), parsowanie zmiennych żądania, alokator/hash.
header('Content-Type: text/plain; charset=utf-8');
$ok = true;
$check = function ($name, $cond) use (&$ok) {
    echo ($cond ? '[OK]   ' : '[FAIL] ') . $name . PHP_EOL;
    $ok = $ok && $cond;
};

echo 'PHP ' . PHP_VERSION . ' ' . PHP_SAPI . PHP_EOL . str_repeat('-', 40) . PHP_EOL;

session_start();
$_SESSION['n'] = ($_SESSION['n'] ?? 0) + 1;
$check('session_start / zapis', $_SESSION['n'] >= 1);

$check('GET a[b][c]', ($_GET['a']['b']['c'] ?? null) === 'x' || !isset($_GET['a']));
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $check('POST pole', ($_POST['field'] ?? null) === 'value');
    $f = $_FILES['up'] ?? null;
    $check('upload pliku', $f && $f['error'] === UPLOAD_ERR_OK && file_get_contents($f['tmp_name']) === 'hello');
    $check('upload tablica plików', isset($_FILES['many']['name'][1]));
}

$a = [];
for ($i = 0; $i < 100000; $i++) { $a["k$i"] = $i; }
$check('hash 100k', count($a) === 100000 && $a['k99999'] === 99999);
$check('str_repeat / alloc', strlen(str_repeat('x', 10 * 1024 * 1024)) === 10485760);
$check('strtod', (float)'1.5e3' === 1500.0);
$check('mul overflow -> float', is_float(PHP_INT_MAX * 2));

echo str_repeat('-', 40) . PHP_EOL . ($ok ? 'ALL OK' : 'FAILURES') . PHP_EOL;

