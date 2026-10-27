#!/bin/bash
# Diagnostyka: dlaczego skrypt kończy się kodem 1 mimo poprawnego przebiegu
cat > /tmp/t1.sh <<'EOF'
#!/bin/bash
set -Eeuo pipefail
LOGFILE=/tmp/t1.log
exec > >(tee -a "$LOGFILE") 2>&1
_TEE_PID=$!
echo "TEE_PID='$_TEE_PID'"
_flush_log() { local rc=$?; exec 1>&- 2>&-; [ -n "${_TEE_PID:-}" ] && wait "$_TEE_PID" 2>/dev/null; return $rc; }
trap '_flush_log' EXIT
echo "koniec"
EOF
bash /tmp/t1.sh; echo "RC bez zmian = $?"

cat > /tmp/t2.sh <<'EOF'
#!/bin/bash
set -Eeuo pipefail
LOGFILE=/tmp/t2.log
exec > >(tee -a "$LOGFILE") 2>&1
_flush_log() { local rc=$?; exec 1>&- 2>&-; return $rc; }
trap '_flush_log' EXIT
echo "koniec"
EOF
bash /tmp/t2.sh; echo "RC bez wait = $?"

