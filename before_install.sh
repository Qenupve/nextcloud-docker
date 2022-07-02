#!/bin/bash

# function to echo to stderr
echoerr() { echo "ERROR: $@" >&2; }

if [ -z "$(groups | egrep "docker|root")" ]; then
    echoerr "must run as a user that can run docker commands"
    exit 1
fi

COMPOSE_DIR="$(dirname "$0")"
PREFIX="$(grep ^PREFIX "$COMPOSE_DIR/.env" | cut -d "=" -f 2)"
SUFFIX="$(grep ^SUFFIX "$COMPOSE_DIR/.env" | cut -d "=" -f 2)"
CONTAINER="${PREFIX}app$SUFFIX"

DOC_EXEC="docker container exec $CONTAINER"

if [ ! -z "$NEXTCLOUD_DATA_DIR" ]; then
    $DOC_EXEC chown -R www-data "$NEXTCLOUD_DATA_DIR"
else
    echoerr "you need to set NEXTCLOUD_DATA_DIR and run chown -r www-data on it"
fi

$DOC_EXEC chown -R www-data: /opt
$DOC_EXEC rm -r /var/www/html/core/skeleton/{Nextcloud\ Manual.pdf,Nextcloud\ intro.mp4,Nextcloud.png,Reasons\ to\ use\ Nextcloud.pdf,Templates,Readme.md}
$DOC_EXEC rm -r /var/www/html/core/skeleton/Documents/{Nextcloud\ flyer.pdf,Readme.md}
