#!/bin/sh
# Turns the container image of a Debian or Ubuntu release into the server that the vendor's
# installer gives on a minimal install, which the container image is a stripped-down copy of:
# no service manager, no init, no network tools. The set is the vendor's own, not a list kept
# here:
#   Debian: every package of priority required or important, which is what the installer
#           puts on a system when no task is chosen, plus systemd-sysv.
#   Ubuntu: the metapackage ubuntu-server-minimal, which is the minimal server install.
# ca-certificates is added, because every server has them. Recommended packages are left
# out, as the vendors' installers leave them out of the base system. Three changes follow,
# because a container image differs from a server in them, see the end. The same file is in
# the folder of every deb server image, and scripts/same-files.sh checks that.
set -eu

export DEBIAN_FRONTEND=noninteractive
apt-get update

# priority_packages prints the names of the packages of priority required or important in the
# archive that apt just read. apt-cache is used because every image has it, and it needs no
# other tool than awk.
priority_packages() {
    apt-cache dumpavail | awk -v RS= -F'\n' '
        {
            name = ""
            priority = ""
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^Package: /) name = substr($i, 10)
                if ($i ~ /^Priority: /) priority = substr($i, 11)
            }
            if (priority == "required" || priority == "important") print name
        }' | sort -u
}

# shellcheck source=/dev/null
. /etc/os-release
# shellcheck disable=SC2154 # ID is set by /etc/os-release
case "${ID}" in
debian)
    list="$(mktemp)"
    priority_packages >"${list}"
    set -- systemd-sysv
    while IFS= read -r package; do
        set -- "$@" "${package}"
    done <"${list}"
    rm -f "${list}"
    ;;
ubuntu)
    set -- ubuntu-server-minimal
    ;;
*)
    echo "server-setup-deb.sh: no minimal server set is known for ${ID}" >&2
    exit 1
    ;;
esac
apt-get install -y --no-install-recommends "$@" ca-certificates

# The package lists stay out of the layer. Nothing on a server needs them at rest, and the
# package tests fetch their own.
rm -rf /var/lib/apt/lists/*

# The vendor image holds a policy file that forbids every package from starting a service,
# because images are built without a running service manager. A server has no such file, and
# here the service manager runs, so with it a package would install and stay stopped. It is
# removed after the installs above, because the build has no service manager to start
# anything with.
rm -f /usr/sbin/policy-rc.d

# A container has no console and no terminal, so a getty that systemd starts on one is no part
# of a valid boot, and after the container restarts it dumps core. Masking the template
# getty@.service covers its instances, and masking getty.target keeps the units that the
# target pulls in from starting.
systemctl mask console-getty.service getty@.service serial-getty@.service getty.target

# The installs gave this image a machine id, and every container made from it would share
# it. Empty, as the vendor's images ship it, makes systemd choose its own at boot. dbus keeps
# a copy of the id of its own, a plain file on Ubuntu, and would hand it back to
# /etc/machine-id at boot. On a server that copy is a link to /etc/machine-id.
: >/etc/machine-id
if [ -e /var/lib/dbus/machine-id ]; then
    ln -sf /etc/machine-id /var/lib/dbus/machine-id
fi
