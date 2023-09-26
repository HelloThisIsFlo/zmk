#!/bin/bash
set -eo pipefail
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

cd "$DIR"

if west status 2> /dev/null; then
    echo "Make sure to NOT run this from the docker devcontainer (in VS Code)"
    exit 1
else
    # It worked
    printf ''
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

docker exec zmk-devcontainer /workspaces/zmk/build_from_docker.sh $SIDE

cp "$BUILDDIR/zephyr/zmk.uf2" /Volumes/NICENANO/



cd - >/dev/null
