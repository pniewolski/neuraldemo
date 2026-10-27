#!/bin/bash
M=/usr/lib64/httpd/modules/libphp74-patched.so
echo "plik: $M"
ls -l "$M"
echo "--- grep -c (binarny):"
grep -c max_multipart_body_parts "$M"; echo "rc=$?"
echo "--- grep -a -c:"
grep -a -c max_multipart_body_parts "$M"; echo "rc=$?"
echo "--- strings | grep:"
strings -a "$M" | grep -c max_multipart_body_parts; echo "rc=$?"
echo "--- czy w ogole sa ciagi ini (np. max_input_vars):"
strings -a "$M" | grep -c max_input_vars
echo "--- czy to ten sam plik co zbudowany:"
md5sum "$M" /usr/local/src/php-mod/libs/libphp7.so 2>/dev/null
echo "--- czy zrodlo php-mod ma latke:"
grep -rc 'max_multipart_body_parts' /usr/local/src/php-mod/main/rfc1867.c /usr/local/src/php-mod/main/main.c 2>/dev/null

