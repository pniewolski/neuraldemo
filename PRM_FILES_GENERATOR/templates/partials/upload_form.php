<?php
/**
 * Formularz wyboru pliku + przykład formatu.
 */
?>
<section class="card">
    <h2>1. Wybierz plik</h2>
    <form method="post" enctype="multipart/form-data" id="uploadForm" data-max-size="<?= MAX_FILE_SIZE ?>">
        <label class="dropzone" id="dropzone">
            <span class="icon">📄</span>
            <span class="file-name" id="fileName">Przeciągnij plik CSV tutaj lub kliknij, aby wybrać</span>
            <span class="hint">Separator: <code><?= e(CSV_DELIMITER) ?></code> · kodowanie UTF-8 · maks. <?= formatMb(MAX_FILE_SIZE) ?></span>
            <input type="file" name="csvfile" id="csvfile" accept=".csv,text/csv" required>
        </label>
        <div class="actions">
            <button type="submit" class="btn btn-primary" id="submitBtn" disabled>
                <span class="spinner"></span><span class="label">Podpisz plik</span>
            </button>
        </div>
    </form>

    <details class="example-box">
        <summary class="hint">Jak powinien wyglądać plik? (pokaż przykład)</summary>
        <p class="hint">
            Nagłówek jest opcjonalny. Typy parametrów:
            <?php foreach (PARAM_TYPES as $code => $label): ?>
                <span class="badge badge-<?= e($code) ?>"><?= e($code) ?></span> <?= e($label) ?>&nbsp;
            <?php endforeach; ?>
        </p>
<pre class="example">id;group_id;descr;param_type;company_ind;value;length;min;max;enum_values;is_withdrawn;is_critical
11;12;Encja1;E;1;q;;;;{"0":"war1","1":"war2","2":"war3"};0;1
24;12;Numer2;N;1;3;;1;6;1;0;
25;13;Tekst3;T;1;Wartość parametru;30;;;0;;1
27;13;Bool4;L;1;0;;;;;;</pre>
    </details>
</section>

