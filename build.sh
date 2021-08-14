#!/bin/bash

SRC=$(realpath $(cd -P "$( dirname "${BASH_SOURCE[0]}")" && pwd))

# http://nginx.org/en/download.html
# https://www.libressl.org/releases.html
# https://www.pcre.org/
# https://zlib.net/

# versions
NGINX_VERSION=
LIBRESSL_VERSION=
PCRE_VERSION=
ZLIB_VERSION=

set -e

CACHEDIR=$SRC/cache
mkdir -p $SRC/cache

grab() {
  if [ ! -f $CACHEDIR/$2.tar.gz ]; then
    echo -n "RETRIEVING: $1/$2.tar.gz -> $CACHEDIR/$2.tar.gz     "
    wget --progress=dot -O $CACHEDIR/$2.tar.gz $1/$2.tar.gz 2>&1 | \
      grep --line-buffered "%" | \
      sed -u -e "s,\.,,g" | \
      awk '{printf("\b\b\b\b%4s", $2)}'
    echo -ne "\b\b\b\b"
    echo " DONE."
  else
    echo "ARCHIVE EXISTS: $CACHEDIR/$2.tar.gz"
  fi
}

git_grab() {
  REPO=$(basename $1)
  if [ ! -d $CACHEDIR/$REPO ]; then
    mkdir -p $CACHEDIR/$REPO
    git clone https://github.com/$1.git $CACHEDIR/$REPO
  fi
  pushd $CACHEDIR/$REPO &> /dev/null
  git clean -f -x -d
  git reset --hard
  git pull
  popd &> /dev/null
}

# latest versions
if [ -z "$NGINX_VERSION" ]; then
  NGINX_VERSION=$(wget -qO- https://nginx.org/download/|sed -E -n 's/.*<a .+?>nginx-([0-9]+\.[0-9]+\.[0-9]+)\.tar\.gz<.*/\1/p'|sort -r -V|head -1)
fi
if [ -z "$LIBRESSL_VERSION" ]; then
  LIBRESSL_VERSION=$(wget -qO- https://ftp.openbsd.org/pub/OpenBSD/LibreSSL/|sed -E -n 's/.*<a .+?>libressl-([0-9]+\.[0-9]+\.[0-9]+)\.tar\.gz<.*/\1/p'|sort -r -V|head -1)
fi
if [ -z "$PCRE_VERSION" ]; then
  PCRE_VERSION=$(wget -qO- https://ftp.pcre.org/pub/pcre|sed -E -n 's/.*<a .+?>pcre-([0-9]+\.[0-9]+)\.tar\.gz<.*/\1/p'|sort -r -V|head -1)
fi
if [ -z "$ZLIB_VERSION" ]; then
  ZLIB_VERSION=$(wget -qO- https://www.zlib.net|sed -E -n 's/.*<b>\s*zlib\s*([0-9]+\.[0-9]+\.[0-9]+)<.*/\1/ip'|sort -r -V|head -1)
fi

BITNAMI_VERSION=$NGINX_VERSION

BUILD=$(cat << END
NGINX:    $NGINX_VERSION
LIBRESSL: $LIBRESSL_VERSION
PCRE:     $PCRE_VERSION
ZLIB:     $ZLIB_VERSION
BITNAMI:  $BITNAMI_VERSION
END
)
cat <<< "$BUILD"

grab https://nginx.org/download nginx-$NGINX_VERSION
grab https://ftp.openbsd.org/pub/OpenBSD/LibreSSL libressl-$LIBRESSL_VERSION
grab https://ftp.pcre.org/pub/pcre pcre-$PCRE_VERSION
grab https://www.zlib.net zlib-$ZLIB_VERSION

git_grab openresty/headers-more-nginx-module

touch $SRC/.build
SUM=$(md5sum <<< "$BUILD")
CURRENT=$(md5sum $SRC/.build)

if [ "$SUM" != "$CURRENT" ]; then
  # force bitnami nginx image version in dockerfile
  perl -pi -e "s|FROM bitnami/nginx:.*|FROM bitnami/nginx:$BITNAMI_VERSION|" $SRC/Dockerfile
  (set -x;
    docker build \
      --pull \
      --progress=plain \
      --build-arg NGINX_VERSION=$NGINX_VERSION \
      --build-arg LIBRESSL_VERSION=$LIBRESSL_VERSION \
      --build-arg PCRE_VERSION=$PCRE_VERSION \
      --build-arg ZLIB_VERSION=$ZLIB_VERSION \
      --tag kenshaw/nginx:$NGINX_VERSION \
      --tag kenshaw/nginx:latest \
      --file Dockerfile \
      .
  )
  cat <<< "$BUILD" > $SRC/.build
else
  echo "SKIPPING BUILD ($SUM == $CURRENT)"
fi

(set -x;
  docker push kenshaw/nginx:$NGINX_VERSION
  docker push kenshaw/nginx:latest
)
