# Środowisko testowe: CentOS 7 + Apache 2.4.6 + PHP 7.2.22 / PHP 7.4 (łatka CVE-2026-109618/109619)

Docker Desktop (WSL2). Kontener `centos7-php`, Apache na http://localhost:8080 (katalog `www/`).

| Prefix | Wersja | php-fpm |
|---|---|---|
| `/opt/php-7.2.22` | PHP 7.2.22 (odpowiednik produkcji) | 127.0.0.1:9072 |
| `/opt/php-7.4-patched` | `php/php-src` gałąź `PHP-7.4-CVE-2026-109618-109619` | 127.0.0.1:9074 |

Apache łączy się z PHP przez `mod_proxy_fcgi` (`/etc/httpd/conf.d/php-fpm.conf`), obie wersje działają równolegle.

## Obsługa

```powershell
docker compose up -d                       # start
docker compose down                        # stop (wersja 7.4 zostaje w wolumenie php-patched)
docker exec -it centos7-php bash           # shell

docker exec centos7-php switch-php         # lista wersji, * = aktywna
docker exec centos7-php switch-php 74      # Apache -> PHP 7.4 z łatką
docker exec centos7-php switch-php 72      # Apache -> PHP 7.2.22
curl.exe http://localhost:8080/index.php
```

## Przebudowa wersji z łatką (np. po nowym commicie w gałęzi)

```powershell
docker exec centos7-php build-php.sh https://github.com/php/php-src.git PHP-7.4-CVE-2026-109618-109619 /opt/php-7.4-patched 9074
docker exec centos7-php bash -c "kill `$(cat /opt/php-7.4-patched/var/run/php-fpm.pid); switch-php 74"
```

Alternatywnie z pliku patcha (położonego w `patches/`):
`build-php.sh <źródło> <ref> <prefix> <port> /patches/plik.patch`

## Testy

Smoke test obszarów zmienionych przez łatkę (sesja, upload multipart, zmienne żądania, alokator), przez Apache dla aktywnej wersji:

```powershell
docker exec centos7-php smoke-test.sh
```

Patch z gałęzi (commit `712e60f9ed` „Avoid state corruption via bailout”, GHSA-w8hw-w9fx-j79w / GHSA-6wmf-4rv5-p3rp) zapisany w `patches/`.

Testy jednostkowe php-src:

```bash
cd /usr/local/src/php-build-php-7.4-patched
TEST_PHP_EXECUTABLE=/opt/php-7.4-patched/bin/php /opt/php-7.4-patched/bin/php run-tests.php -q <katalog/plik .phpt>
```

## Wyniki (2026-10-23)

| Test | 7.2.22 | 7.4 bez łatki (`/opt/php-7.4-vanilla`) | 7.4 z łatką |
|---|---|---|---|
| smoke-test.sh (Apache + fpm) | OK | – | OK |
| php-src: Zend, session, basic, lang (3451) | – | 0 FAIL | 9 FAIL |
| `max_multipart_body_parts` | brak | brak | działa (`test-multipart-limit.sh`) |

Wszystkie 9 FAIL wynikają z zamierzonych zmian łatki:
- 8× `ext/session/tests/rfc1867*` – łatka **wyłącza `session.upload_progress`** (`if (!PS(rfc1867_enabled) || true)`). Aplikacje korzystające z paska postępu uploadu przez sesję przestaną go dostawać.
- 1× `tests/lang/bug45392` – inny format komunikatu „Allowed memory size exhausted” (dodatkowa pusta linia), kosmetyczne.

Nowe ini: `max_multipart_body_parts` (domyślnie -1 = `max_input_vars` + `max_file_uploads`). Duplikaty i nieużywane nagłówki części multipart są ignorowane.

## Uwagi
- 7.2 → 7.4 to zmiana wersji minor: sprawdzić aplikację (deprecated/usunięte funkcje, `ext/zip` wymaga libzip ≥ 0.11 – w buildzie 7.4 pominięte).
- Kontener współdzieli kernel WSL2 – nie ma to znaczenia dla podatności w samym PHP.
- Brak systemd w kontenerze; na produkcji php-fpm należy dodać jako unit systemd.
