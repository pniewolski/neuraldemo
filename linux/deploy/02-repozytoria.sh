#!/bin/bash
# 02-repozytoria.sh – krok 1: przestawienie yum na archiwum vault.centos.org (CentOS 7 jest EOL).
# Uruchom na OBU serwerach. Idempotentny – można uruchamiać wielokrotnie.
# NIE wykonuje "yum update" (zaktualizowałby PHP 7.2 z remi).

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_root
start_log "02-repozytoria"

head1 "Sprawdzenie, czy yum w ogóle działa"
if yum -q repolist >/dev/null 2>&1; then
  ok "yum działa poprawnie – zmiany repozytoriów mogą nie być potrzebne"
  if [ "${FORCE:-0}" != "1" ]; then
    log "Aby mimo to przestawić repozytoria na vault, uruchom: FORCE=1 $0"
    exit 0
  fi
else
  warn "yum zgłasza błędy – przestawiam repozytoria na archiwum"
fi

head1 "Kopia zapasowa plików repo"
BK="$WORKDIR/backup-yum-repos-$(date +%F-%H%M%S).tgz"
tar czf "$BK" /etc/yum.repos.d /etc/yum/vars 2>/dev/null || true
ok "Zapisano: $BK"

head1 "Ustawienie wersji wydania"
mkdir -p /etc/yum/vars
echo "7.9.2009" > /etc/yum/vars/releasever     # vault nie ma katalogu "7", tylko konkretne wydania
ok "/etc/yum/vars/releasever = 7.9.2009"

head1 "Repozytoria CentOS -> vault.centos.org"
sed -i -e 's|^mirrorlist=|#mirrorlist=|g' \
       -e 's|^#\s*baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' \
       /etc/yum.repos.d/CentOS-*.repo
ok "Przestawiono pliki CentOS-*.repo"

head1 "EPEL"
# Przy naszym zestawie rozszerzeń EPEL nie jest potrzebny. Jeśli istnieje i jest zepsuty, naprawiamy go.
if [ -f /etc/yum.repos.d/epel.repo ]; then
  if grep -qE '^\s*(baseurl|metalink|mirrorlist)=' /etc/yum.repos.d/epel.repo; then
    ok "epel.repo ma zdefiniowany adres – zostawiam bez zmian"
  else
    warn "epel.repo nie ma żadnego adresu (typowy skutek nieudanego sed) – nadpisuję"
    cp -a /etc/yum.repos.d/epel.repo "$WORKDIR/epel.repo.bak"
    cat > /etc/yum.repos.d/epel.repo <<'EOF'
[epel]
name=Extra Packages for Enterprise Linux 7 - $basearch (archive)
baseurl=https://dl.fedoraproject.org/pub/archive/epel/7/$basearch
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-7
EOF
    [ -f /etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-7 ] || \
      curl -fsSL -o /etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-7 \
           https://dl.fedoraproject.org/pub/archive/epel/RPM-GPG-KEY-EPEL-7 || \
      warn "Nie udało się pobrać klucza GPG EPEL"
    ok "epel.repo nadpisany adresem archiwum"
  fi
else
  log "Brak epel.repo – EPEL nie jest wymagany przy tym zestawie rozszerzeń"
fi

head1 "Odświeżenie metadanych"
yum clean all >/dev/null
if yum makecache; then
  ok "Metadane pobrane bez błędów"
else
  err "yum makecache zakończone błędem."
  log ""
  log "Najczęstsze przyczyny i rozwiązania:"
  log "  1) curl#35 / unsupported protocol version – za stara biblioteka TLS:"
  log "       yum -y --disablerepo=epel update nss nss-util nss-sysinit nss-tools curl libcurl ca-certificates"
  log "     a potem uruchom ten skrypt ponownie."
  log "  2) błąd dotyczy repozytorium epel – wyłącz je, nie jest potrzebne:"
  log "       yum-config-manager --disable epel"
  log "  3) szczegółowa procedura naprawy: KROK1-NAPRAWA-EPEL.md"
  exit 1
fi

head1 "Włączone repozytoria"
yum repolist enabled || true

ok "Krok 1 zakończony"
warn "Nie uruchamiaj 'yum update' na całym systemie – zaktualizowałby PHP 7.2 z remi."

