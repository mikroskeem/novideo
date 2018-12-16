if (glxinfo | grep "OpenGL vendor string:" | grep -q "NVIDIA Corporation"); then
    nvidia-settings --load-config-only
fi

xrdb -l ~/.Xresources
exec systemd-cat --identifier="i3-${DISPLAY}" i3

# vim:ft=sh
