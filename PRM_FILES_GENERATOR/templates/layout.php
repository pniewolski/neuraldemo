<?php
/**
 * Główny układ strony.
 *
 * @var string[]         $errors
 * @var string[]         $warnings
 * @var UploadedCsv|null $upload
 * @var SignResult|null  $result
 */
?>
<!DOCTYPE html>
<html lang="pl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Podpisywanie wsadu do importera</title>
    <link rel="stylesheet" href="assets/style.css">
</head>
<body>
<div class="container">
    <header>
        <h1>🔏 Podpisywanie wsadu do importera</h1>
        <p>Wczytaj plik CSV z definicją parametrów – narzędzie zwaliduje go, policzy sumę kontrolną
            i przygotuje plik gotowy do wczytania w Hosie.</p>
    </header>

    <?php render('partials/alerts', compact('errors', 'warnings', 'upload', 'result')); ?>
    <?php render('partials/upload_form'); ?>

    <?php if ($result && $result->isSuccess()): ?>
        <?php render('partials/result', compact('upload', 'result')); ?>
    <?php endif; ?>
</div>

<div class="toast" id="toast" role="status" aria-live="polite"></div>

<script src="assets/app.js"></script>
</body>
</html>

