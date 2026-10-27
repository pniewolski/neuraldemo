# Środowisko testowe: CentOS 7 (Core) + Apache 2.4.6 + PHP 7.2.22 (php-fpm)
# + miejsce na równoległe PHP 7.4 z gałęzi z łatką CVE.
FROM --platform=linux/amd64 centos:7

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# CentOS 7 jest EOL -> repozytoria przeniesione do vault.centos.org, EPEL do archiwum.
RUN echo "7.9.2009" > /etc/yum/vars/releasever \
 && sed -i -e 's|^mirrorlist=|#mirrorlist=|g' \
           -e 's|^#\s*baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' \
           /etc/yum.repos.d/CentOS-*.repo \
 && yum -y install epel-release ca-certificates \
 && sed -i -e 's|^metalink=|#metalink=|g' \
           -e 's|^#\s*baseurl=http://download.fedoraproject.org/pub/epel/7|baseurl=https://dl.fedoraproject.org/pub/archive/epel/7|g' \
           /etc/yum.repos.d/epel*.repo \
 && yum -y install \
      gcc gcc-c++ make autoconf automake libtool re2c pkgconfig \
      git curl wget tar xz bzip2 file which patch procps-ng \
      libxml2-devel openssl-devel zlib-devel libcurl-devel libicu-devel \
      libpng-devel libjpeg-turbo-devel freetype-devel sqlite-devel \
      oniguruma-devel libxslt-devel \
      httpd \
 && yum clean all && rm -rf /var/cache/yum

# Bison >= 3.0 jest wymagany do budowania PHP 7.4 z gita (CentOS 7 ma 2.7).
RUN curl -fsSL https://ftp.gnu.org/gnu/bison/bison-3.0.5.tar.xz | tar xJ -C /tmp \
 && cd /tmp/bison-3.0.5 && ./configure --prefix=/usr/local >/dev/null \
 && make -j"$(nproc)" >/dev/null && make install >/dev/null \
 && rm -rf /tmp/bison-3.0.5

COPY scripts/ /usr/local/bin/
RUN sed -i 's/\r$//' /usr/local/bin/*.sh /usr/local/bin/switch-php \
 && chmod +x /usr/local/bin/*.sh /usr/local/bin/switch-php

# PHP 7.2.22 - odpowiednik produkcji
RUN build-php.sh https://www.php.net/distributions/php-7.2.22.tar.gz "" /opt/php-7.2.22 9072 \
 && rm -rf /usr/local/src/php-build-*

COPY httpd/php-fpm.conf /etc/httpd/conf.d/php-fpm.conf
RUN sed -i 's/\r$//' /etc/httpd/conf.d/php-fpm.conf \
 && sed -i 's/^#ServerName.*/ServerName localhost/' /etc/httpd/conf/httpd.conf \
 && echo 9072 > /etc/httpd/php-active-port

EXPOSE 80
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

