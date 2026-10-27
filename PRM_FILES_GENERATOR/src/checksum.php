<?php
declare(strict_types=1);

/*
 * Logika podpisu.
 * UWAGA: algorytm NIE może się zmienić – musi być zgodny z importerem w Hosie.
 */

/**
 * Mapuje wiersz CSV na strukturę używaną do liczenia sumy kontrolnej.
 * Kolejność kluczy ma znaczenie dla wyniku!
 */
function mapRow(array $row): array
{
    $col = static fn(int $i) => $row[$i] ?? null;

    switch ($col(3)) {
        case 'N':
            $validation = $col(7) . '-' . $col(8);
            break;
        case 'T':
            $validation = $col(6);
            break;
        case 'E':
            $validation = $col(9);
            break;
        default:
            $validation = null;
    }

    return [
        'param_group'  => $col(1),
        'param_nr'     => $col(0),
        'param_descr'  => $col(2),
        'param_type'   => $col(3),
        'param_value'  => $col(5),
        'validation'   => $validation,
        'id_company'   => $col(4),
        'is_withdrawn' => !empty($col(10)) ? $col(10) : '0',
        'is_critical'  => !empty($col(11)) ? $col(11) : '0',
    ];
}

/**
 * Liczy sumę kontrolną dla listy zmapowanych wierszy.
 */
function calculateChecksum(array $rows): string
{
    $result = '';
    foreach ($rows as $row) {
        if (!is_array($row)) {
            continue;
        }
        foreach ($row as $value) {
            if (is_scalar($value)) {
                $result .= preg_replace('/[^a-zA-Z0-9]/', '', (string)$value);
            }
        }
    }
    return md5(sha1($result . CHECKSUM_SALT));
}

