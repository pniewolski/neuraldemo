# Krok 5 (poprawka): rozszerzenia PHP 7.4 identyczne jak w PHP 7.2

## Porównanie `php -m`

| Rozszerzenie | 7.2 (produkcja) | 7.4 (pierwszy build) | Decyzja |
|---|---|---|---|
| `bz2` | ✅ | ❌ | dodać `--with-bz2` |
| `ftp` | ✅ | ❌ | dodać `--enable-ftp` |
| `gettext` | ✅ | ❌ | dodać `--with-gettext` |
| `pcntl` | ✅ | ❌ | dodać `--enable-pcntl` (działa tylko w CLI) |
| `readline` | ✅ | ❌ | dodać `--with-readline` (działa tylko w CLI) |
| `bcmath gd intl mbstring soap xsl` | ❌ | ✅ | usunąć (nie dodawać flag) |
| `mysqli mysqlnd PDO pdo_mysql pdo_sqlite sqlite3` | ❌ | ✅ | usunąć (`--disable-pdo --without-sqlite3`) |
| `dom SimpleXML xml xmlreader xmlwriter` | ❌ | ✅ | usunąć (`--disable-dom ...`) |
| `posix` | ❌ | ✅ | usunąć (`--disable-posix`) |
| `opcache` | ❌ | wkompilowany | nie włączać w kroku 6 (jak w 7.2) |
| pozostałe 22 | ✅ | ✅ | bez zmian |

Cel: ten sam zestaw rozszerzeń co w 7.2. Aplikacja zachowuje się tak samo, kod z `function_exists()` czy `extension_loaded()` daje te same wyniki, a ilość kodu narażonego na podatności jest najmniejsza.

---

## 5.0 Sprawdzenie, czy Apache (mod_php) nie ładuje więcej rozszerzeń niż CLI

`php -m` pokazuje rozszerzenia dla **CLI**. W remi Apache używa tego samego `/etc/php.d`, więc lista zwykle jest identyczna. Mimo to sprawdź:

```bash
echo '<?php echo implode("\n", get_loaded_extensions()), "\n";' > /var/www/html/_ext.php
curl -s http://localhost/_ext.php | sort > /root/php74-migracja/php72-modules-apache.txt
rm -f /var/www/html/_ext.php                              # usuń stronę testową od razu

# porównanie z listą CLI (ignorujemy wielkość liter i nagłówki)
php -m | grep -v '^\[' | grep -v '^$' | sort -f > /tmp/cli.txt
sort -f /root/php74-migracja/php72-modules-apache.txt | diff -i /tmp/cli.txt -
```

Oczekiwany wynik: różnice tylko w `pcntl` i `readline` (te są tylko w CLI) albo brak różnic.
Jeśli Apache ma **dodatkowe** rozszerzenia, dopisz je do `configure` w 5.3.

Jeśli `localhost` nie odpowiada albo trafia na inny vhost, podmień adres na właściwą domenę lub `DocumentRoot`.

---

## 5.1 Dodatkowe biblioteki do kompilacji

```bash
yum -y install bzip2-devel readline-devel gettext-devel
```

| Pakiet | Dla rozszerzenia |
|---|---|
| `bzip2-devel` | `bz2` |
| `readline-devel` | `readline` (interaktywne `php -a`) |
| `gettext-devel` | `gettext` |

---

## 5.2 Usunięcie poprzedniego buildu

```bash
cd /usr/local/src/php-7.4-patched
make distclean                          # usuwa skompilowane obiekty i wynik poprzedniego configure

# poprzednia instalacja – w /opt nie ma jeszcze konfiguracji (krok 6 nie był wykonany)
ls /opt/php-7.4-patched/etc/            # jeśli są tu pliki .ini/.conf z kroku 6 – najpierw je skopiuj
rm -rf /opt/php-7.4-patched             # usuwa poprzednią instalację z nadmiarowymi rozszerzeniami
```

---

## 5.3 Configure z rozszerzeniami jak w 7.2

```bash
./buildconf --force

./configure \
  --prefix=/opt/php-7.4-patched \
  --with-config-file-path=/opt/php-7.4-patched/etc \
  --with-config-file-scan-dir=/opt/php-7.4-patched/etc/conf.d \
  --enable-fpm --with-fpm-user=apache --with-fpm-group=apache \
  --with-openssl --with-zlib --with-curl --with-bz2 \
  --enable-calendar --enable-exif --enable-ftp --with-gettext \
  --enable-sockets --enable-pcntl --with-readline \
  --enable-opcache \
  --disable-dom --disable-simplexml --disable-xml --disable-xmlreader --disable-xmlwriter \
  --disable-pdo --without-pdo-sqlite --without-sqlite3 \
  --disable-posix --disable-mbstring
```

| Opcja | Znaczenie |
|---|---|
| `--prefix`, `--with-config-file-*`, `--enable-fpm ...` | jak poprzednio: osobny katalog, własny php.ini, php-fpm jako `apache` |
| `--with-openssl --with-zlib --with-curl --with-bz2` | openssl, zlib, curl, bz2 |
| `--enable-calendar --enable-exif --enable-ftp --with-gettext` | calendar, exif, ftp, gettext |
| `--enable-sockets --enable-pcntl --with-readline` | sockets, pcntl (CLI), readline (CLI) |
| `--enable-opcache` | buduje `opcache.so`, ale **nie włącza** go (decyzja w kroku 6) |
| `--disable-dom ... --disable-xmlwriter` | wyłącza rozszerzenia XML, które w 7.4 są domyślnie włączone. `libxml` zostaje, tak jak w 7.2. |
| `--disable-pdo --without-pdo-sqlite --without-sqlite3` | wyłącza PDO i SQLite, domyślnie włączone w 7.4 |
| `--disable-posix --disable-mbstring` | wyłącza posix (domyślnie włączony) i upewnia się, że mbstring nie jest budowany |

Pozostałe rozszerzenia z listy 7.2 (ctype, fileinfo, filter, hash, iconv, json, Phar, session, tokenizer, Reflection, SPL, standard, date, pcre, Core) są w 7.4 włączone domyślnie.

Na końcu `configure` musi pojawić się `Thank you for using PHP.` i nie może być linii `error:`.

---

## 5.4 Kompilacja, testy, instalacja

```bash
make -j"$(nproc)"

# testy obszarów zmienionych przez łatkę
TEST_PHP_EXECUTABLE=sapi/cli/php sapi/cli/php run-tests.php -j"$(nproc)" -q \
    -d opcache.enable_cli=0 Zend/tests ext/session/tests tests/basic tests/lang
```

Oczekiwane nieudane testy to wyłącznie zamierzone zmiany łatki:
`ext/session/tests/rfc1867*` (8 testów) oraz `tests/lang/bug45392.phpt`.
Więcej testów zostanie pominiętych (SKIP), bo część rozszerzeń jest wyłączona. To normalne.

```bash
make install
```

---

## 5.5 Weryfikacja zgodności rozszerzeń

```bash
diff <(php -m) <(/opt/php-7.4-patched/bin/php -m) && echo "IDENTYCZNE"
```

Oczekiwany wynik: `IDENTYCZNE`.
Dopuszczalna różnica to tylko kolejność albo wielkość liter, np. `Phar` / `phar`. Wtedy porównaj tak:

```bash
diff <(php -m | sort -f) <(/opt/php-7.4-patched/bin/php -m | sort -f)
```

---

## 5.6 Paczka na produkcję

```bash
tar czf /root/php-7.4-patched-centos7.tgz \
    -C / opt/php-7.4-patched usr/lib64/httpd/modules/libphp74-patched.so
sha256sum /root/php-7.4-patched-centos7.tgz > /root/php-7.4-patched-centos7.tgz.sha256
```

Na produkcji (krok 5P) biblioteki uruchomieniowe dla tego zestawu to:

```bash
yum -y install openssl-libs zlib libcurl bzip2-libs readline libxml2 ncurses-libs
ldd /usr/lib64/httpd/modules/libphp74-patched.so /opt/php-7.4-patched/bin/php | grep 'not found'   # musi być PUSTE
```

---

## Uwaga do kroku 6: opcache

PHP 7.2 działa **bez opcache**. Żeby zachowanie było takie samo, **nie twórz** pliku `conf.d/10-opcache.ini`.
Opcache można włączyć później jako osobną zmianę wydajnościową, po stabilizacji.

