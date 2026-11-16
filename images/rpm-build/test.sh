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

check "rpmbuild" rpmbuild --version
check "rpm" rpm --version
check "rpmsign" rpmsign --version
check "createrepo_c" createrepo_c --version
check "gpg" gpg --version
