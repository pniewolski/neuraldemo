<#
.SYNOPSIS
  Wgrywa skrypty wdrozeniowe PHP 7.4 do repozytorium hoss2-dev-environment.

.DESCRIPTION
  Klonuje repozytorium, kopiuje katalog php74-cve-2026-109618-109619,
  weryfikuje zakonczenia linii i wykonuje commit + push.
  Nie dotyka zadnych innych plikow w repozytorium.
  Srodowisko testowe Dockera nie jest kopiowane.

.PARAMETER Branch
  Galaz docelowa. Domyslnie php74-cve-2026-109618-109619 (nowa galaz, do merge requesta).
  Podaj 'main' albo 'master', aby wrzucic bezposrednio na galaz glowna.

.PARAMETER Force
  Nadpisuje katalog w repozytorium, jesli juz istnieje.
#>
param(
    [string]$Branch = "php74-cve-2026-109618-109619",
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$RepoUrl  = "git@git.mccomp.pl:devops/tools/hoss2-dev-environment.git"
$WorkDir  = "C:\p\PhpstormProjects\hoss2-dev-environment"
$Source   = "C:\p\PhpstormProjects\_hoss2-upload\php74-cve-2026-109618-109619"
$DirName  = "php74-cve-2026-109618-109619"

function Krok($t) { Write-Host "`n== $t" -ForegroundColor Cyan }
function Ok($t)   { Write-Host "[ OK ] $t"  -ForegroundColor Green }
function Uwaga($t){ Write-Host "[UWAGA] $t" -ForegroundColor Yellow }
function Stop-Blad($t) { Write-Host "[BLAD] $t" -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------- warunki wstepne
Krok "Sprawdzenie zrodla"
if (-not (Test-Path $Source)) { Stop-Blad "Brak katalogu zrodlowego: $Source" }
$liczbaSh = (Get-ChildItem "$Source\*.sh").Count
Ok "Znaleziono $liczbaSh skryptow w $Source"

Krok "Sprawdzenie dostepu do repozytorium"
# BatchMode, zeby nie czekac na haslo w nieskonczonosc
$null = & ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -T git@git.mccomp.pl 2>&1
# GitLab zwraca kod 1 nawet przy poprawnym logowaniu, wiec sprawdzamy inaczej
$test = & git ls-remote $RepoUrl HEAD 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host $test -ForegroundColor Red
    Write-Host ""
    Uwaga "Brak dostepu do repozytorium."
    Write-Host "Dodaj ten klucz publiczny w GitLabie (Preferences -> SSH Keys):"
    Write-Host ""
    Get-Content "$env:USERPROFILE\.ssh\id_ed25519.pub"
    Write-Host ""
    Write-Host "Szczegoly: C:\p\PhpstormProjects\_hoss2-upload\INSTRUKCJA.md"
    exit 1
}
Ok "Dostep do repozytorium dziala"

# ---------------------------------------------------------------- klonowanie
Krok "Przygotowanie kopii roboczej"
if (Test-Path "$WorkDir\.git") {
    Ok "Repozytorium juz sklonowane: $WorkDir"
    Push-Location $WorkDir
    & git fetch --all --prune
    if ($LASTEXITCODE -ne 0) { Pop-Location; Stop-Blad "git fetch nie powiodl sie" }
    Pop-Location
} else {
    if (Test-Path $WorkDir) { Stop-Blad "$WorkDir istnieje, ale nie jest repozytorium git. Usun go recznie." }
    & git clone $RepoUrl $WorkDir
    if ($LASTEXITCODE -ne 0) { Stop-Blad "git clone nie powiodl sie" }
    Ok "Sklonowano do $WorkDir"
}

Push-Location $WorkDir
try {
    $glowna = (& git symbolic-ref --short refs/remotes/origin/HEAD 2>$null) -replace '^origin/',''
    if (-not $glowna) { $glowna = "main" }
    Ok "Galaz glowna repozytorium: $glowna"

    Krok "Co juz jest w repozytorium"
    & git checkout -q $glowna 2>&1 | Out-Null
    & git pull -q --ff-only 2>&1 | Out-Null
    Get-ChildItem . -Force | Where-Object { $_.Name -ne '.git' } |
        Select-Object -ExpandProperty Name | ForEach-Object { "  $_" }

    # ------------------------------------------------------------ galaz
    Krok "Galaz docelowa: $Branch"
    if ($Branch -ne $glowna) {
        $istnieje = & git ls-remote --heads origin $Branch
        if ($istnieje) {
            & git checkout -q $Branch 2>&1 | Out-Null
            & git pull -q --ff-only origin $Branch 2>&1 | Out-Null
            Ok "Przelaczono na istniejaca galaz $Branch"
        } else {
            & git checkout -q -b $Branch
            Ok "Utworzono nowa galaz $Branch"
        }
    } else {
        Uwaga "Praca bezposrednio na galezi glownej ($glowna)"
    }

    # ------------------------------------------------------------ kopiowanie
    Krok "Kopiowanie plikow"
    $cel = Join-Path $WorkDir $DirName
    if ((Test-Path $cel) -and -not $Force) {
        Uwaga "Katalog $DirName juz istnieje w repozytorium."
        $o = Read-Host "Nadpisac jego zawartosc? [t/N]"
        if ($o -notmatch '^[tTyY]') { Stop-Blad "Przerwano." }
    }
    New-Item -ItemType Directory -Force -Path "$cel\docs" | Out-Null
    Copy-Item "$Source\*.sh"           $cel -Force
    Copy-Item "$Source\README.md"      $cel -Force
    Copy-Item "$Source\.gitattributes" $cel -Force
    Copy-Item "$Source\docs\*.md"      "$cel\docs" -Force
    Ok "Skopiowano do $cel"

    # ------------------------------------------------------------ kontrola LF
    Krok "Kontrola zakonczen linii (musi byc LF)"
    $zle = @()
    Get-ChildItem "$cel\*.sh" | ForEach-Object {
        $b = [IO.File]::ReadAllBytes($_.FullName)
        for ($i = 1; $i -lt $b.Length; $i++) {
            if ($b[$i] -eq 10 -and $b[$i-1] -eq 13) { $zle += $_.Name; break }
        }
    }
    if ($zle.Count -gt 0) {
        Uwaga "Pliki z CRLF - konwertuje na LF:"
        $zle | ForEach-Object { "  $_" }
        foreach ($n in $zle) {
            $p = Join-Path $cel $n
            $t = [IO.File]::ReadAllText($p) -replace "`r`n", "`n"
            [IO.File]::WriteAllText($p, $t, (New-Object Text.UTF8Encoding $false))
        }
        Ok "Przekonwertowano"
    } else {
        Ok "Wszystkie skrypty maja LF"
    }

    # ------------------------------------------------------------ prawa wykonywania
    Krok "Ustawienie bitu wykonywalnosci"
    Get-ChildItem "$cel\*.sh" | ForEach-Object {
        & git add --chmod=+x -- "$DirName/$($_.Name)" 2>&1 | Out-Null
    }
    Ok "Skrypty beda wykonywalne po sklonowaniu na Linuksie"

    # ------------------------------------------------------------ podglad
    Krok "Zmiany do zatwierdzenia"
    & git add -- $DirName
    $zmiany = & git status --porcelain -- $DirName
    if (-not $zmiany) { Uwaga "Brak zmian - repozytorium jest juz aktualne."; exit 0 }
    $zmiany | ForEach-Object { "  $_" }

    Write-Host ""
    Uwaga "Zostana zatwierdzone WYLACZNIE pliki z katalogu $DirName"
    $poza = & git status --porcelain | Where-Object { $_ -notmatch [regex]::Escape($DirName) }
    if ($poza) {
        Uwaga "Poza nim sa niezatwierdzone zmiany (NIE beda commitowane):"
        $poza | ForEach-Object { "  $_" }
    }

    Write-Host ""
    $o = Read-Host "Wykonac commit i push na galaz '$Branch'? [t/N]"
    if ($o -notmatch '^[tTyY]') { Stop-Blad "Przerwano. Pliki pozostaja przygotowane w $WorkDir" }

    # ------------------------------------------------------------ commit i push
    Krok "Commit"
    $msg = @"
Skrypty wdrozeniowe PHP 7.4 z latka CVE-2026-109618 / CVE-2026-109619

Automatyzacja wdrozenia latki na CentOS 7 + Apache 2.4.6 (prefork) + mod_php.
PHP 7.4 budowane ze zrodel jako modul Apache i instalowane obok PHP 7.2,
bez nadpisywania dotychczasowego modulu. Powrot do 7.2 jedna pozycja w menu.

Punkt wejscia: $DirName/menu.sh
Dokumentacja:  $DirName/README.md
"@
    & git commit -q -m $msg
    if ($LASTEXITCODE -ne 0) { Stop-Blad "git commit nie powiodl sie" }
    Ok "Commit utworzony"

    Krok "Push"
    & git push -u origin $Branch
    if ($LASTEXITCODE -ne 0) { Stop-Blad "git push nie powiodl sie" }
    Ok "Wyslano na origin/$Branch"

    Write-Host ""
    Write-Host "Gotowe." -ForegroundColor Green
    if ($Branch -ne $glowna) {
        Write-Host "Utworz merge request z galezi '$Branch' do '$glowna' w GitLabie."
    }
}
finally {
    Pop-Location
}

