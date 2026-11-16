#!/bin/sh
# Turns the container image of a Debian or Ubuntu release into a server that is up and
# running: the vendor's own service manager, which the container image leaves out, and
# ca-certificates, which every server has. Nothing else is installed, and no recommended
# packages, because systemd runs without them. One file of the vendor image is removed,
# because a server does not have it. The same file is in the folder of every deb server
# image, and scripts/same-files.sh checks that.
set -eu

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends systemd ca-certificates
# The package lists stay out of the layer. Nothing on a server needs them at rest, and the
# package tests fetch their own.
rm -rf /var/lib/apt/lists/*

# The vendor image holds a policy file that forbids every package from starting a service,
# because images are built without a running service manager. A server has no such file, and
# here the service manager runs, so with it a package would install and stay stopped. It is
# removed after the installs above, because the build has no service manager to start
# anything with.
rm -f /usr/sbin/policy-rc.d
