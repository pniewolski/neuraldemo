#!/bin/bash
# Warianty _flush_log: czy zachowują kod wyjścia i czy nie gubią ostatnich linii
mk() { # $1=nazwa  $2=cialo_flush  $3=kod_wyjscia_skryptu
cat > /tmp/v.sh <<EOF
#!/bin/bash
set -Eeuo pipefail
LOGFILE=/tmp/v.log; : > "\$LOGFILE"
exec > >(tee -a "\$LOGFILE") 2>&1
_TEE_PID=\$!
_flush_log() { $2 }
trap '_flush_log' EXIT
echo "linia-1"
echo "OSTATNIA-LINIA"
exit $3
EOF
  local out; out=$(bash /tmp/v.sh); local rc=$?
  local ma_ostatnia="nie"; printf '%s' "$out" | grep -q 'OSTATNIA-LINIA' && ma_ostatnia="tak"
  printf '  %-22s rc=%-4s ostatnia_linia=%s\n' "$1" "$rc" "$ma_ostatnia"
}

echo "oczekiwane: rc=0 oraz rc=7, ostatnia_linia=tak"
echo "--- exit 0:"
mk "wait+return"    'local rc=$?; exec 1>&- 2>&-; [ -n "${_TEE_PID:-}" ] && wait "$_TEE_PID" 2>/dev/null; return $rc;' 0
mk "wait+|| true"   'local rc=$?; exec 1>&- 2>&-; wait "${_TEE_PID:-}" 2>/dev/null || true; return $rc;' 0
mk "tylko close"    'local rc=$?; exec 1>&- 2>&-; return $rc;' 0
mk "sleep 0.2"      'local rc=$?; sleep 0.2; return $rc;' 0
mk "pusty"          'local rc=$?; return $rc;' 0
echo "--- exit 7:"
mk "wait+return"    'local rc=$?; exec 1>&- 2>&-; [ -n "${_TEE_PID:-}" ] && wait "$_TEE_PID" 2>/dev/null; return $rc;' 7
mk "wait+|| true"   'local rc=$?; exec 1>&- 2>&-; wait "${_TEE_PID:-}" 2>/dev/null || true; return $rc;' 7
mk "tylko close"    'local rc=$?; exec 1>&- 2>&-; return $rc;' 7
mk "sleep 0.2"      'local rc=$?; sleep 0.2; return $rc;' 7
mk "pusty"          'local rc=$?; return $rc;' 7

