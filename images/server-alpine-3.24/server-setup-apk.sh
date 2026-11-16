#!/bin/sh
# Turns the container image of an Alpine release into a server that is up and running: the
# vendor's own service manager, OpenRC, which the container image leaves out, and
# ca-certificates, which every server has. Nothing else is installed. One setting of OpenRC
# is changed, see below. The same file is in the folder of every apk server image, and
# scripts/same-files.sh checks that.
set -eu

# --no-cache keeps the package index out of the layer.
apk add --no-cache openrc ca-certificates

# A container cannot reach the hardware that the boot services of OpenRC expect, so OpenRC
# is told that it runs in a container. It then leaves those services out and still reaches
# the default runlevel, which is where packages add their services.
sed -i '/^#*rc_sys=/d' /etc/rc.conf
echo 'rc_sys="docker"' >>/etc/rc.conf
