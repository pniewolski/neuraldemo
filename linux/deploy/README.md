# Skrypty wdrożeniowe – PHP 7.4 z łatką CVE-2026-109618 / CVE-2026-109619

Automatyzacja instrukcji z `WDROZENIE.md` dla CentOS 7 + Apache 2.4.6 (prefork) + mod_php.

PHP 7.4 instalowane jest **obok** PHP 7.2, jako osobny moduł Apache. PHP 7.2 nie jest nadpisywane, a powrót do niego to jedna pozycja w menu.

---

## Jak zacząć

```bash
scp -r deploy root@SERWER:/root/
ssh root@SERWER
cd /root/deploy
sed -i 's/\r$//' *.sh      # tylko jeśli pliki szły przez Windows
chmod +x *.sh
./menu.sh
```

To wszystko. **`menu.sh` jest jedynym punktem wejścia** — prowadzi przez całe wdrożenie.

Przy pierwszym uruchomieniu wybierasz rolę serwera (testowy albo produkcyjny). Potem menu samo wykrywa stan, pokazuje, co jest już zrobione, i strzałką `-->` wskazuje zalecany następny krok.

```
===========================================================================
  Wdrożenie PHP 7.4 z łatką CVE-2026-109618 / CVE-2026-109619
===========================================================================
  System      : CentOS Linux 7 (Core)
  Rola        : SERWER TESTOWY (kompilacja)
  Apache      : działa, MPM prefork
  PHP w Apache: PHP 7.2 (podatne)
  PHP 7.2 CLI : 7.2.22
  PHP 7.4     : 7.4.34-dev   moduł Apache: tak   php.ini: tak
  Paczka      : tak (19M)
  Repozytoria : OK
---------------------------------------------------------------------------
  --> zalecany następny krok      [ok] zrobione      [  ] do zrobienia

     1) [ok] Inwentaryzacja i kopia zapasowa (nic nie zmienia)
     2) [ok] Naprawa repozytoriów yum (vault)
     3) [ok] Kompilacja PHP 7.4 + testy + paczka   (~15 min)
     4) [ok] Konfiguracja php.ini dla PHP 7.4
 --> 5) [  ] PRZEŁĄCZ Apache na PHP 7.4   (restart Apache!)
     6)      Weryfikacja (nic nie zmienia)

         7) Powrót do PHP 7.2 (rollback)
         8) Podgląd logów i plików pomocniczych
         9) Zmień rolę serwera (teraz: test)

         p) CZY SERWER JEST PODATNY? (sprawdzenie, nic nie zmienia)
         d) Diagnoza połączenia HTTP (gdy test HTTP zawodzi)
         0) Wyjście
```

Pozycje 3, 5 i 7 proszą o dodatkowe potwierdzenie. Na serwerze produkcyjnym pozycja 5 dodatkowo przypomina o oknie serwisowym.

Menu można zamknąć i uruchomić ponownie w dowolnym momencie — stan jest odczytywany z serwera, nie z pliku.

---

## Jak sprawdzić, czy serwer jest podatny

Najprościej: w menu wybierz **pozycję `p`** albo uruchom

```bash
./60-czy-podatny.sh
```

Skrypt nic nie zmienia i działa nawet wtedy, gdy nie da się wykonać żądania HTTP. Sprawdza cztery rzeczy:

1. **Który moduł ma załadowany działający proces Apache** (z `/proc/PID/maps`) — to stan bieżący.
2. **Czy plik modułu zawiera łatkę** — wyszukuje w binarce dyrektywę `max_multipart_body_parts`, która istnieje wyłącznie w wersji z łatką.
3. **Odpowiedź serwera na żądanie HTTP** — jeśli połączenie działa.
4. **PHP w linii poleceń** — dla crona i skryptów.

Kod wyjścia: `0` = załatany, `1` = podatny, `2` = nie ustalono. Można więc użyć skryptu w monitoringu.

Skrypt rozróżnia stan **bieżący** od stanu **po restarcie** i ostrzega przy rozbieżności:

```
[BŁĄD] ROZBIEZNOSC miedzy stanem biezacym a konfiguracja!
  Teraz serwer obsluguje zadania: zalatany
  Po restarcie Apache zaladuje  : podatny
```

### Sprawdzenie ręczne

Bez żadnych skryptów, z dowolnego miejsca:

```bash
# na serwerze
echo '<?php var_dump(ini_get("max_multipart_body_parts"));' > /var/www/html/t.php

# z dowolnego miejsca
curl -s http://ADRES/t.php
#   string(2) "-1"  -> łatka jest obecna
#   bool(false)     -> BRAK łatki, serwer podatny

rm -f /var/www/html/t.php      # posprzątaj po teście
```

Albo bezpośrednio na pliku modułu:

```bash
grep -qa max_multipart_body_parts /usr/lib64/httpd/modules/libphp7.so \
  && echo "z łatką" || echo "BEZ łatki"
```

Przydaje się też log Apache — przy każdym starcie zapisuje wersję PHP:

```bash
grep -o 'PHP/[0-9][^ ]*' /var/log/httpd/error_log | tail -1
```

### Przeniesienie na produkcję

Po zakończeniu pracy na serwerze testowym:

```bash
scp /root/php-7.4-patched-centos7.tgz /root/php-7.4-patched-centos7.tgz.sha256 root@PROD:/root/
scp -r /root/deploy root@PROD:/root/
```

Na produkcji uruchamiasz `./menu.sh`, wybierasz rolę **PRODUKCYJNY** i menu samo pokaże właściwą ścieżkę: zamiast kompilacji będzie instalacja paczki.

---

## Przed uruchomieniem

1. **Zrób snapshot maszyny.**
2. Przejrzyj `config.sh` i dostosuj, jeśli trzeba:

| Zmienna | Domyślnie | Kiedy zmienić |
|---|---|---|
| `TEST_URL` | `http://localhost` | gdy `localhost` trafia na inny vhost niż aplikacja |
| `DOCROOT` | `/var/www/html` | gdy `DocumentRoot` jest w innym miejscu |
| `PHP_PREFIX` | `/opt/php-7.4-patched` | rzadko |
| `CONFIGURE_FLAGS` | zestaw jak w PHP 7.2 | gdy brakuje jakiegoś rozszerzenia |

Jeśli `DOCROOT` nie pasuje do `TEST_URL`, skrypty same przeszukają `DocumentRoot` z konfiguracji Apache, znajdą działający i zapamiętają go w `/root/php74-migracja/docroot`. Mimo to warto wpisać właściwą wartość do `config.sh`.

---

## Uruchamianie pojedynczych skryptów

Menu wywołuje poniższe skrypty. Można je też uruchamiać osobno, np. w automatyzacji.

**Serwer testowy:**

```bash
./01-inwentaryzacja.sh      # spis stanu + kopia zapasowa (nic nie zmienia)
./02-repozytoria.sh         # repozytoria yum -> archiwum vault
./10-build-test.sh          # kompilacja PHP 7.4, testy, paczka (~15 min)
./30-konfiguracja-php.sh    # php.ini dla 7.4
./40-wlacz-php74.sh         # podmiana modułu w Apache + restart
./50-weryfikacja.sh         # sprawdzenie
```

**Serwer produkcyjny:**

```bash
./01-inwentaryzacja.sh
./02-repozytoria.sh         # tylko jeśli yum zgłasza błędy
./20-install-prod.sh        # rozpakowanie paczki (bez kompilatorów)
./30-konfiguracja-php.sh
./40-wlacz-php74.sh         # OKNO SERWISOWE
./50-weryfikacja.sh
```

**Powrót do PHP 7.2:** `./90-rollback-php72.sh`

---

## Co robi każdy skrypt

| Skrypt | Serwer | Zmienia stan? | Opis |
|---|---|---|---|
| `menu.sh` | oba | nie (sam) | Punkt wejścia. Wykrywa stan i uruchamia pozostałe skrypty. |
| `01-inwentaryzacja.sh` | oba | nie | Zapisuje wersje, rozszerzenia, moduły Apache i kopię `/etc/httpd` do `/root/php74-migracja`. Sprawdza, czy MPM to `prefork` i czy działa mod_php. |
| `02-repozytoria.sh` | oba | tak | Przestawia yum na `vault.centos.org`. Pomija się sam, jeśli yum już działa (wymuszenie: `FORCE=1`). |
| `10-build-test.sh` | testowy | tak | Instaluje kompilatory, buduje bison 3.x, pobiera gałąź z łatką, kompiluje PHP 7.4 jako moduł Apache, uruchamia testy, instaluje i tworzy paczkę `.tgz`. |
| `20-install-prod.sh` | produkcja | tak | Sprawdza sumę kontrolną paczki, rozpakowuje ją, instaluje biblioteki, weryfikuje zależności. |
| `30-konfiguracja-php.sh` | oba | tak | Tworzy `php.ini` dla 7.4 na bazie obecnego i sprawdza go. Wypisuje kluczowe ustawienia. |
| `40-wlacz-php74.sh` | oba | **tak** | Podmienia `LoadModule` i robi pełny restart Apache. Przy błędzie automatycznie cofa zmianę. |
| `50-weryfikacja.sh` | oba | nie | Sprawdza wersję, SAPI, `php.ini`, aktywność łatki, rozszerzenia, sesje, upload i logi. |
| `60-czy-podatny.sh` | oba | nie | Odpowiada na pytanie „czy serwer jest podatny”. Działa bez połączenia HTTP. Kod wyjścia: 0 = załatany, 1 = podatny. |
| `61-sprawdz-test-serwera.sh` | testowy | nie | Rozstrzyga, czy nieudany test z wbudowanym serwerem HTTP wynika ze środowiska, czy z kompilacji. |
| `90-rollback-php72.sh` | oba | **tak** | Przywraca PHP 7.2 i restartuje Apache. |
| `99-diagnoza-http.sh` | oba | nie | Szuka przyczyny, gdy test HTTP nie działa: nasłuch, `localhost`, zapora, SELinux, vhosty. |
| `config.sh`, `lib.sh` | — | — | Konfiguracja i wspólne funkcje. Nie uruchamia się ich bezpośrednio. |

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
| `Cannot find a valid baseurl for repo: epel` | Wybierz pozycję 2 w menu. Szczegóły: `KROK1-NAPRAWA-EPEL.md`. EPEL nie jest wymagany — można go wyłączyć: `yum-config-manager --disable epel`. |
| `Serwer zwrócił HTTP 404` / `stronę HTML zamiast wyniku skryptu PHP` | `TEST_URL` i `DOCROOT` wskazują różne miejsca. Skrypty same próbują znaleźć właściwy `DocumentRoot` i wypisują listę kandydatów oraz hosty wirtualne. Popraw `config.sh`. |
| `exit signal Segmentation fault` po wdrożeniu | Apache został przeładowany zamiast zrestartowany. Wykonaj `systemctl restart httpd`. |
| `configure` kończy się błędem | Brakuje pakietu `-devel`. Zajrzyj do `/root/php74-migracja/configure.log` (menu, pozycja 8). |
| Rozszerzenia 7.4 różnią się od 7.2 | Dopisz flagę w `CONFIGURE_FLAGS` w `config.sh` i wybierz pozycję 3 w menu (przebuduje). |
| Strona zwraca 500 po przełączeniu | Zajrzyj do `/var/log/httpd/error_log` (menu, pozycja 8). W razie potrzeby pozycja 7 — rollback. |
| Menu pokazuje `PHP w Apache: ?` | Nie rozpoznano wpisu `LoadModule`. Sprawdź plik wskazany w nawiasie (menu, pozycja 8 → 4). |
| `MPM to 'worker'/'event'` przy przełączaniu | mod_php wymaga `prefork`. Skrypt przerywa pracę — zmiana MPM to osobna decyzja. |
| Nieudany test `tests/basic/bug67198.phpt` | Test uruchamia wbudowany serwer HTTP PHP; jeśli nie zdąży wystartować, zgłasza `Server is not accepting connections`. Skrypt rozpoznaje to i nie traktuje jako błędu łatki. Szczegóły niżej. |

---

## Wyniki testów `run-tests.php` — jak je czytać

Skrypt dzieli nieudane testy na trzy grupy:

| Grupa | Przykład | Co to znaczy |
|---|---|---|
| **Zgodne z oczekiwaniem** (9) | `ext/session/tests/rfc1867*` (8), `tests/lang/bug45392.phpt` | Zamierzone zmiany łatki: wyłączenie `session.upload_progress` i inny format komunikatu o braku pamięci. |
| **Zależne od środowiska** | `tests/basic/bug67198.phpt` | Test startuje wbudowany serwer HTTP PHP i łączy się z nim. Gdy port jest zajęty albo serwer nie wstanie, test zgłasza `Server could not be started` lub `Server is not accepting connections`. |
| **Nieoczekiwane** | — | Wymagają wyjaśnienia przed wdrożeniem. Skrypt pokazuje `diff` i pyta o zgodę na kontynuację. |

Każdy podejrzany test jest uruchamiany ponownie **pojedynczo**, bo część bywa niestabilna przy zrównolegleniu (`-j`).

### Testy wymagające wbudowanego serwera HTTP

Jeśli test nadal nie przechodzi, a korzysta z wbudowanego serwera PHP, skrypt **sprawdza to empirycznie**: próbuje uruchomić taki serwer z nowego PHP 7.4 oraz z obecnego PHP 7.2 i porównuje wynik.

| PHP 7.4 | PHP 7.2 | Wniosek |
|---|---|---|
| działa | — | Niepowodzenie było chwilowe (zajęty port, obciążenie). Można kontynuować. |
| nie działa | nie działa | Ograniczenie środowiska (zapora, SELinux, porty). Nie ma związku z łatką. |
| nie działa | działa | **Wymaga wyjaśnienia** — może wskazywać na problem z kompilacją. |
| nie działa | brak PHP 7.2 | Najpewniej środowisko, ale bez porównania nie ma pewności. |

To samo sprawdzenie można uruchomić osobno, bez przebudowy — w menu **pozycja `t`** albo:

```bash
./61-sprawdz-test-serwera.sh
```

Sprawdziłem `bug67198.phpt` na dwóch kompilacjach tego samego kodu — z łatką i bez niej. Wynik był identyczny (5 niepowodzeń na 5 prób w obu), więc **test nie ma związku z łatką**.

Jeśli kiedyś pojawi się test z grupy „nieoczekiwane”, najpewniejszy sposób sprawdzenia to zbudowanie obok wersji bez łatki i porównanie:

```bash
cd /usr/local/src/php-7.4-patched
git fetch --depth 1 origin PHP-7.4 && git checkout FETCH_HEAD    # gałąź bez łatki
# ... configure + make, potem ten sam test
```

---

## Dwie dyrektywy LoadModule (pakiety remi)

Plik `15-php.conf` z remi zawiera dwa warianty modułu:

```apache
<IfModule prefork.c>
    LoadModule php7_module modules/libphp7.so        <-- ten podmieniamy
</IfModule>
<IfModule !prefork.c>
    LoadModule php7_module modules/libphp7-zts.so    <-- zostaje bez zmian
</IfModule>
```

Skrypty podmieniają wyłącznie wariant `libphp7.so` (prefork) i sprawdzają, czy zmieniła się dokładnie jedna dyrektywa. Wariant `-zts` dotyczy MPM wielowątkowych i na tym serwerze nie jest używany. Przed podmianą skrypt dodatkowo weryfikuje, że MPM to `prefork`.

---

## Stan sprawdzony

Skrypty przetestowano na kontenerze CentOS 7.9 z Apache 2.4.6 (prefork) i PHP 7.4.34-dev zbudowanym z gałęzi z łatką: składnia wszystkich plików, menu (obie role, podmenu logów, ostrzeżenia i odmowa potwierdzenia), inwentaryzacja, konfiguracja `php.ini`, tworzenie i instalacja paczki, podmiana modułu wraz z automatycznym cofnięciem przy błędzie, pełna weryfikacja (wszystkie sprawdzenia OK) oraz rollback.

Restart przez `systemctl` nie był testowany, bo kontener nie ma systemd — w tej sytuacji skrypty używają `apachectl`. Na docelowym serwerze z systemd działa główna ścieżka.






