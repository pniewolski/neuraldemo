# Przebudowa PHP 7.4 z rozszerzeniami jak w 7.2

**Kiedy:** PHP 7.4 jest już zainstalowane w `/opt/php-7.4-patched`, ale z pierwszym, ogólnym zestawem rozszerzeń (gd, intl, mbstring, PDO itd.).
**Cel:** podmienić je na build z tym samym zestawem rozszerzeń co PHP 7.2.

Obecne PHP 7.2 i Apache **nie są** dotykane.

---

## 1. Sprawdź, na jakim etapie jesteś

```bash
ls /opt/php-7.4-patched/etc/                      # są tu pliki .ini/.conf?
systemctl is-active php74-fpm 2>/dev/null         # usługa php74-fpm działa?
ls /etc/httpd/conf.d/ | grep php74                # Apache przełączony na 7.4?
```

| Wynik | Co to znaczy | Co robisz |
|---|---|---|
| `etc/` pusty lub tylko `php-fpm.conf.default`, usługa `inactive`/`unknown`, brak `php74-fpm.conf` | wykonany tylko `make install` (krok 5) | **wariant A** |
| są `php.ini` / `php-fpm.conf` / `php-fpm.d/www.conf`, ale Apache **nie** przełączony | wykonany krok 6 lub 7 | **wariant B** |
| jest `/etc/httpd/conf.d/php74-fpm.conf` | Apache już używa 7.4 | **wariant C** |

---

## 2A. Wariant A – był tylko `make install`

```bash
cd /usr/local/src/php-7.4-patched

# 1) biblioteki dla bz2, readline, gettext
yum -y install bzip2-devel readline-devel gettext-devel

# 2) usunięcie poprzedniej kompilacji i instalacji
make distclean                  # czyści wynik poprzedniego configure/make w katalogu źródeł
rm -rf /opt/php-7.4-patched     # usuwa poprzednią instalację (nic tam jeszcze nie konfigurowałeś)
```

Przejdź do **3. Budowanie**.

## 2B. Wariant B – jest już konfiguracja (krok 6/7), Apache jeszcze na 7.2

```bash
cd /usr/local/src/php-7.4-patched
yum -y install bzip2-devel readline-devel gettext-devel

# 1) zatrzymanie php-fpm 7.4 (jeśli działa) – Apache dalej obsługuje stronę przez 7.2
systemctl stop php74-fpm 2>/dev/null

# 2) kopia konfiguracji z kroku 6
cp -a /opt/php-7.4-patched/etc /root/php74-migracja/php74-etc-backup

# 3) usunięcie poprzedniej kompilacji i instalacji
make distclean
rm -rf /opt/php-7.4-patched
```

Przejdź do **3. Budowanie**, a potem do **4B**.

## 2C. Wariant C – Apache już działa na 7.4

Najpierw **wróć z Apache na 7.2** (krok 12 w `WDROZENIE.md`), żeby strona działała w czasie przebudowy:

```bash
mv /etc/httpd/conf.d/php74-fpm.conf /root/php74-migracja/php74-fpm.conf.saved
mv /etc/httpd/conf.modules.d/15-php.conf.disabled /etc/httpd/conf.modules.d/15-php.conf   # nazwa wg Twojego serwera (10- lub 15-)
mv /etc/httpd/conf.d/php.conf.disabled /etc/httpd/conf.d/php.conf
httpd -t && systemctl reload httpd       # strona znowu działa na PHP 7.2
```

Następnie wykonaj **2B** w całości, potem **3**, a na końcu **4C**.

---

## 3. Budowanie (wszystkie warianty)

```bash
cd /usr/local/src/php-7.4-patched

./buildconf --force       # odtworzenie skryptu configure po distclean

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

Na końcu `configure` musi być `Thank you for using PHP.`, bez linii `error:`.

```bash
make -j"$(nproc)"         # kompilacja – kilka minut
```

```bash
# testy obszarów zmienionych przez łatkę (ok. 1 min)
TEST_PHP_EXECUTABLE=sapi/cli/php sapi/cli/php run-tests.php -j"$(nproc)" -q \
    -d opcache.enable_cli=0 Zend/tests ext/session/tests tests/basic tests/lang
```

Oczekiwane FAIL to tylko `ext/session/tests/rfc1867*` (8 testów) i `tests/lang/bug45392.phpt`. To zamierzone zmiany łatki.
Testów SKIP będzie więcej niż poprzednio, bo część rozszerzeń jest wyłączona. To normalne.

```bash
make install              # instalacja do /opt/php-7.4-patched

/opt/php-7.4-patched/bin/php -v
diff <(php -m | sort -f) <(/opt/php-7.4-patched/bin/php -m | sort -f) && echo "IDENTYCZNE"
```

Oczekiwany wynik: `IDENTYCZNE`. Jeśli `diff` pokaże różnice, wklej je.

---

## 4. Po przebudowie

### 4A. Wariant A

Przejdź do **kroku 6** w `WDROZENIE.md` (konfiguracja php.ini i php-fpm). **Nie twórz** pliku `10-opcache.ini`.

### 4B. Wariant B – przywrócenie konfiguracji

```bash
cp -a /root/php74-migracja/php74-etc-backup/. /opt/php-7.4-patched/etc/   # przywraca php.ini, php-fpm.conf, php-fpm.d/
rm -f /opt/php-7.4-patched/etc/conf.d/10-opcache.ini                     # opcache wyłączony, jak w 7.2

# kontrola: brak ostrzeżeń o brakujących rozszerzeniach i poprawna konfiguracja FPM
/opt/php-7.4-patched/bin/php -c /opt/php-7.4-patched/etc/php.ini -r 'echo "OK\n";'
/opt/php-7.4-patched/sbin/php-fpm -t -y /opt/php-7.4-patched/etc/php-fpm.conf

systemctl start php74-fpm && systemctl status php74-fpm --no-pager
```

Dalej kontynuuj od miejsca, w którym przerwałeś w `WDROZENIE.md`.

### 4C. Wariant C – ponowne przełączenie Apache na 7.4

Najpierw wykonaj **4B**, potem:

```bash
mv /etc/httpd/conf.modules.d/15-php.conf /etc/httpd/conf.modules.d/15-php.conf.disabled
mv /etc/httpd/conf.d/php.conf /etc/httpd/conf.d/php.conf.disabled
cp /root/php74-migracja/php74-fpm.conf.saved /etc/httpd/conf.d/php74-fpm.conf
httpd -t && systemctl reload httpd
```

Weryfikacja jak w kroku 10 `WDROZENIE.md`.

---

## 5. Paczka na produkcję

Jeśli paczka `.tgz` była już zrobiona, utwórz ją **od nowa**, bo stara zawiera poprzedni build:

```bash
rm -f /root/php-7.4-patched-centos7.tgz /root/php-7.4-patched-centos7.tgz.sha256
tar czf /root/php-7.4-patched-centos7.tgz -C /opt php-7.4-patched
sha256sum /root/php-7.4-patched-centos7.tgz > /root/php-7.4-patched-centos7.tgz.sha256
```

Paczka zawiera też `/opt/php-7.4-patched/etc` z konfiguracją z testu. Na produkcji przejrzyj ją przed uruchomieniem, szczególnie `session.save_path` i ścieżki logów.

