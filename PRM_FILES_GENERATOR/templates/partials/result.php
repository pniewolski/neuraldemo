<?php
/**
 * Wynik: statystyki, suma kontrolna, podgląd i treść pliku.
 *
 * @var UploadedCsv $upload
 * @var SignResult  $result
 */
$issues = $result->rowsWithIssues();
?>
<section class="card">
    <h2>2. Wynik</h2>

    <div class="stats">
        <div class="stat">
            <div class="v"><?= $result->rowCount() ?></div>
            <div class="l">parametrów</div>
        </div>
        <?php foreach ($result->typeCounts() as $type => $count): ?>
            <div class="stat">
                <div class="v"><?= $count ?></div>
                <div class="l"><span class="badge badge-<?= e($type) ?>"><?= e($type) ?></span> <?= e(PARAM_TYPES[$type]) ?></div>
            </div>
        <?php endforeach; ?>
        <div class="stat">
            <div class="v"><?= $result->hasHeader ? 'tak' : 'nie' ?></div>
            <div class="l">nagłówek</div>
        </div>
        <div class="stat">
            <div class="v <?= $issues ? 'text-warn' : 'text-ok' ?>"><?= $issues ?></div>
            <div class="l">wierszy z uwagami</div>
        </div>
    </div>

    <p class="hint label-sm">Suma kontrolna:</p>
    <div class="checksum">
        <code id="checksumValue"><?= e($result->checksum) ?></code>
        <button type="button" class="btn" data-copy="#checksumValue">📋 Kopiuj</button>
    </div>

    <div class="actions">
        <button type="button" class="btn btn-primary" id="downloadBtn"
                data-source="#resultText" data-filename="<?= e($upload->signedFileName()) ?>">
            ⬇️ Pobierz <?= e($upload->signedFileName()) ?>
        </button>
        <button type="button" class="btn" data-copy="#resultText">📋 Kopiuj zawartość pliku</button>
    </div>
</section>

<section class="card">
    <h2>3. Podgląd sparsowanych parametrów</h2>
    <div class="table-wrap">
        <table>
            <thead>
            <tr>
                <th>Linia</th><th>ID</th><th>Grupa</th><th>Opis</th><th>Typ</th><th>Wartość</th>
                <th>Walidacja</th><th>Firma</th><th>Wycofany</th><th>Krytyczny</th><th>Uwagi</th>
            </tr>
            </thead>
            <tbody>
            <?php foreach ($result->rows as $row): $d = $row['data']; ?>
                <tr class="<?= $row['issues'] ? 'has-issue' : '' ?>">
                    <td><?= $row['line'] ?></td>
                    <td class="mono"><?= e($d['param_nr']) ?></td>
                    <td class="mono"><?= e($d['param_group']) ?></td>
                    <td class="wrap"><?= e($d['param_descr']) ?></td>
                    <td><span class="badge badge-<?= e($d['param_type']) ?>"><?= e($d['param_type']) ?></span></td>
                    <td class="wrap"><?= e($d['param_value']) ?></td>
                    <td class="mono wrap"><?= e($d['validation']) ?></td>
                    <td><?= e($d['id_company']) ?></td>
                    <td><?= $d['is_withdrawn'] === '1' ? '✔' : '–' ?></td>
                    <td><?= $d['is_critical'] === '1' ? '❗' : '–' ?></td>
                    <td class="wrap">
                        <?php if ($row['issues']): ?>
                            ⚠️ <?= e(implode('; ', $row['issues'])) ?>
                        <?php else: ?>
                            <span class="text-ok">OK</span>
                        <?php endif; ?>
                    </td>
                </tr>
            <?php endforeach; ?>
            </tbody>
        </table>
    </div>
</section>

<section class="card">
    <h2>4. Zawartość pliku wynikowego</h2>
    <p class="hint">Pole tylko do odczytu – każda zmiana treści unieważniłaby podpis.</p>
    <textarea id="resultText" readonly spellcheck="false"><?= e($result->output) ?></textarea>
</section>

