<?php
header('Content-Type: text/plain; charset=utf-8');
echo 'PHP ' . PHP_VERSION . ' (' . PHP_SAPI . ')' . PHP_EOL;
echo 'Binary: ' . PHP_BINARY . PHP_EOL;
echo 'OS: ' . php_uname() . PHP_EOL;
echo 'Extensions: ' . implode(', ', get_loaded_extensions()) . PHP_EOL;

