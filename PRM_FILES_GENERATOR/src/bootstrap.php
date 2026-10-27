<?php
declare(strict_types=1);

error_reporting(E_ALL);
ini_set('display_errors', '0'); // błędy pokazujemy w UI, nie w surowym HTML

require_once __DIR__ . '/config.php';
require_once __DIR__ . '/helpers.php';
require_once __DIR__ . '/checksum.php';
require_once __DIR__ . '/RowValidator.php';
require_once __DIR__ . '/SignResult.php';
require_once __DIR__ . '/CsvSigner.php';
require_once __DIR__ . '/UploadedCsv.php';

