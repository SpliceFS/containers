#!/bin/sh
# Checks that the image holds what a minimal server of this vendor has, and nothing that
# SpliceFS packages install themselves. The build workflow runs this inside the image, so
# that a broken image is not published. Process 1 is not checked here, because the check
# runs in place of the service manager; boot the image as the README says to see that.
# The same file is in the folder of every deb server image, and scripts/same-files.sh
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

# Says so, and fails nothing, when the command succeeds.
note() {
    message="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "note: ${message}"
    fi
}

# Status 0 when /etc/machine-id is a file with nothing in it.
empty_machine_id() {
    [ -f /etc/machine-id ] && [ ! -s /etc/machine-id ]
}

# Status 0 when dpkg says the package is installed.
installed() {
    # dpkg-query reads ${db:Status-Status} itself, the shell must not.
    # shellcheck disable=SC2016
    status="$(dpkg-query -W -f='${db:Status-Status}' "$1" 2>/dev/null || true)"
    [ "${status}" = installed ]
}

check "the service manager is there" test -x /lib/systemd/systemd
check "systemctl is there" command -v systemctl
check "package systemd" installed systemd
check "package systemd-sysv" installed systemd-sysv
check "package ca-certificates" installed ca-certificates
check "the certificate bundle is there" test -s /etc/ssl/certs/ca-certificates.crt
refuse "the policy file that stops services from starting is gone" test -e /usr/sbin/policy-rc.d
check "machine-id exists and is empty, so that each machine makes its own" empty_machine_id

# The rest is the vendor's own set. Debian: the packages of priority required and important
# are what its installer puts on a minimal install, and iproute2 and init stand for them.
# Ubuntu: the metapackage of its minimal server install.
# shellcheck source=/dev/null
. /etc/os-release
# shellcheck disable=SC2154 # ID is set by /etc/os-release
case "${ID}" in
debian)
    check "package init" installed init
    check "package iproute2" installed iproute2
    refuse "package fuse3 is not installed" installed fuse3
    refuse "fusermount3 is not there" command -v fusermount3
    ;;
ubuntu)
    check "package ubuntu-server-minimal" installed ubuntu-server-minimal
    # The Ubuntu set brings fuse3 itself. The image keeps what the vendor's set has, so this
    # only says so.
    note "fuse3 is installed, the vendor set ubuntu-server-minimal brings it" installed fuse3
    ;;
*)
    echo "FAIL: unknown system ${ID}" >&2
    exit 1
    ;;
esac
