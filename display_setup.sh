#!/bin/bash

# this script is ran in X11/Sway session
CONFIG_FILE="/etc/optimus_setup.json"

is_nvidia () {
    [ "$(jq -r .use_optimus "${CONFIG_FILE}")" = "true" ]
    return "${?}"
}

is_sway () {
    [ -n "${SWAYSOCK}" ]
    return "${?}"
}

get_dpi () {
    jq -r .dpi /etc/optimus_setup.json
}

get_enabled_outputs () {
    # TODO: sed usage here is a dirty hack
    xrandr \
        | sed 's/primary//' \
        | awk '$2 == "connected" && $3 ~ /^[0-9]*x[0-9]*+[0-9]*+[0-9]*/ { print $1 }'
}

get_primary () {
    xrandr | awk '$3 == "primary" { print $1" "$4  }'
}

# Prepare LID configuration
LID="$(jq -r .hardware.lid_button "${CONFIG_FILE}")"
LID_STATE="$(awk '/^state:/ { print $2 }' "/proc/acpi/button/lid/${LID}/state")"
LID_OUTPUT="$(jq -r .hardware.lid_output "${CONFIG_FILE}")"
EXT_OUTPUT="$(jq -r .hardware.external_output "${CONFIG_FILE}")"

if is_nvidia; then
    # NVIDIA changes output names for some reason
    LID_OUTPUT="eDP-1-1"
    EXT_OUTPUT="HDMI-1-1"
fi

if is_sway; then
    # Another can of worms...
    LID_OUTPUT="eDP-1"
    EXT_OUTPUT="HDMI-A-1"
fi

# Setup monitors based on a laptop lid state
case "${LID_STATE}" in
    open)
        # no-op
        ;;
    closed)
        # Turn the lid output off
        if is_sway; then
            swaymsg output "${LID_OUTPUT}" disable
        else
            xrandr --output "${LID_OUTPUT}" --noprimary --off
        fi

        # Set new primary output
        if ! is_sway; then
            xrandr --output "${EXT_OUTPUT}" --primary
        fi
        ;;
    *)
        echo "Unknown lid state: '${LID_STATE}'"
        ;;
esac

# Set up NVIDIA output source
if is_nvidia; then
    # Set the provider output source
    xrandr --setprovideroutputsource modesetting NVIDIA-0

    # Work around double cursor issue
    get_enabled_outputs | while read -r output; do
        xrandr --output "${output}" --set 'PRIME Synchronization' '0'
        xrandr --output "${output}" --set 'PRIME Synchronization' '1'
    done

    # Work around the Vulkan ICD quirk
    export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/nvidia_icd.json

    # DPI
    xrandr --dpi "$(get_dpi)"

    # TODO: is this really required? Causes eDP output still get enabled
    #xrandr --auto
fi

# Move mouse to the middle of the screen
PRIMARY="$(get_primary | awk '{print $2}' | sed 's/\+.*//')"
X="$(echo -n "${PRIMARY}" | cut -dx -f 1)"
Y="$(echo -n "${PRIMARY}" | cut -dx -f 2)"

xdotool mousemove $((X / 2)) $((Y / 2))
