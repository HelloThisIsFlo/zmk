#!/bin/bash
# Build in the zmk-devcontainer, then wait for each half to enter bootloader mode and flash it.
#
# Usage: ./build_and_flash.sh <unit> left|right|both|reset [--pristine] [--no-flash]
#   <unit>      A physical keyboard from 'zmk-config/config/targets.txt' (e.g. chocofi-pro)
#   left|right  Build + flash one half
#   both        Build + flash left, then right
#   reset       Flash 'settings_reset' to both halves (wipes BT bonds + split pairing)
#   --pristine  Full rebuild (needed after adding a new '.conf' file or changing 'targets.txt')
#   --no-flash  Build only (e.g. to verify compilation)
#
# Bootloader mode: double-tap the reset button on the nice!nano (or BIOS layer -> &bootloader)
set -eo pipefail
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

cd "$DIR"

CONTAINER=zmk-devcontainer
TARGETS="$DIR/../zmk-config/config/targets.txt"
VOLUME=/Volumes/NICENANO
MOUNT_TIMEOUT_SEC=120
UNMOUNT_TIMEOUT_SEC=30

if west status 2> /dev/null; then
    echo "Make sure to NOT run this from the docker devcontainer (in VS Code)"
    exit 1
fi

usage() {
    echo "Usage: $0 <unit> left|right|both|reset [--pristine] [--no-flash]"
    echo "Units: $(awk '!/^#/ && NF {printf "%s ", $1}' "$TARGETS")"
    exit 1
}

UNIT="$1"
TARGET="$2"
shift 2 || usage
PRISTINE=''
NO_FLASH=false
for OPT in "$@"; do
    case "$OPT" in
        --pristine) PRISTINE='--pristine' ;;
        --no-flash) NO_FLASH=true ;;
        *) echo "Unknown option: $OPT"; exit 1 ;;
    esac
done

# --- Resolve the unit: 'unit keyboard board shields...' ---
ROW="$(awk -v u="$UNIT" '!/^#/ && $1 == u' "$TARGETS")"
[ -n "$ROW" ] || { echo "❌ Unknown unit: '$UNIT'"; usage; }
read -r _ KEYBOARD BOARD SHIELDS <<< "$ROW"
shields_for() { echo "${SHIELDS//\{side\}/$1}"; }

RESET="reset-$BOARD"
case "$TARGET" in
    left)  BUILDS=(left);       FLASHES=(left:$UNIT/left) ;;
    right) BUILDS=(right);      FLASHES=(right:$UNIT/right) ;;
    both)  BUILDS=(left right); FLASHES=(left:$UNIT/left right:$UNIT/right) ;;
    reset) BUILDS=(reset);      FLASHES=(left:$RESET right:$RESET) ;;
    *) usage ;;
esac


# --- Container ---
if ! docker inspect "$CONTAINER" >/dev/null 2>&1; then
    echo "🐳 Creating $CONTAINER"
    devcontainer up --workspace-folder "$DIR" >/dev/null
elif [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER")" != "true" ]; then
    echo "🐳 Starting $CONTAINER"
    docker start "$CONTAINER" >/dev/null
fi


# --- Build (everything first, so flashing isn't interrupted by a failed build) ---
echo "⌨️  Unit: $UNIT (keyboard: $KEYBOARD)"
for BUILD in "${BUILDS[@]}"; do
    if [ "$BUILD" == "reset" ]; then
        docker exec "$CONTAINER" /workspaces/zmk/build_from_docker.sh "$RESET" "$BOARD" settings_reset $PRISTINE
    else
        docker exec "$CONTAINER" /workspaces/zmk/build_from_docker.sh "$UNIT/$BUILD" "$BOARD" "$(shields_for "$BUILD")" "$KEYBOARD" "$UNIT" $PRISTINE
    fi
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

    SIDE_UPPER="$(echo "$SIDE" | tr '[:lower:]' '[:upper:]')"
    echo ""
    if [ -d "$VOLUME" ]; then
        # Already in bootloader (reset double-tapped during the build): flash it right away
        echo "👉 $VOLUME already mounted, assuming it's the $SIDE_UPPER half"
    else
        echo "👉 Plug in the $SIDE_UPPER half and double-tap its reset button"
        wait_for_volume present "$MOUNT_TIMEOUT_SEC" || { echo "❌ Timed out waiting for $VOLUME"; exit 1; }
        sleep 1 # Let macOS finish mounting
    fi

    echo "⚡ Flashing ${FLASH##*:} to $SIDE_UPPER"
    # macOS '/bin/cp' (GNU cp may be first on PATH); '-X' skips xattrs the bootloader doesn't want.
    # The board reboots as soon as the copy completes, which can make 'cp' report an I/O error
    /bin/cp -X "$UF2" "$VOLUME/" || wait_for_volume absent 5 || { echo "❌ Copy failed"; exit 1; }
    wait_for_volume absent "$UNMOUNT_TIMEOUT_SEC" || { echo "❌ $SIDE_UPPER did not reboot"; exit 1; }
    echo "✅ $SIDE_UPPER flashed"
done



cd - >/dev/null
