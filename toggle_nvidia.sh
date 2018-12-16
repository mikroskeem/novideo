#!/bin/bash -x

if [ "$(id -u)" -ne 0 ]; then
    exec sudo "${0}" "${@}"
fi

OPTIMUS_CONFIG="/etc/optimus_setup.json"
INTEL_XORG_CONFIG="/etc/X11/xorg.conf.d/10-intel.conf"
NVIDIA_XORG_CONFIG="/usr/share/X11/xorg.conf.d/10-nvidia-drm-outputclass.conf"

XORG_CONF='
Section "Module"
    Disable "nvidia"
EndSection

Section "OutputClass"
    Identifier "Intel"
    Option "PrimaryGPU" "yes"
    Driver "intel"
EndSection

Section "OutputClass"
    Identifier "nvidia"
    MatchDriver "nvidia-drm"
    Driver "none"
    ModulePath "/usr/lib/xorg/modules"
EndSection

Section "Device"
    Identifier "Intel Graphics"
    Driver "intel"
    Option "TearFree" "true"
    Option "Tiling" "true"
    Option "SwapbuffersWait" "true"
EndSection
'

USE_NVIDIA="$(jq .use_optimus "${OPTIMUS_CONFIG}")"

has_module() {
    test -d /sys/module/"${1}"
}

rmmod_loaded () {
    has_module "${1}" && \
        rmmod "${1}"
}

has_nvidia () {
    has_module "nvidia"
    return ${?}
}

is_masked () {
    grep -q "${1}" /proc/mounts
    return "${?}"
}

mask () {
    if ! is_masked "${1}"; then
        mount --bind /dev/null "${1}"
    fi
}

unmask () {
    if is_masked "${1}"; then
        umount "${1}"
    fi
}

nvidia_off () {
    # Disable Xorg configuration
    mask "${NVIDIA_XORG_CONFIG}"
    unmask "${INTEL_XORG_CONFIG}"

    # Overwrite old Intel Xorg config
    echo -en "${XORG_CONF}" | tee "${INTEL_XORG_CONFIG}" > /dev/null

    # Remove modules and turn GPU off
    rmmod_loaded "nvidia_drm"
    rmmod_loaded "nvidia_modeset"
    rmmod_loaded "nvidia_uvm"
    rmmod_loaded "nvidia"

    # Turn GPU off
    if [ "$(awk '{print $2}' /proc/acpi/bbswitch)" = "ON" ]; then
        echo "OFF" | tee /proc/acpi/bbswitch > /dev/null
    fi
}

nvidia_on () {
    # Restore Xorg configuration
    mask "${INTEL_XORG_CONFIG}"
    unmask "${NVIDIA_XORG_CONFIG}"

    # Turn GPU on
    if [ "$(awk '{print $2}' /proc/acpi/bbswitch)" = "OFF" ]; then
        echo "ON" | tee /proc/acpi/bbswitch > /dev/null
    fi

    # Load nvidia modules
    has_module "nvidia_drm" || modprobe nvidia_drm modeset=1
    has_module "nvidia_modeset" || modprobe nvidia_modeset
    has_module "nvidia_uvm" || modprobe nvidia_uvm
    has_module "nvidia" || modprobe nvidia
}

write_config () {
    jq -M ".use_optimus = ${1}" "${OPTIMUS_CONFIG}" | sponge "${OPTIMUS_CONFIG}"
}

# toggle_nvidia.sh is used mostly before launching the Xorg session
if [ "${1}" = "restore" ]; then
    # Ensure that needed modules are loaded
    has_module "bbswitch" || modprobe bbswitch

    if [ "${USE_NVIDIA}" = "true" ]; then
        nvidia_on
    else
        nvidia_off
    fi

    exit 0
fi

if [ "${USE_NVIDIA}" = "true" ]; then
    echo "Switched to Intel"
    write_config "false"
else
    echo "Switched to NVIDIA"
    write_config "true"
fi

echo "*** Restart your Xorg session"
