#!/bin/sh
# Checks that the image holds what a minimal server of this vendor has, and nothing that
# SpliceFS packages install themselves. The build workflow runs this inside the image, so
# that a broken image is not published. Process 1 is not checked here, because the check
# runs in place of the service manager; boot the image as the README says to see that.
# The same file is in the folder of every rpm server image, and scripts/same-files.sh
# checks that.
set -eu

# Runs a command with output hidden, and stops the whole test when it fails.
check() {
    name="$1"
    shift
    if ! "$@" >/dev/null 2>&1; then
        echo "FAIL: ${name}" >&2
        exit 1
    fi
    echo "ok: ${name}"
}

# The same for a command that must fail.
refuse() {
    name="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "FAIL: ${name}" >&2
        exit 1
    fi
    echo "ok: ${name}"
}

# Status 0 when /etc/machine-id is a file with nothing in it, and no other file named
# machine-id holds an id either (dbus keeps a copy of its own on some systems, and that copy
# would give every machine the id of the image).
empty_machine_id() {
    [ -f /etc/machine-id ] && [ ! -s /etc/machine-id ] || return 1
    stray="$(find / -xdev -name machine-id -type f -size +0c 2>/dev/null)"
    [ -z "${stray}" ]
}

# Status 0 when the unit is masked. The service manager is not running when this test runs, so
# the answer comes from the unit files alone.
masked() {
    state="$(systemctl is-enabled "$1" 2>/dev/null)" || true
    [ "${state}" = masked ]
}

# Status 0 when the system has a certificate bundle: Rocky Linux and Amazon Linux keep it in
# one place, openSUSE in another.
bundle() {
    for file in /etc/pki/tls/certs/ca-bundle.crt /etc/ssl/ca-bundle.pem; do
        if [ -s "${file}" ]; then
            return 0
        fi
    done
    return 1
}

check "the service manager is there" test -x /usr/lib/systemd/systemd
check "systemctl is there" command -v systemctl
check "package systemd" rpm -q systemd
check "package ca-certificates" rpm -q ca-certificates
check "the certificate bundle is there" bundle
check "machine-id exists and is empty, so that each machine makes its own" empty_machine_id

# A container has no console and no terminal, so a getty that systemd starts on one is no part
# of a valid boot, and it dumps core after the container restarts. getty@tty1.service is asked
# too, to see that masking the template covers its instances.
check "console-getty.service is masked" masked console-getty.service
check "getty@.service is masked" masked getty@.service
check "getty@tty1.service is masked" masked getty@tty1.service
check "serial-getty@.service is masked" masked serial-getty@.service
check "getty.target is masked" masked getty.target

refuse "package fuse3 is not installed" rpm -q fuse3
refuse "fusermount3 is not there" command -v fusermount3

# The rest is the vendor's own set, which its installer puts on a minimal install. Rocky
# Linux: the group core, and openssh-server and firewalld stand for it. Amazon Linux: the
# group base-minimal, and openssh-server and chrony stand for it. openSUSE: the pattern base,
# which is the package patterns-base-base.
# shellcheck source=/dev/null
. /etc/os-release
# shellcheck disable=SC2154 # ID is set by /etc/os-release
case "${ID}" in
rocky)
    check "package openssh-server" rpm -q openssh-server
    check "package firewalld" rpm -q firewalld
    # Firmware is for hardware and a kernel, and a container has neither.
    refuse "no firmware package is installed" sh -c 'rpm -qa | grep -q firmware'
    ;;
amzn)
    check "package openssh-server" rpm -q openssh-server
    check "package chrony" rpm -q chrony
    # update-motd runs for about 30 seconds at every boot and holds systemd in the state
    # starting, and a container has no login that would show the message.
    check "update-motd.service is masked" masked update-motd.service
    check "update-motd.timer is masked" masked update-motd.timer
    ;;
opensuse-leap)
    check "package patterns-base-base" rpm -q patterns-base-base
    ;;
*)
    echo "FAIL: unknown system ${ID}" >&2
    exit 1
    ;;
esac
