# Konfiguracja wdrożenia PHP 7.4 (łatka CVE-2026-109618 / CVE-2026-109619)
# Plik wczytywany przez wszystkie skrypty. Zmień wartości, jeśli Twój serwer różni się od domyślnych.

# Gałąź i oczekiwany commit łatki (weryfikowany po sklonowaniu)
PHP_REPO="https://github.com/php/php-src.git"
PHP_BRANCH="PHP-7.4-CVE-2026-109618-109619"
PHP_COMMIT="712e60f9edfd03f0960fc4fc3c2c375f42b90aa2"

# Katalog instalacji PHP 7.4 (CLI, php.ini, nagłówki)
PHP_PREFIX="/opt/php-7.4-patched"

# Nazwa modułu Apache dla PHP 7.4 – celowo inna niż libphp7.so z remi (PHP 7.2)
MOD_NAME="libphp74-patched.so"
MOD_DIR="/usr/lib64/httpd/modules"

# Katalog roboczy: kopie zapasowe, inwentaryzacja, logi
WORKDIR="/root/php74-migracja"

# Katalog źródeł na serwerze testowym
SRCDIR="/usr/local/src/php-7.4-patched"

# Paczka przenoszona na produkcję
PKG="/root/php-7.4-patched-centos7.tgz"

# Wersja bison budowana ze źródeł (CentOS 7 ma 2.7, PHP 7.4 wymaga >= 3.0)
BISON_VER="3.0.5"

# Adres używany do testów HTTP. Zmień, jeśli localhost trafia na niewłaściwy vhost.
TEST_URL="http://localhost"

# DocumentRoot, w którym skrypty tworzą tymczasowe pliki testowe (i od razu je kasują)
DOCROOT="/var/www/html"

# Flagi configure – zestaw rozszerzeń identyczny jak w PHP 7.2 na tym serwerze.
# Porównanie i uzasadnienie: KROK5-ROZSZERZENIA.md
CONFIGURE_FLAGS=(
  --prefix="$PHP_PREFIX"
  --with-config-file-path="$PHP_PREFIX/etc"
  --with-config-file-scan-dir="$PHP_PREFIX/etc/conf.d"
  --with-apxs2=/usr/bin/apxs
  --with-openssl --with-zlib --with-curl --with-bz2
  --enable-calendar --enable-exif --enable-ftp --with-gettext
  --enable-sockets --enable-pcntl --with-readline
  --enable-opcache
  --disable-dom --disable-simplexml --disable-xml --disable-xmlreader --disable-xmlwriter
  --disable-pdo --without-pdo-sqlite --without-sqlite3
  --disable-posix --disable-mbstring
)

# Pakiety do kompilacji (tylko serwer testowy)
BUILD_PKGS=(
  gcc make autoconf automake libtool re2c pkgconfig git patch
  httpd-devel libxml2-devel openssl-devel zlib-devel libcurl-devel
  bzip2-devel readline-devel gettext-devel
)

# Biblioteki uruchomieniowe (serwer produkcyjny)
RUNTIME_PKGS=(openssl-libs zlib libcurl bzip2-libs readline libxml2 ncurses-libs)

