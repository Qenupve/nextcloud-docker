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

OCC_CMD="docker container exec --user www-data $CONTAINER php occ"
DOC_EXEC="docker container exec $CONTAINER"

$OCC_CMD config:import /tmp/config.json
if [ "$?" = "0" ]; then
    $DOC_EXEC rm /tmp/config.json
else
    echoerr "\"$OCC_CMD config:import /tmp/config.json\" didn't work... Try yourself?"
fi

$OCC_CMD app:install previewgenerator
$OCC_CMD app:install richdocuments
$OCC_CMD app:install workflow_script
$OCC_CMD app:enable workflow_script --force
$OCC_CMD app:install tasks
$OCC_CMD app:install metadata
$OCC_CMD app:install files_photospheres
$OCC_CMD app:install notes
$OCC_CMD app:install calendar

# these are the preview sizes that seem to get created on-the-fly in my normal use as of 2022.07.04,
# these settings set up the previewgenerator app to pre-generate them for better performance
# also reduce the preview quality a bit, should reduce the size of previews without hurting quality too much
$OCC_CMD config:app:set previewgenerator squareSizes --value="256 1024"
$OCC_CMD config:app:set previewgenerator widthSizes  --value="256"
$OCC_CMD config:app:set previewgenerator heightSizes --value="256"
$OCC_CMD config:system:set preview_max_x --value 2048
$OCC_CMD config:system:set preview_max_y --value 2048
$OCC_CMD config:system:set jpeg_quality --value 75
$OCC_CMD config:app:set preview jpeg_quality --value="75"
