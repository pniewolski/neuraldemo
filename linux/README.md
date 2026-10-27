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

```bash
cd /usr/local/src/php-build-php-7.4-patched
TEST_PHP_EXECUTABLE=/opt/php-7.4-patched/bin/php /opt/php-7.4-patched/bin/php run-tests.php -q <katalog/plik .phpt>
```

## Uwagi
- 7.2 → 7.4 to zmiana wersji minor: sprawdzić aplikację (deprecated/usunięte funkcje, `ext/zip` wymaga libzip ≥ 0.11 – w buildzie 7.4 pominięte).
- Kontener współdzieli kernel WSL2 – nie ma to znaczenia dla podatności w samym PHP.
- Brak systemd w kontenerze; na produkcji php-fpm należy dodać jako unit systemd.

