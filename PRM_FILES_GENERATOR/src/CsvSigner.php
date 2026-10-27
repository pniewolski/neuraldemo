<?php
declare(strict_types=1);

/**
 * Parsuje plik CSV z parametrami, waliduje go i dokleja wiersz z sumą kontrolną.
 */
final class CsvSigner
{
    public function sign(string $raw): SignResult
    {
        $result = new SignResult();

        $this->checkEncoding($raw, $result);

        $eol         = strpos($raw, "\r\n") !== false ? "\r\n" : "\n";
        $validator   = new RowValidator();
        $outputLines = [];
        $mappedRows  = [];

        $handle = fopen('php://temp', 'r+');
        fwrite($handle, $raw);
        rewind($handle);

        $lineNo = 0;
        while (true) {
            $start = ftell($handle);
            $row   = fgetcsv($handle, 0, CSV_DELIMITER, '"', '\\');
            if ($row === false) {
                break;
            }
            $lineNo++;

            if ($this->isBlankRow($row)) {
                continue;
            }

            if ($row[0] === 'checksum') {
                // stary podpis nie trafia do wyniku – zostanie zastąpiony nowym
                $result->oldChecksum = (string)($row[1] ?? '');
                continue;
            }

            // oryginalny tekst rekordu (zachowuje formatowanie, także pola wieloliniowe)
            $outputLines[] = rtrim(substr($raw, $start, ftell($handle) - $start), "\r\n");

            if ($row[0] === 'id') {
                $result->hasHeader = true;
                continue;
            }

            $data         = mapRow($row);
            $mappedRows[] = $data;
            $issues       = $validator->validate($row, $data, $lineNo);

            $result->rows[] = ['line' => $lineNo, 'data' => $data, 'issues' => $issues];
            foreach ($issues as $issue) {
                $result->warnings[] = "Linia {$lineNo}: {$issue}.";
            }
        }
        fclose($handle);

        if (!$mappedRows) {
            $result->errors[] = 'Plik nie zawiera żadnych wierszy z parametrami.';
            return $result;
        }

        $result->checksum = calculateChecksum($mappedRows);
        $result->output   = implode($eol, $outputLines) . $eol . 'checksum;' . $result->checksum;

        if ($result->oldChecksum !== null) {
            $result->warnings[] = $result->oldChecksum === $result->checksum
                ? 'Plik był już podpisany – istniejący podpis jest poprawny (zastąpiono go identycznym).'
                : "Plik zawierał nieaktualny podpis ({$result->oldChecksum}) – został zastąpiony nowym.";
        }

        return $result;
    }

    private function checkEncoding(string $raw, SignResult $result): void
    {
        if (strncmp($raw, "\xEF\xBB\xBF", 3) === 0) {
            $result->warnings[] = 'Plik zawiera znacznik BOM (UTF-8). Jeśli pierwszy wiersz to nagłówek, '
                . 'zostanie potraktowany jak dane – zapisz plik jako „UTF-8 bez BOM”.';
        }
        if (function_exists('mb_check_encoding') && !mb_check_encoding($raw, 'UTF-8')) {
            $result->warnings[] = 'Plik nie jest poprawnym UTF-8 (np. zapisany w Windows-1250). '
                . 'Polskie znaki mogą się wyświetlać niepoprawnie.';
        }
    }

    private function isBlankRow(array $row): bool
    {
        return count($row) === 1 && ($row[0] === null || trim((string)$row[0]) === '');
    }
}

