<?php
declare(strict_types=1);

/** Escapowanie do HTML. */
function e($value): string
{
    return htmlspecialchars((string)$value, ENT_QUOTES, 'UTF-8');
}

/** Formatuje rozmiar w MB, np. "5 MB". */
function formatMb(int $bytes): string
{
    return round($bytes / 1024 / 1024, 2) . ' MB';
}

/** Renderuje szablon z katalogu templates/ z przekazanymi zmiennymi. */
function render(string $template, array $vars = []): void
{
    extract($vars, EXTR_SKIP);
    require __DIR__ . '/../templates/' . $template . '.php';
}

