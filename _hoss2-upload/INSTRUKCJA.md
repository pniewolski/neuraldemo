# Wgranie skryptów do repozytorium hoss2-dev-environment

Skrypty są gotowe w katalogu `_hoss2-upload\php74-cve-2026-109618-109619`.
Brakuje tylko dostępu do repozytorium — klucz SSH nie jest na nim autoryzowany.

```
git@git.mccomp.pl: Permission denied (publickey,gssapi-keyex,gssapi-with-mic,password)
```

## Krok 1 — odblokuj dostęp (jednorazowo)

Wybierz jedną z opcji.

### A. Personal Access Token (HTTPS) — najprostsze

1. Wejdź: **https://git.mccomp.pl/-/user_settings/personal_access_tokens**
2. **Token name**: `wdrozenie-php74`, **Scopes**: zaznacz **`write_repository`**.
3. **Create personal access token** i skopiuj token (`glpat-...`) — pokazywany tylko raz.
4. Uruchom wgrywanie z tokenem:
   ```powershell
   C:\p\PhpstormProjects\_hoss2-upload\wgraj.ps1 -Token glpat-xxxxxxxxxxxx
   ```
   Token jest używany tylko do operacji git i **nie jest zapisywany** w konfiguracji repozytorium.

### B. Klucz SSH

Ten klucz publiczny jest już na Twojej maszynie (`%USERPROFILE%\.ssh\id_ed25519.pub`):

```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN0GAfRUDmarhln+ctJGObdcRrcyiL8HBhXvnZ/kveL1 copilot-wdrozenie
```

Dodaj go w GitLabie: **Preferences → SSH Keys → Add new key**. Sprawdzenie: `ssh -T git@git.mccomp.pl`.

### C. Użyj własnego klucza SSH, jeśli masz już inny

```powershell
$env:GIT_SSH_COMMAND = "ssh -i $env:USERPROFILE\.ssh\TWOJ_KLUCZ"
```

## Krok 2 — wgranie

```powershell
# z tokenem (HTTPS)
C:\p\PhpstormProjects\_hoss2-upload\wgraj.ps1 -Token glpat-xxxxxxxxxxxx

# albo przez SSH (gdy dodałeś klucz)
C:\p\PhpstormProjects\_hoss2-upload\wgraj.ps1
```

Skrypt sam:

1. sklonuje repozytorium do `C:\p\PhpstormProjects\hoss2-dev-environment`,
2. sprawdzi, czy katalog `php74-cve-2026-109618-109619` już tam nie istnieje,
3. skopiuje pliki,
4. zweryfikuje, że skrypty mają zakończenia linii **LF** (przy CRLF nie uruchomią się na CentOS-ie),
5. pokaże listę plików do zatwierdzenia i **poprosi o potwierdzenie**,
6. wykona commit i push na nową gałąź `php74-cve-2026-109618-109619`.

Domyślnie powstaje **gałąź**, a nie commit na `main` — dzięki temu możesz spokojnie przejrzeć zmiany
przez merge request. Aby wrzucić od razu na gałąź główną:

```powershell
C:\p\PhpstormProjects\_hoss2-upload\wgraj.ps1 -Branch main
```

## Co trafia do repozytorium

```
php74-cve-2026-109618-109619/
├── .gitattributes          wymusza LF dla .sh i .md
├── README.md               przewodnik, od tego zaczyna się czytanie
├── menu.sh                 punkt wejścia
├── config.sh, lib.sh       konfiguracja i wspólne funkcje
├── 01-inwentaryzacja.sh    spis stanu + kopia zapasowa
├── 02-repozytoria.sh       naprawa yum (vault)
├── 10-build-test.sh        kompilacja na serwerze testowym
├── 20-install-prod.sh      instalacja paczki na produkcji
├── 30-konfiguracja-php.sh  php.ini dla 7.4
├── 40-wlacz-php74.sh       podmiana modułu + restart
├── 50-weryfikacja.sh       weryfikacja po wdrożeniu
├── 60-czy-podatny.sh       czy serwer jest podatny
├── 61-sprawdz-test-serwera.sh   diagnoza nieudanego testu
├── 90-rollback-php72.sh    powrót do PHP 7.2
├── 99-diagnoza-http.sh     diagnoza połączenia HTTP
└── docs/
    ├── WDROZENIE.md
    ├── KROK1-NAPRAWA-EPEL.md
    ├── KROK5-ROZSZERZENIA.md
    └── KROK5-PRZEBUDOWA.md
```

**Nie trafia** tam środowisko testowe Dockera (`docker/`, `docker-compose.yml`, `www/`, `patches/`)
ani nic spoza katalogu `php74-cve-2026-109618-109619`.


