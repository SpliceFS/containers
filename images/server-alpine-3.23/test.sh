#!/bin/sh
# Checks that the image holds what a minimal server of this vendor has, and nothing that
# SpliceFS packages install themselves. The build workflow runs this inside the image, so
# that a broken image is not published. Process 1 is not checked here, because the check
# runs in place of the service manager; boot the image as the README says to see that.
# The same file is in the folder of every apk server image, and scripts/same-files.sh
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

check "the service manager is there" test -x /sbin/openrc
check "the init of the system is there" test -x /sbin/init
check "rc-status is there" command -v rc-status
check "package alpine-base" apk info -e alpine-base
check "package openrc" apk info -e openrc
check "package ca-certificates" apk info -e ca-certificates
check "the certificate bundle is there" test -s /etc/ssl/certs/ca-certificates.crt
check "OpenRC knows it runs in a container" grep -q '^rc_sys="docker"$' /etc/rc.conf
# A container has no console and no terminal, so the getty that inittab respawns on tty1 to tty6
# is no part of a valid boot: it fails to open the terminal, or, where the host shows its
# terminals through, it runs a login prompt that nobody reads.
refuse "inittab starts no getty" grep -q '^[^#].*getty' /etc/inittab
refuse "package fuse3 is not installed" apk info -e fuse3
refuse "fusermount3 is not there" command -v fusermount3
