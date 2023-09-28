#!/bin/bash
set -eo pipefail
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

cd "$DIR"
cd app

ZMK_CONFIG=/workspaces/zmk-config/config # Location in Docker, see './create_docker_volume_for_zmk_devcontainer.sh' in 'zmk-config' repo

if west status 2> /dev/null; then
    # It worked
    printf ''
else
    echo "Make sure to run from within docker devcontainer (in VS Code)"
    exit 1
fi

if [ "$1" == "left" ]; then
    echo "Flashing Left side"
    SIDE='left'
elif [ "$1" == "right" ]; then
    echo "Flashing Right side"
    SIDE='right'
else
    echo "Invalid argument. Please provide either 'left' or 'right'"
    exit 1
fi
BUILDDIR="$DIR/app/build/$SIDE"



if [ ! -d "$BUILDDIR" ]; then
    echo "Build directory $BUILDDIR does not exist. Performing full build"
    west build -d $BUILDDIR -b nice_nano_v2 -- -DSHIELD="corne_$SIDE nice_view_adapter nice_view" -DZMK_CONFIG="$ZMK_CONFIG" -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
else
    echo "Build directory $BUILDDIR exists. Performing build with cache"
    west build -d $BUILDDIR
fi



cd - >/dev/null
