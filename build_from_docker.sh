#!/bin/bash
# Runs INSIDE the zmk-devcontainer. Called by 'build_and_flash.sh' on the host, which resolves
# the unit from 'zmk-config/config/targets.txt' and passes everything explicitly.
# Usage: build_from_docker.sh <build-name> <board> "<shields>" [<keyboard> <unit>] [--pristine]
#   <keyboard>  'zmk-config/config/keyboards/<keyboard>/' becomes ZMK_CONFIG (keymap + model/side .conf)
#   <unit>      'zmk-config/config/units/<unit>.conf' is loaded last (EXTRA_CONF_FILE, wins)
#   Omit both for a config-less build (e.g. settings_reset)
set -eo pipefail
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

cd "$DIR"
cd app

CONFIG_ROOT=/workspaces/zmk-config/config # Location in Docker, see './create_docker_volume_for_zmk_devcontainer.sh' in 'zmk-config' repo

if west status 2> /dev/null; then
    # It worked
    printf ''
else
    echo "Make sure to run from within docker devcontainer (in VS Code)"
    exit 1
fi

PRISTINE='auto'
ARGS=()
for ARG in "$@"; do
    if [ "$ARG" == "--pristine" ]; then PRISTINE='always'; else ARGS+=("$ARG"); fi
done
if [ "${#ARGS[@]}" -ne 3 ] && [ "${#ARGS[@]}" -ne 5 ]; then
    echo "Usage: $0 <build-name> <board> \"<shields>\" [<keyboard> <unit>] [--pristine]"
    exit 1
fi
NAME="${ARGS[0]}"
BOARD="${ARGS[1]}"
SHIELDS="${ARGS[2]}"
KEYBOARD="${ARGS[3]:-}"
UNIT="${ARGS[4]:-}"

BUILD_ARGS=(-b "$BOARD" -- -DSHIELD="$SHIELDS")
if [ -n "$KEYBOARD" ]; then
    ZMK_CONFIG="$CONFIG_ROOT/keyboards/$KEYBOARD"
    UNIT_CONF="$CONFIG_ROOT/units/$UNIT.conf"
    [ -d "$ZMK_CONFIG" ] || { echo "❌ No keyboard folder: $ZMK_CONFIG"; exit 1; }
    [ -f "$UNIT_CONF" ] || { echo "❌ No unit config: $UNIT_CONF"; exit 1; }
    BUILD_ARGS+=(-DZMK_CONFIG="$ZMK_CONFIG" -DEXTRA_CONF_FILE="$UNIT_CONF" -DCMAKE_EXPORT_COMPILE_COMMANDS=ON)
fi
BUILDDIR="$DIR/app/build/$NAME"
echo "🔨 Building $NAME (board: $BOARD, shields: $SHIELDS)"


# Board/shield/config args are only needed for the first (or a pristine) build: they're cached in $BUILDDIR.
# Note: a new '.conf' file in zmk-config, or a changed row in 'targets.txt', is only picked up by a pristine build.
if [ ! -d "$BUILDDIR" ] || [ "$PRISTINE" == "always" ]; then
    echo "Performing full build in $BUILDDIR"
    west build -p always -d "$BUILDDIR" "${BUILD_ARGS[@]}"
else
    echo "Build directory $BUILDDIR exists. Performing build with cache"
    west build -d "$BUILDDIR"
fi



cd - >/dev/null
