#!/bin/sh
# Checks that the image holds what a running server of this family has, and nothing that
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
check "package ca-certificates" installed ca-certificates
check "the certificate bundle is there" test -s /etc/ssl/certs/ca-certificates.crt
refuse "package fuse3 is not installed" installed fuse3
refuse "fusermount3 is not there" command -v fusermount3
refuse "the policy file that stops services from starting is gone" test -e /usr/sbin/policy-rc.d
