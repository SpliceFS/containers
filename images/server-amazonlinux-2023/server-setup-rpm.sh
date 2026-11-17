#!/bin/sh
# Turns the container image of a Rocky Linux, Amazon Linux or openSUSE release into the
# server that the vendor gives on a minimal install, which the container image is a
# stripped-down copy of. The set is the vendor's own, not a list kept here:
#   Rocky Linux:  the group core, the group of the "Minimal Install" of its installer.
#   Amazon Linux: the group base-minimal, "the basic minimal install of Amazon Linux". Its
#                 group core is only five packages that the container image already has.
#   openSUSE:     the pattern base, with the pattern minimal_base that it requires. The
#                 pattern minimal_base alone is already satisfied by the container image,
#                 and has no service manager in it.
# ca-certificates is added, because every server has them. Firmware is left out on Rocky Linux. Weak dependencies are installed
# as the installers of Rocky Linux and openSUSE install them, and are left out on Amazon
# Linux, see there. The same file is in the folder of every rpm server image, and
# scripts/same-files.sh checks that.
set -eu

# shellcheck source=/dev/null
. /etc/os-release
# shellcheck disable=SC2154 # ID is set by /etc/os-release
case "${ID}" in
rocky)
    # --allowerasing lets the full coreutils and curl replace coreutils-single and
    # curl-minimal, which the container image has and the group does not. Firmware is
    # left out: it is for hardware and a kernel, a container has neither, and it would
    # make the image up to 2 GB larger.
    dnf install -y --allowerasing --exclude='*firmware*' @core ca-certificates
    # The package caches stay out of the layer.
    dnf clean all
    ;;
amzn)
    # The group lists everything that the minimal install holds. Its weak dependencies would
    # add systemd-networkd, whose wait-online unit makes a container take two minutes to boot
    # because networkd manages no interface there.
    dnf install -y --allowerasing --setopt=install_weak_deps=False @base-minimal ca-certificates
    dnf clean all
    ;;
opensuse-leap)
    zypper --non-interactive --gpg-auto-import-keys install pattern:base ca-certificates
    zypper clean --all
    ;;
*)
    echo "server-setup-rpm.sh: no minimal server set is known for ${ID}" >&2
    exit 1
    ;;
esac

# The installs gave this image a machine id, and every container made from it would share
# it. Empty, as the vendor's images ship it, makes systemd choose its own at boot.
: >/etc/machine-id
