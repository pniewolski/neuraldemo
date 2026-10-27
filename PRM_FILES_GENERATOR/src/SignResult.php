<?php
declare(strict_types=1);

/**
 * Wynik podpisywania pliku.
 */
final class SignResult
{
    /** @var string[] błędy uniemożliwiające podpis */
    public array $errors = [];

    /** @var string[] ostrzeżenia (zwykły tekst) */
    public array $warnings = [];

    /** Zawartość pliku wynikowego (z podpisem). */
    public string $output = '';

    public string $checksum = '';

    /** Podpis znaleziony w pliku wejściowym (jeśli był). */
    public ?string $oldChecksum = null;

    public bool $hasHeader = false;

    /** @var array<int, array{line:int, data:array, issues:string[]}> */
    public array $rows = [];

    public function isSuccess(): bool
    {
        return !$this->errors && $this->output !== '';
    }

    public function rowCount(): int
    {
        return count($this->rows);
    }

    public function rowsWithIssues(): int
    {
        return count(array_filter($this->rows, static fn(array $r) => (bool)$r['issues']));
    }

    /** @return array<string,int> typ => liczba wystąpień (tylko znane typy) */
    public function typeCounts(): array
    {
        $counts = [];
        foreach ($this->rows as $r) {
            $type = (string)$r['data']['param_type'];
            if (isset(PARAM_TYPES[$type])) {
                $counts[$type] = ($counts[$type] ?? 0) + 1;
            }
        }
        ksort($counts);
        return $counts;
    }
}

