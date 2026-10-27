# Skrypty wdrożeniowe – PHP 7.4 z łatką CVE-2026-109618 / CVE-2026-109619

Automatyzacja instrukcji z `WDROZENIE.md` dla CentOS 7 + Apache 2.4.6 (prefork) + mod_php.

PHP 7.4 instalowane jest **obok** PHP 7.2, jako osobny moduł Apache. PHP 7.2 nie jest nadpisywane, a powrót do niego to jeden skrypt.

---

## Przed uruchomieniem

1. **Zrób snapshot maszyny.**
2. Skopiuj katalog na serwer i nadaj prawa wykonywania:

```bash
scp -r deploy root@SERWER:/root/
ssh root@SERWER
cd /root/deploy
sed -i 's/\r$//' *.sh      # tylko jeśli pliki szły przez Windows
chmod +x *.sh
```

3. Przejrzyj `config.sh` i dostosuj, jeśli trzeba:

| Zmienna | Domyślnie | Kiedy zmienić |
|---|---|---|
| `TEST_URL` | `http://localhost` | gdy `localhost` trafia na inny vhost niż aplikacja |
| `DOCROOT` | `/var/www/html` | gdy `DocumentRoot` jest w innym miejscu |
| `PHP_PREFIX` | `/opt/php-7.4-patched` | rzadko |
| `CONFIGURE_FLAGS` | zestaw jak w PHP 7.2 | gdy brakuje jakiegoś rozszerzenia |

---

## Kolejność: serwer TESTOWY

```bash
./01-inwentaryzacja.sh      # spis stanu + kopia zapasowa (nic nie zmienia)
./02-repozytoria.sh         # repozytoria yum -> archiwum vault (CentOS 7 jest EOL)
./10-build-test.sh          # kompilacja PHP 7.4, testy, paczka na produkcję (kilkanaście minut)
./30-konfiguracja-php.sh    # php.ini dla 7.4 na bazie obecnego
./40-wlacz-php74.sh         # podmiana modułu w Apache + restart
./50-weryfikacja.sh         # sprawdzenie, czy wszystko działa
```

Następnie **przetestuj aplikację**: logowanie, sesje, upload plików, formularze, logi.

## Kolejność: serwer PRODUKCYJNY

Najpierw przenieś paczkę i skrypty z serwera testowego:

```bash
scp /root/php-7.4-patched-centos7.tgz /root/php-7.4-patched-centos7.tgz.sha256 root@PROD:/root/
scp -r /root/deploy root@PROD:/root/
```

Potem na produkcji:

```bash
./01-inwentaryzacja.sh      # spis stanu + kopia zapasowa
./02-repozytoria.sh         # tylko jeśli yum zgłasza błędy
./20-install-prod.sh        # rozpakowanie paczki (bez kompilatorów)
./30-konfiguracja-php.sh    # php.ini dla 7.4
./40-wlacz-php74.sh         # podmiana modułu + restart  <-- OKNO SERWISOWE
./50-weryfikacja.sh         # sprawdzenie
```

## Powrót do PHP 7.2

```bash
./90-rollback-php72.sh
```

Działa w każdym momencie po kroku 40. Przywraca kopię pliku `LoadModule` i restartuje Apache.

---

## Co robi każdy skrypt

| Skrypt | Serwer | Zmienia stan? | Opis |
|---|---|---|---|
| `01-inwentaryzacja.sh` | oba | nie | Zapisuje wersje, rozszerzenia, moduły Apache i kopię `/etc/httpd` do `/root/php74-migracja`. Sprawdza, czy MPM to `prefork` i czy działa mod_php. |
| `02-repozytoria.sh` | oba | tak | Przestawia yum na `vault.centos.org`. Pomija się sam, jeśli yum już działa (wymuszenie: `FORCE=1`). |
| `10-build-test.sh` | testowy | tak | Instaluje kompilatory, buduje bison 3.x, pobiera gałąź z łatką, kompiluje PHP 7.4 jako moduł Apache, uruchamia testy, instaluje i tworzy paczkę `.tgz`. |
| `20-install-prod.sh` | produkcja | tak | Sprawdza sumę kontrolną paczki, rozpakowuje ją, instaluje biblioteki, weryfikuje zależności. |
| `30-konfiguracja-php.sh` | oba | tak | Tworzy `php.ini` dla 7.4 na bazie obecnego i sprawdza go. Wypisuje kluczowe ustawienia. |
| `40-wlacz-php74.sh` | oba | **tak** | Podmienia `LoadModule` i robi pełny restart Apache. Przy błędzie automatycznie cofa zmianę. |
| `50-weryfikacja.sh` | oba | nie | Sprawdza wersję, SAPI, `php.ini`, aktywność łatki, rozszerzenia, sesje, upload i logi. |
| `90-rollback-php72.sh` | oba | **tak** | Przywraca PHP 7.2 i restartuje Apache. |

---

## Zmienne środowiskowe

| Zmienna | Działanie |
|---|---|
| `ASSUME_YES=1` | pomija pytania o potwierdzenie (do automatyzacji) |
| `FORCE=1` | `02-repozytoria.sh`: wymusza zmianę repo; `30-konfiguracja-php.sh`: nadpisuje istniejący `php.ini` |
| `REBUILD=1` | `10-build-test.sh`: przebudowuje, nawet jeśli PHP 7.4 jest już zainstalowane |
| `SKIP_TESTS=1` | `10-build-test.sh`: pomija `run-tests.php` (niezalecane) |

Przykład: `ASSUME_YES=1 ./10-build-test.sh`

---

## Zabezpieczenia wbudowane w skrypty

- **Moduł PHP 7.2 nie jest nadpisywany.** Skrypty celowo nie używają `make install` (przy `--with-apxs2` nadpisałoby ono `libphp7.so` i zmieniło `httpd.conf`). Dodatkowo porównywana jest suma kontrolna modułu 7.2 przed instalacją i po niej.
- **Pełny restart zamiast przeładowania.** Przy podmianie mod_php `reload`, `graceful` i `httpd -k restart` powodują segfaulty. Skrypty zawsze robią pełny restart.
- **Automatyczne cofnięcie przy błędzie.** Jeśli `httpd -t` albo restart zawiedzie, `40-wlacz-php74.sh` sam przywraca PHP 7.2.
- **Kopie zapasowe.** Konfiguracja Apache, pliki repo i plik `LoadModule` trafiają do `/root/php74-migracja`.
- **Logi.** Każde uruchomienie zapisuje pełny log do `/root/php74-migracja/<nazwa>-<data>.log`.
- **Weryfikacja commita.** `10-build-test.sh` sprawdza, czy gałąź wskazuje na oczekiwany commit łatki, i pyta o zgodę, jeśli jest inny.

---

## Czego skrypty NIE robią

- Nie uruchamiają `yum update` na całym systemie (zaktualizowałby PHP 7.2 z remi).
- Nie zmieniają `/etc/php.ini`, `/etc/php.d/` ani `/etc/httpd/conf.d/php.conf`.
- Nie podmieniają PHP w linii poleceń. `php` i cron nadal używają 7.2 — opis w kroku 10 `WDROZENIE.md`.
- Nie testują samej aplikacji. To trzeba zrobić ręcznie.

---

## Typowe problemy

| Objaw | Przyczyna i rozwiązanie |
|---|---|
| `Cannot find a valid baseurl for repo: epel` | Uruchom `./02-repozytoria.sh`. Szczegóły: `KROK1-NAPRAWA-EPEL.md`. EPEL nie jest wymagany — można go wyłączyć: `yum-config-manager --disable epel`. |
| `Brak odpowiedzi z http://localhost` | Ustaw `TEST_URL` w `config.sh` na adres działającego vhosta. |
| `exit signal Segmentation fault` po wdrożeniu | Apache został przeładowany zamiast zrestartowany. Wykonaj `systemctl restart httpd`. |
| `configure` kończy się błędem | Brakuje pakietu `-devel`. Zajrzyj do `/root/php74-migracja/configure.log`. |
| Rozszerzenia 7.4 różnią się od 7.2 | Dopisz flagę w `CONFIGURE_FLAGS` w `config.sh` i uruchom `REBUILD=1 ./10-build-test.sh`. |
| Strona zwraca 500 po przełączeniu | Zajrzyj do `/var/log/httpd/error_log`. W razie potrzeby: `./90-rollback-php72.sh`. |

---

## Stan sprawdzony

Skrypty przetestowano na kontenerze CentOS 7.9 z Apache 2.4.6 (prefork) i PHP 7.4.34-dev zbudowanym z gałęzi z łatką:
składnia wszystkich plików, inwentaryzacja, konfiguracja `php.ini`, tworzenie i instalacja paczki, podmiana modułu wraz z automatycznym cofnięciem przy błędzie, pełna weryfikacja (wszystkie sprawdzenia OK) oraz rollback.

Restart przez `systemctl` nie był testowany, bo kontener nie ma systemd — w tej sytuacji skrypty używają `apachectl`. Na docelowym serwerze z systemd działa główna ścieżka.

