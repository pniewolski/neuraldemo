<?php
/**
 * Komunikaty: błędy, sukces, ostrzeżenia.
 *
 * @var string[]         $errors
 * @var string[]         $warnings
 * @var UploadedCsv|null $upload
 * @var SignResult|null  $result
 */
?>
<?php if ($errors): ?>
    <div class="alert alert-err" role="alert">
        <strong>❌ Nie udało się przygotować pliku</strong>
        <ul>
            <?php foreach ($errors as $error): ?>
                <li><?= e($error) ?></li>
            <?php endforeach; ?>
        </ul>
    </div>
<?php endif; ?>

<?php if ($result && $result->isSuccess()): ?>
    <div class="alert alert-ok" role="status" id="successAlert">
        <strong>✅ Plik „<?= e($upload->name) ?>” został podpisany</strong>
        <?= $result->rowCount() ?> parametrów<?=
            $result->rowsWithIssues()
                ? ', ' . $result->rowsWithIssues() . ' wierszy wymaga uwagi (sprawdź ostrzeżenia poniżej)'
                : ', bez zastrzeżeń' ?>.
    </div>
<?php endif; ?>

<?php if ($warnings): ?>
    <details class="alert alert-warn" <?= count($warnings) <= 5 ? 'open' : '' ?>>
        <summary>⚠️ Ostrzeżenia (<?= count($warnings) ?>)</summary>
        <ul>
            <?php foreach ($warnings as $warning): ?>
                <li><?= e($warning) ?></li>
            <?php endforeach; ?>
        </ul>
    </details>
<?php endif; ?>

