#!/bin/sh
# Turns the container image of an Alpine release into the server that the vendor gives on a
# minimal install: the package alpine-base, which is what Alpine's own setup installs first,
# and which brings OpenRC, the service manager of Alpine, with it. The container image
# leaves all of it out. ca-certificates is added, because every server has them. Two changes
# follow, because a container differs from a server in them, see below. The same file is in the
# folder of every apk server image, and scripts/same-files.sh checks that.
set -eu

# --no-cache keeps the package index out of the layer.
apk add --no-cache alpine-base ca-certificates

# A container cannot reach the hardware that the boot services of OpenRC expect, so OpenRC
# is told that it runs in a container. It then leaves those services out and still reaches
# the default runlevel, which is where packages add their services.
sed -i '/^#*rc_sys=/d' /etc/rc.conf
echo 'rc_sys="docker"' >>/etc/rc.conf

# A container has no console and no terminal, and inittab respawns a getty on tty1 to tty6. Where
# the terminals do not exist, each one fails to open, and where the host shows its own through,
# each one runs a login prompt that nobody reads.
sed -i '/^tty[0-9]*::respawn:\/sbin\/getty/d' /etc/inittab
