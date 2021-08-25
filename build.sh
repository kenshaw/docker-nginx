#!/bin/bash

# add via `crontab -e`:
#
#   05 */3 * * * /usr/bin/flock -w 0 $HOME/src/docker-nginx/.lock $HOME/src/docker-nginx/build.sh 2>&1 >> /var/log/build/docker-nginx.log

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

NOTIFY_TEAM=dev
NOTIFY_CHANNEL=town-square

HOST=$(jq -r '.["docker-nginx"].instanceUrl' $HOME/.config/mmctl)
TOKEN=$(jq -r '.["docker-nginx"].authToken' $HOME/.config/mmctl)

mmcurl() {
  local method=$1
  local url=$HOST/api/v4/$2
  if [ ! -z "$3" ]; then
    body="-d"
  fi
  curl \
    -s \
    -m 30 \
    -X $method \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $TOKEN" \
    $body "$3" \
    $url
}

NOTIFY_TEAMID=$(mmcurl GET teams/name/$NOTIFY_TEAM|jq -r '.id')
NOTIFY_CHANNELID=$(mmcurl GET teams/$NOTIFY_TEAMID/channels/name/$NOTIFY_CHANNEL|jq -r '.id')

mmfile() {
  local url=$HOST/api/v4/files
  curl \
    -s \
    -H "Authorization: Bearer $TOKEN" \
    -F "channel_id=$NOTIFY_CHANNELID" \
    -F "files=@$1" \
    $url
}

mmpost() {
  local message="$1"
  shift
  local files=''
  while (( "$#" )); do
    files+="\"$1\", "
    shift
  done
  if [ ! -z "$files" ]; then
    files=$(echo -e ',\n  "file_ids": ['$(sed -e 's/, $//' <<< "$files")']')
  fi
  POST=$(cat << END
{
  "channel_id": "$NOTIFY_CHANNELID",
  "message": "$message"$files
}
END
)
  mmcurl POST posts "$POST"
}

if [[ -z "$NOTIFY_TEAMID" || -z "$NOTIFY_CHANNELID" ]]; then
  echo "ERROR: unable to determine NOTIFY_TEAMID or NOTIFY_CHANNELID, exiting ($(date))"
  exit 1
fi

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

pushd $SRC &> /dev/null

echo "------------------------------------------------------------"
echo "STARTING ($(date))"

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

touch $SRC/.last
LAST=$(md5sum <<< "$BUILD"|awk '{print $1}')
CURRENT=$(md5sum $SRC/.last|awk '{print $1}')

echo "LAST:     $LAST"
echo "CURRENT:  $CURRENT"

if [ "$LAST" = "$CURRENT" ]; then
  echo "SKIPPING: LAST($LAST) == CURRENT($CURRENT)"
else
  # force bitnami nginx image version in dockerfile
  perl -pi -e "s|FROM bitnami/nginx:.*|FROM bitnami/nginx:$BITNAMI_VERSION|" $SRC/Dockerfile
  (set -x;
    docker pull bitnami/nginx:$BITNAMI_VERSION
    docker pull debian:buster-slim
    DOCKER_BUILDKIT=1 \
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
  cat <<< "$BUILD" > $SRC/.last
fi

if [ ! -f $SRC/cache/$CURRENT.docker_push_done ]; then
  (set -x;
    docker push kenshaw/nginx:$NGINX_VERSION
    docker push kenshaw/nginx:latest
  )
  # notify
  HASH=$(docker inspect --format='{{index .RepoDigests 0}}' kenshaw/nginx:$NGINX_VERSION|awk -F: '{print $2}')
  LINK=$(printf 'https://hub.docker.com/layers/kenshaw/nginx/%s/images/sha256-%s?context=explore' $NGINX_VERSION $HASH)
  TAGS='`'$NGINX_VERSION'`, `latest`'
  mmpost "Pushed kenshaw/nginx ($TAGS) to Docker hub: [kenshaw/nginx:$NGINX_VERSION]($LINK)"
  touch $SRC/cache/$CURRENT.docker_push_done
fi

echo "DONE ($(date))"

popd &> /dev/null
