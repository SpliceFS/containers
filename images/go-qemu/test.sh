#!/bin/sh
# Checks that every tool of the image is installed and starts. The build workflow runs
# this inside the image, so that a broken image is not published.
set -eu

# Runs a tool with output hidden, and stops the whole test at the first one that is
# missing or does not start.
check() {
    name="$1"
    shift
    if ! "$@" >/dev/null 2>&1; then
        echo "FAIL: ${name}" >&2
        exit 1
    fi
    echo "ok: ${name}"
}

check "go" go version
check "qemu-img" qemu-img --version
check "fusermount3" fusermount3 -V
check "curl" curl --version
check "xz" xz --version
check "zstd" zstd --version

# Each CPU type gets only the emulator of its own package.
machine="$(uname -m)"
case "${machine}" in
x86_64)
    qemu_system="qemu-system-x86_64"
    ;;
aarch64)
    qemu_system="qemu-system-aarch64"
    ;;
*)
    echo "FAIL: no QEMU system program is expected on CPU type ${machine}" >&2
    exit 1
    ;;
esac
check "${qemu_system}" "${qemu_system}" --version
