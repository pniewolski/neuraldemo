<?php
declare(strict_types=1);

/**
 * Odczyt i podstawowa walidacja przesłanego pliku.
 */
final class UploadedCsv
{
    public string $name = '';
    public string $content = '';
    public ?string $error = null;
    /** @var string[] */
    public array $warnings = [];

    public static function fromRequest(?array $file): self
    {
        $upload = new self();

        if (!$file || !isset($file['error'])) {
            $upload->error = 'Nie przesłano pliku.';
            return $upload;
        }
        if ($file['error'] !== UPLOAD_ERR_OK) {
            $upload->error = self::uploadErrorMessage((int)$file['error']);
            return $upload;
        }
        if ((int)$file['size'] === 0) {
            $upload->error = 'Przesłany plik jest pusty.';
            return $upload;
        }
        if ((int)$file['size'] > MAX_FILE_SIZE) {
            $upload->error = 'Plik przekracza maksymalny rozmiar ' . formatMb(MAX_FILE_SIZE) . '.';
            return $upload;
        }

        $upload->name = basename((string)$file['name']);

        $ext = strtolower(pathinfo($upload->name, PATHINFO_EXTENSION));
        if (!in_array($ext, ALLOWED_EXTENSIONS, true)) {
            $upload->warnings[] = "Plik ma rozszerzenie „.{$ext}” – oczekiwano .csv. Przetwarzam mimo to.";
        }

        $content = @file_get_contents($file['tmp_name']);
        if ($content === false) {
            $upload->error = 'Nie udało się odczytać przesłanego pliku.';
            return $upload;
        }
        $upload->content = $content;

        return $upload;
    }

    /** Nazwa pliku do pobrania, np. "parametry_podpisany.csv". */
    public function signedFileName(): string
    {
        $base = pathinfo($this->name, PATHINFO_FILENAME);
        return ($base !== '' ? $base : 'wsad') . '_podpisany.csv';
    }

    private static function uploadErrorMessage(int $code): string
    {
        switch ($code) {
            case UPLOAD_ERR_INI_SIZE:
            case UPLOAD_ERR_FORM_SIZE:
                return 'Plik jest zbyt duży.';
            case UPLOAD_ERR_PARTIAL:
                return 'Plik został przesłany tylko częściowo. Spróbuj ponownie.';
            case UPLOAD_ERR_NO_FILE:
                return 'Nie wybrano pliku.';
            default:
                return "Nie udało się przesłać pliku (kod błędu: {$code}).";
        }
    }
}

