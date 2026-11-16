#!/bin/sh
# Checks that the image holds what a running server of this family has, and nothing that
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
refuse "package fuse3 is not installed" rpm -q fuse3
refuse "fusermount3 is not there" command -v fusermount3
