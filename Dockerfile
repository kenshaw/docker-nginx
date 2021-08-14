# syntax=docker/dockerfile:experimental

FROM debian:stable-slim AS builder
ARG NGINX_VERSION
ARG LIBRESSL_VERSION
ARG PCRE_VERSION
ARG ZLIB_VERSION
ENV NGINX_VERSION ${NGINX_VERSION}
ENV LIBRESSL_VERSION ${LIBRESSL_VERSION}
ENV PCRE_VERSION ${PCRE_VERSION}
ENV ZLIB_VERSION ${ZLIB_VERSION}

RUN \
  apt-get update -y && apt-get install -y git rsync build-essential libperl-dev

RUN \
  --mount=type=bind,target=/cache,source=cache,ro \
  --mount=type=cache,target=/usr/src/ \
  rm -rf /usr/src/{nginx,libressl,pcre,zlib}-* /usr/src/{headers-more-nginx-module,lua-nginx-module} \
  && tar -zxC /usr/src -f /cache/nginx-${NGINX_VERSION}.tar.gz \
  && tar -zxC /usr/src -f /cache/libressl-${LIBRESSL_VERSION}.tar.gz \
  && tar -zxC /usr/src -f /cache/pcre-${PCRE_VERSION}.tar.gz \
  && tar -zxC /usr/src -f /cache/zlib-${ZLIB_VERSION}.tar.gz \
  && rsync -rvP --delete /cache/headers-more-nginx-module /usr/src

RUN \
  --mount=type=cache,target=/usr/src/ \
  cd /usr/src/nginx-$NGINX_VERSION \
  && ./configure \
    --prefix=/opt/bitnami/nginx \
    --sbin-path=/opt/bitnami/nginx/sbin/nginx \
    --conf-path=/opt/bitnami/nginx/conf/nginx.conf \
    --error-log-path=/dev/stderr \
    --http-log-path=/dev/stdout \
    --http-client-body-temp-path=/var/cache/nginx/tmp/client_body \
    --http-proxy-temp-path=/var/cache/nginx/tmp/proxy \
    --http-fastcgi-temp-path=/var/cache/nginx/tmp/fastcgi \
    --http-uwsgi-temp-path=/var/cache/nginx/tmp/uwsgi \
    --http-scgi-temp-path=/var/cache/nginx/tmp/scgi \
    --pid-path=/var/run/nginx.pid \
    --lock-path=/var/run/nginx.lock \
    --user=1001 \
    --group=1001 \
    --with-ipv6 \
    --with-threads \
    --with-file-aio \
    --with-http_ssl_module \
    --with-http_v2_module \
    --with-http_realip_module \
    --with-http_gzip_static_module \
    --with-http_slice_module \
    --with-http_stub_status_module \
    --with-http_perl_module \
    --with-perl=/usr/bin/perl \
    --with-perl_modules_path=/usr/share/perl/5.28.1 \
    --without-select_module \
    --without-poll_module \
    --without-mail_pop3_module \
    --without-mail_imap_module \
    --without-mail_smtp_module \
    --with-stream \
    --with-stream_ssl_module \
    --with-stream_ssl_preread_module \
    --with-stream_realip_module \
    --with-openssl=/usr/src/libressl-${LIBRESSL_VERSION} \
    --with-pcre=/usr/src/pcre-${PCRE_VERSION} \
    --with-pcre-jit \
    --with-zlib=/usr/src/zlib-${ZLIB_VERSION} \
    --add-module=/usr/src/headers-more-nginx-module \
    --with-cc-opt='-fPIC -pie -O2 -g -pipe -Wall -Werror=format-security -Wp,-D_FORTIFY_SOURCE=2 -fexceptions -fstack-protector-strong --param=ssp-buffer-size=4 -grecord-gcc-switches -m64 -mtune=generic' \
    --with-ld-opt='-Wl,-z,now -lrt'

RUN \
  --mount=type=cache,target=/usr/src/ \
  cd /usr/src/nginx-$NGINX_VERSION \
  && make -i -k -j$(getconf _NPROCESSORS_ONLN)

RUN \
  --mount=type=cache,target=/usr/src/ \
  cd /usr/src/nginx-$NGINX_VERSION \
  && make install \
  && rm -rf /etc/nginx/html/ \
  && mkdir -p /usr/share/nginx/html/ \
  && install -m644 html/index.html /usr/share/nginx/html/ \
  && install -m644 html/50x.html /usr/share/nginx/html/ \
  && strip /opt/bitnami/nginx/sbin/nginx*

FROM bitnami/nginx:1.21.1
COPY --from=builder /opt/bitnami/nginx/sbin/nginx /opt/bitnami/nginx/sbin/
COPY --from=builder /usr/share/perl/5.28.1/x86_64-linux-gnu-thread-multi /usr/share/perl/5.28.1/
USER root
RUN \
  apt-get update -y && apt-get install -y libperl5.28
USER 1001
