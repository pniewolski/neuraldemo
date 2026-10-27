<?php
declare(strict_types=1);

/** Sól używana przy liczeniu sumy kontrolnej – musi być zgodna z importerem. */
const CHECKSUM_SALT = 'Bwg3ax98Mmwogisn3';

/** Separator kolumn w pliku CSV. */
const CSV_DELIMITER = ';';

/** Maksymalny rozmiar przesyłanego pliku (bajty). */
const MAX_FILE_SIZE = 5 * 1024 * 1024;

/** Oczekiwana liczba kolumn w wierszu z parametrem. */
const EXPECTED_COLUMNS = 12;

/** Dozwolone rozszerzenia plików. */
const ALLOWED_EXTENSIONS = ['csv', 'txt'];

/** Obsługiwane typy parametrów. */
const PARAM_TYPES = [
    'N' => 'Liczba',
    'T' => 'Tekst',
    'E' => 'Encja (lista)',
    'L' => 'Logiczny',
];

