#!/bin/sh
# Tests version-valid.sh. Run from anywhere:
#   sh scripts/version-valid-test.sh
set -eu

case "$0" in
*/*) here="${0%/*}" ;;
*) here="." ;;
esac
script_dir="$(cd "${here}" && pwd)"
script="${script_dir}/version-valid.sh"

passed=0

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

# check DESCRIPTION EXPECTED_STATUS ARGS...
# A version is never printed, so the script must print nothing.
check() {
    description="$1"
    want_status="$2"
    shift 2
    status=0
    out="$(sh "${script}" "$@" 2>&1)" || status=$?
    if [ "${status}" != "${want_status}" ]; then
        fail "${description}: exit status ${status}, wanted ${want_status} (${out})"
    fi
    if [ "${status}" != 2 ] && [ -n "${out}" ]; then
        fail "${description}: printed \"${out}\""
    fi
    passed=$((passed + 1))
    echo "ok - ${description}"
}

check "v1 is a version" 0 v1
check "v2 is a version" 0 v2
check "v10 is a version" 0 v10
check "v123 is a version" 0 v123
check "v90 is a version" 0 v90

check "an empty text is not a version" 1 ""
check "v alone is not a version" 1 v
check "v0 is not a version" 1 v0
check "a leading zero is not a version" 1 v01
check "a number without v is not a version" 1 1
check "a capital V is not a version" 1 V1
check "a dot is not a version" 1 v1.0
check "a sign is not a version" 1 v-1
check "a letter after the number is not a version" 1 v1a
check "a space inside is not a version" 1 "v 1"
check "a trailing space is not a version" 1 "v1 "
check "a leading space is not a version" 1 " v1"
check "a line break after the version is not a version" 1 "v1
"
check "a second line is not a version" 1 "v1
v2"
check "latest is not a version" 1 latest
check "a dated tag is not a version" 1 2026-11-14-1a2b3c4

check "no argument is a usage error" 2
check "two arguments are a usage error" 2 v1 v2

echo "${passed} checks passed"
