#!/bin/bash
# Runs INSIDE the zmk-devcontainer. Called by 'build_and_flash.sh' on the host.
# Usage: build_from_docker.sh left|right|reset [--pristine]
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

TARGET="$1"
PRISTINE='auto'
if [ "$2" == "--pristine" ]; then
    PRISTINE='always'
fi

if [ "$TARGET" == "left" ] || [ "$TARGET" == "right" ]; then
    echo "Building $TARGET side"
    BUILD_ARGS=(-b nice_nano_v2 -- -DSHIELD="corne_$TARGET nice_view_adapter nice_view" -DZMK_CONFIG="$ZMK_CONFIG" -DCMAKE_EXPORT_COMPILE_COMMANDS=ON)
elif [ "$TARGET" == "reset" ]; then
    echo "Building settings_reset"
    TARGET='settings_reset'
    BUILD_ARGS=(-b nice_nano_v2 -- -DSHIELD=settings_reset)
else
    echo "Invalid argument. Please provide 'left', 'right' or 'reset'"
    exit 1
fi
BUILDDIR="$DIR/app/build/$TARGET"


# Board/shield args are only needed for the first (or a pristine) build.
# Note: a new '.conf' file in zmk-config is only picked up by a pristine build.
if [ ! -d "$BUILDDIR" ] || [ "$PRISTINE" == "always" ]; then
    echo "Performing full build in $BUILDDIR"
    west build -p always -d "$BUILDDIR" "${BUILD_ARGS[@]}"
else
    echo "Build directory $BUILDDIR exists. Performing build with cache"
    west build -d "$BUILDDIR"
fi



cd - >/dev/null
