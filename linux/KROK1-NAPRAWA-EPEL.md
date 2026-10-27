# Krok 1: naprawa repozytorium EPEL

Stan wyjściowy: `yum` kończy się błędem `Cannot find a valid baseurl for repo: epel`.

Przyczyna: polecenie `sed` z poprzedniej wersji instrukcji zakomentowało w `/etc/yum.repos.d/epel.repo` linię `metalink=`, ale nie wpisało `baseurl=`. EPEL został bez adresu, a przez jedno uszkodzone repozytorium `yum` przestaje działać w całości.

> **Uwaga na kopiowanie:** w poprzednim logu apostrof `'` zamienił się na `%27`.
> Kopiuj polecenia z tego pliku otwartego jako **zwykły tekst** (np. Notepad++, VS Code, `cat` na serwerze),
> a nie z podglądu w przeglądarce, Teams czy Outlooku.
> Najbezpieczniej przenieść plik na serwer (`scp`) i kopiować z `less KROK1-NAPRAWA-EPEL.md`.

**Nie uruchamiaj ponownie** poleceń `echo "7.9.2009" ...` ani `sed ... CentOS-*.repo`, bo zostały już wykonane poprawnie. **Nie uruchamiaj** też `yum -y install epel-release`, bo pakiet jest już zainstalowany. **Nie uruchamiaj** starego `sed ... epel*.repo`.

---

## 1.1 Sprawdzenie klucza GPG EPEL

```bash
ls -l /etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-7
```

- Plik istnieje: przejdź do 1.2.
- `No such file or directory`: pobierz klucz ręcznie:
  ```bash
  curl -fsSL -o /etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-7 https://dl.fedoraproject.org/pub/archive/epel/RPM-GPG-KEY-EPEL-7
  ```

---

## 1.2 Kopia zapasowa obecnego pliku repo

```bash
mkdir -p /root/php74-migracja
cp -a /etc/yum.repos.d/epel.repo /root/php74-migracja/epel.repo.bak
```

Zachowuje uszkodzony plik na wypadek, gdyby trzeba było do niego wrócić.

---

## 1.3 Nowy plik `epel.repo`, wpisany w całości (bez `sed`)

Skopiuj **cały blok**, od `cat` do `EOF` włącznie:

```bash
cat > /etc/yum.repos.d/epel.repo <<'EOF'
[epel]
name=Extra Packages for Enterprise Linux 7 - $basearch (archive)
baseurl=https://dl.fedoraproject.org/pub/archive/epel/7/$basearch
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-7
EOF
```

Nadpisuje plik nową definicją EPEL, która wskazuje na archiwum Fedory (EPEL 7 jest zarchiwizowany).
Zapis `<<'EOF'` w apostrofach powoduje, że `$basearch` zostaje w pliku dosłownie, a `yum` sam wstawi tam `x86_64`.

---

## 1.4 Kontrola pliku

```bash
cat /etc/yum.repos.d/epel.repo
```

Oczekiwany wynik to dokładnie 6 linii jak w 1.3, w tym `$basearch` dosłownie.

```bash
grep -l '%27' /etc/yum.repos.d/*.repo
```

Oczekiwany wynik: **brak wyniku**. Jeśli wypisze jakiś plik, jest w nim artefakt z kopiowania i trzeba go poprawić.

---

## 1.5 Odświeżenie metadanych yum

```bash
yum clean all
yum makecache
```

`yum clean all` usuwa stare metadane. `yum makecache` pobiera je od nowa ze wszystkich repozytoriów. **Na końcu nie może być błędu.**

```bash
yum repolist enabled
```

Oczekiwany wynik (liczby pakietów mogą się różnić):

```
repo id                     repo name                                     status
base/7.9.2009/x86_64        CentOS-7.9.2009 - Base                        10 072
epel/x86_64                 Extra Packages for Enterprise Linux 7 ...     13 xxx
extras/7.9.2009/x86_64      CentOS-7.9.2009 - Extras                         526
remi-php72                  Remi's PHP 7.2 RPM repository ...                xxx
remi-safe                   Safe Remi's RPM repository ...                 x xxx
updates/7.9.2009/x86_64     CentOS-7.9.2009 - Updates                      6 xxx
```

---

## 1.6 Sprawdzenie, że EPEL ma potrzebny pakiet

```bash
yum info oniguruma-devel | grep -E '^(Name|Version|Repo)'
```

Oczekiwany wynik: `Name : oniguruma-devel`, `Version : 6.8.2`, `Repo : epel`.
Ta biblioteka jest wymagana przez rozszerzenie `mbstring` w PHP 7.4.

---

## Jeśli w 1.5 pojawi się błąd

### A) `curl#35 - "Peer reports incompatible or unsupported protocol version"`

Systemowa biblioteka TLS jest za stara, żeby połączyć się z serwerem po HTTPS. Zaktualizuj ją, chwilowo bez EPEL:

```bash
yum -y --disablerepo=epel update nss nss-util nss-sysinit nss-tools nss-softokn nss-softokn-freebl curl libcurl ca-certificates
```

Potem powtórz **1.5**.

### B) `Cannot find a valid baseurl for repo: <inna nazwa niż epel>`

Uszkodzone jest inne repozytorium. Zbierz informacje i wklej wynik:

```bash
grep -n 'baseurl\|mirrorlist\|metalink\|enabled' /etc/yum.repos.d/*.repo
yum makecache 2>&1 | tail -30
```

### C) `[Errno 14] HTTP Error 404` dla `vault.centos.org`

Sprawdź plik wersji:

```bash
cat /etc/yum/vars/releasever
```

Oczekiwany wynik: `7.9.2009`.

### Awaryjnie: tymczasowe obejście EPEL

Jeśli EPEL nie działa, a trzeba wykonać inne polecenie `yum`:

```bash
yum --disablerepo=epel <polecenie>
```

---

## Po sukcesie

Gdy `yum makecache` kończy się bez błędów, a `yum repolist enabled` pokazuje `epel`, przejdź do **kroku 2** w `WDROZENIE.md` (instalacja narzędzi do kompilacji).

**Nie uruchamiaj `yum update` na całym systemie.** Z repozytorium `remi-php72` zaktualizowałoby się też obecne PHP 7.2.

