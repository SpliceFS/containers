#!/bin/sh
# Checks that every tool of the image is installed and starts, and that the image does not
# run as root unless the run asks for it. The build workflow runs this inside the image, as
# the default user, so that a broken image is not published.
#
# Start the container with --user 0 -e EXPECT_ROOT=1 to prove the root mode: the run must
# then really be root, and every tool still starts.
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

# Without a request for root, the default user is under test, and that user is not root.
# Every tool above has started as that user, which is the proof that installing QEMU did
# not leave the image in a state that only root can use.
uid="$(id -u)"
if [ "${EXPECT_ROOT:-}" = 1 ]; then
    check "the run is root, as asked" test "${uid}" -eq 0
else
    check "the default user is not root" test "${uid}" -ne 0
fi
