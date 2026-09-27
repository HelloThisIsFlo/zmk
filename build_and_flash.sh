#!/bin/bash
# Build in the zmk-devcontainer, then wait for each half to enter bootloader mode and flash it.
#
# Usage: ./build_and_flash.sh left|right|both|reset [--pristine] [--no-flash]
#   left|right  Build + flash one half
#   both        Build + flash left, then right
#   reset       Flash 'settings_reset' to both halves (wipes BT bonds + split pairing)
#   --pristine  Full rebuild (needed after adding a new '.conf' file to zmk-config)
#   --no-flash  Build only (e.g. to verify compilation)
#
# Bootloader mode: double-tap the reset button on the nice!nano (or BIOS layer -> &bootloader)
set -eo pipefail
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

cd "$DIR"

CONTAINER=zmk-devcontainer
VOLUME=/Volumes/NICENANO
MOUNT_TIMEOUT_SEC=120
UNMOUNT_TIMEOUT_SEC=30

if west status 2> /dev/null; then
    echo "Make sure to NOT run this from the docker devcontainer (in VS Code)"
    exit 1
fi

TARGET="$1"
shift || true
PRISTINE=''
NO_FLASH=false
for OPT in "$@"; do
    case "$OPT" in
        --pristine) PRISTINE='--pristine' ;;
        --no-flash) NO_FLASH=true ;;
        *) echo "Unknown option: $OPT"; exit 1 ;;
    esac
done
case "$TARGET" in
    left)  BUILDS=(left);           FLASHES=(left:left) ;;
    right) BUILDS=(right);          FLASHES=(right:right) ;;
    both)  BUILDS=(left right);     FLASHES=(left:left right:right) ;;
    reset) BUILDS=(settings_reset); FLASHES=(left:settings_reset right:settings_reset) ;;
    *)
        echo "Usage: $0 left|right|both|reset [--pristine] [--no-flash]"
        exit 1
        ;;
esac


# --- Container ---
if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null)" != "true" ]; then
    echo "🐳 Starting $CONTAINER"
    docker start "$CONTAINER" >/dev/null
fi


# --- Build (everything first, so flashing isn't interrupted by a failed build) ---
for BUILD in "${BUILDS[@]}"; do
    ARG="$BUILD"
    [ "$BUILD" == "settings_reset" ] && ARG='reset'
    docker exec "$CONTAINER" /workspaces/zmk/build_from_docker.sh "$ARG" $PRISTINE
done


# --- Flash ---
if [ "$NO_FLASH" == "true" ]; then
    echo "✅ Build done (--no-flash)"
    exit 0
fi

wait_for_volume() { # $1 = present|absent, $2 = timeout
    local elapsed=0
    while true; do
        if [ "$1" == "present" ] && [ -d "$VOLUME" ]; then return 0; fi
        if [ "$1" == "absent" ] && [ ! -d "$VOLUME" ]; then return 0; fi
        if [ "$elapsed" -ge "$2" ]; then return 1; fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
}

for FLASH in "${FLASHES[@]}"; do
    SIDE="${FLASH%%:*}"
    UF2="$DIR/app/build/${FLASH##*:}/zephyr/zmk.uf2"

    if [ -d "$VOLUME" ]; then
        echo "⏳ $VOLUME is still mounted, waiting for it to go away..."
        wait_for_volume absent "$UNMOUNT_TIMEOUT_SEC" || { echo "❌ $VOLUME never unmounted"; exit 1; }
    fi

    SIDE_UPPER="$(echo "$SIDE" | tr '[:lower:]' '[:upper:]')"
    echo ""
    echo "👉 Plug in the $SIDE_UPPER half and double-tap its reset button"
    wait_for_volume present "$MOUNT_TIMEOUT_SEC" || { echo "❌ Timed out waiting for $VOLUME"; exit 1; }
    sleep 1 # Let macOS finish mounting

    echo "⚡ Flashing $(basename "$(dirname "$(dirname "$UF2")")") to $SIDE_UPPER"
    # macOS '/bin/cp' (GNU cp may be first on PATH); '-X' skips xattrs the bootloader doesn't want.
    # The board reboots as soon as the copy completes, which can make 'cp' report an I/O error
    /bin/cp -X "$UF2" "$VOLUME/" || wait_for_volume absent 5 || { echo "❌ Copy failed"; exit 1; }
    wait_for_volume absent "$UNMOUNT_TIMEOUT_SEC" || { echo "❌ $SIDE_UPPER did not reboot"; exit 1; }
    echo "✅ $SIDE_UPPER flashed"
done



cd - >/dev/null
