#!/bin/bash
# Użycie:
#   build-php.sh <źródło> <ref|""> <prefix> <port-fpm> [plik.patch]
#   źródło: URL do tarballa (.tar.gz/.tar.xz/.tar.bz2), URL repo git albo lokalny katalog
#   ref:    gałąź/tag/commit dla gita (pusty dla tarballa/katalogu)
# Przykład:
#   build-php.sh https://github.com/ORG/php-src.git PHP-7.4-CVE-2026-109618-109619 /opt/php-7.4-patched 9074
set -euo pipefail

SRC="${1:?źródło}"; REF="${2:-}"; PREFIX="${3:?prefix}"; PORT="${4:?port}"; PATCH="${5:-}"
WORK="/usr/local/src/php-build-$(basename "$PREFIX")"
rm -rf "$WORK"; mkdir -p "$WORK"; cd "$WORK"

echo "==> Pobieranie: $SRC ${REF:+($REF)}"
case "$SRC" in
  *.tar.gz|*.tgz|*.tar.xz|*.tar.bz2)
    curl -fsSL "$SRC" -o src.tar || curl -fsSL "https://museum.php.net/php7/$(basename "$SRC")" -o src.tar
    tar xf src.tar --strip-components=1 && rm -f src.tar ;;
  /*)
    cp -a "$SRC"/. . ;;
  *)
    git clone --depth 1 ${REF:+--branch "$REF"} "$SRC" . ;;
esac

if [ -n "$PATCH" ]; then
  echo "==> Nakładanie patcha $PATCH"
  patch -p1 < "$PATCH"
fi

MAJ=$(awk '/define PHP_MAJOR_VERSION/{print $3}' main/php_version.h)
MIN=$(awk '/define PHP_MINOR_VERSION/{print $3}' main/php_version.h)
VER=$(awk -F'"' '/define PHP_VERSION /{print $2}' main/php_version.h)
echo "==> Wersja źródeł: $VER"

[ -f configure ] || ./buildconf --force

COMMON=(
  --prefix="$PREFIX"
  --with-config-file-path="$PREFIX/etc"
  --with-config-file-scan-dir="$PREFIX/etc/conf.d"
  --enable-fpm --with-fpm-user=apache --with-fpm-group=apache
  --with-openssl --with-zlib --with-curl --with-xsl
  --enable-mbstring --enable-intl --enable-soap --enable-bcmath
  --enable-sockets --enable-opcache --enable-exif --enable-calendar
  --with-mysqli=mysqlnd --with-pdo-mysql=mysqlnd --with-pdo-sqlite
)
if [ "$MAJ" -eq 7 ] && [ "$MIN" -lt 4 ]; then
  EXTRA=(--with-gd --with-jpeg-dir=/usr --with-png-dir=/usr --with-freetype-dir=/usr --enable-zip)
else
  # 7.4+: gd przez pkg-config, zip wymaga libzip>=0.11 (CentOS 7 ma 0.10) -> pomijamy
  EXTRA=(--enable-gd --with-jpeg --with-freetype)
fi

echo "==> configure"
./configure "${COMMON[@]}" "${EXTRA[@]}" > configure.log 2>&1 || { tail -50 configure.log; exit 1; }
echo "==> make"
make -j"$(nproc)" > make.log 2>&1 || { tail -80 make.log; exit 1; }
make install > install.log 2>&1

mkdir -p "$PREFIX/etc/conf.d" "$PREFIX/var/log" "$PREFIX/var/run"
cp php.ini-development "$PREFIX/etc/php.ini"
echo "zend_extension=opcache.so" > "$PREFIX/etc/conf.d/10-opcache.ini"

cat > "$PREFIX/etc/php-fpm.conf" <<EOF
[global]
pid = $PREFIX/var/run/php-fpm.pid
error_log = $PREFIX/var/log/php-fpm.log
daemonize = yes
include = $PREFIX/etc/php-fpm.d/*.conf
EOF
mkdir -p "$PREFIX/etc/php-fpm.d"
rm -f "$PREFIX/etc/php-fpm.d/"*.default
cat > "$PREFIX/etc/php-fpm.d/www.conf" <<EOF
[www]
user = apache
group = apache
listen = 127.0.0.1:$PORT
pm = dynamic
pm.max_children = 10
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
catch_workers_output = yes
php_admin_value[error_log] = $PREFIX/var/log/www-error.log
EOF
echo "$PORT" > "$PREFIX/.fpm-port"
echo "$VER"  > "$PREFIX/.php-version"

echo "==> Zainstalowano PHP $VER w $PREFIX (php-fpm 127.0.0.1:$PORT)"
"$PREFIX/bin/php" -v

