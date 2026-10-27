#!/bin/bash
# Czy "strings | grep max_multipart_body_parts" poprawnie odroznia modul z latka od modulu bez latki?
echo "=== budowanie modulu BEZ latki do porownania (vanilla)..."
V=/usr/local/src/php-build-php-7.4-vanilla
if [ ! -f /tmp/libphp7-vanilla.so ]; then
  cd $V || exit 1
  if [ ! -f libs/libphp7.so ]; then
    make distclean >/dev/null 2>&1
    ./buildconf --force >/dev/null 2>&1
    ./configure --prefix=/tmp/v --with-apxs2=/usr/bin/apxs \
      --disable-dom --disable-simplexml --disable-xml --disable-xmlreader --disable-xmlwriter \
      --disable-pdo --without-pdo-sqlite --without-sqlite3 --disable-posix --disable-mbstring \
      > /tmp/vconf.log 2>&1 || { tail -5 /tmp/vconf.log; exit 1; }
    make -j"$(nproc)" > /tmp/vmake.log 2>&1 || { tail -20 /tmp/vmake.log; exit 1; }
  fi
  cp libs/libphp7.so /tmp/libphp7-vanilla.so
fi
echo "gotowe"
echo
echo "=== wynik wykrywania:"
for M in /usr/lib64/httpd/modules/libphp74-patched.so /tmp/libphp7-vanilla.so; do
  [ -f "$M" ] || { echo "  brak: $M"; continue; }
  if strings -a "$M" 2>/dev/null | grep -q 'max_multipart_body_parts'; then
    printf '  %-50s -> %s\n' "$(basename $M)" "wykryto LATKE"
  else
    printf '  %-50s -> %s\n' "$(basename $M)" "BEZ latki"
  fi
done

