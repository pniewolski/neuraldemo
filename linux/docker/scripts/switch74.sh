#!/bin/bash
# Przełącza moduł w konfiguracji Apache na PHP 7.4 (do testów w kontenerze).
set -e
sed -i 's|modules/libphp7\.so|modules/libphp74-patched.so|' /etc/httpd/conf.modules.d/15-php.conf
httpd -t
cat /etc/httpd/conf.modules.d/15-php.conf

