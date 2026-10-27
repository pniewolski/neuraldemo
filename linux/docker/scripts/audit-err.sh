#!/bin/bash
cd /root/deploy || exit 1
echo "=== pozostale 'set +e' (moga dawac falszywe alarmy ERR):"
grep -n 'set +e' *.sh || echo "  brak"
echo
echo "=== skladnia:"
for f in *.sh; do bash -n "$f" && echo "  OK   $f" || echo "  BLAD $f"; done
echo
echo "=== symulacja: polecenie konczace sie bledem w kontekscie ||"
cat > /tmp/err-test.sh <<'EOF'
#!/bin/bash
source /root/deploy/lib.sh
start_log "err-test"
RC=0
false || RC=$?
log "false w kontekscie || : RC=$RC (brak komunikatu o bledzie = dobrze)"
exit 0
EOF
bash /tmp/err-test.sh; echo "RC skryptu = $?"

