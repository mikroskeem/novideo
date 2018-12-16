if [[ ! "${DISPLAY}" ]] && ([[ "${XDG_VTNR}" -eq 1 ]] && [[ "${TERM}" = "linux" ]]); then
    /usr/local/bin/toggle_nvidia.sh restore
    exec startx
fi
