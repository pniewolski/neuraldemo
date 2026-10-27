#!/bin/bash
# Test ścieżki produkcyjnej: tworzy paczkę jak 10-build-test.sh i instaluje ją przez 20-install-prod.sh
set -e
source /root/deploy/config.sh
rm -f "$PKG" "$PKG.sha256"
tar czf "$PKG" -C / "${PHP_PREFIX#/}" "${MOD_DIR#/}/$MOD_NAME"
sha256sum "$PKG" > "$PKG.sha256"
echo "Paczka: $(du -h "$PKG" | cut -f1)"
cd /root/deploy && ASSUME_YES=1 ./20-install-prod.sh 2>&1 | tail -30

