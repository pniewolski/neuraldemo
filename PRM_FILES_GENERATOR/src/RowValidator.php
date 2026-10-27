<?php
declare(strict_types=1);

/**
 * Sprawdza poprawność wierszy z parametrami.
 * Zwraca listę uwag – nie blokują one podpisu, służą jako informacja dla użytkownika.
 */
final class RowValidator
{
    /** @var array<string,int> id parametru => numer linii pierwszego wystąpienia */
    private array $seenIds = [];

    /**
     * @param array $rawRow  wiersz w postaci z fgetcsv
     * @param array $data    wiersz po mapRow()
     * @return string[]
     */
    public function validate(array $rawRow, array $data, int $lineNo): array
    {
        $issues = [];

        if (count($rawRow) < EXPECTED_COLUMNS) {
            $issues[] = sprintf('za mało kolumn (%d/%d)', count($rawRow), EXPECTED_COLUMNS);
        }

        $id = (string)$data['param_nr'];
        if (!ctype_digit($id)) {
            $issues[] = 'id nie jest liczbą';
        } elseif (isset($this->seenIds[$id])) {
            $issues[] = 'zduplikowane id (także w linii ' . $this->seenIds[$id] . ')';
        } else {
            $this->seenIds[$id] = $lineNo;
        }

        $type = (string)$data['param_type'];
        if (!isset(PARAM_TYPES[$type])) {
            $issues[] = 'nieznany typ „' . $type . '”';
        }

        $validation = (string)$data['validation'];
        if ($type === 'E' && $validation !== '' && json_decode($validation) === null) {
            $issues[] = 'enum_values nie jest poprawnym JSON';
        }

        $value = (string)$data['param_value'];
        if ($type === 'N' && $value !== '' && !is_numeric($value)) {
            $issues[] = 'wartość nie jest liczbą';
        }

        return $issues;
    }
}

