#!/bin/sh
# Tests version-compare.sh. Run from anywhere:
#   sh scripts/version-compare-test.sh
set -eu

case "$0" in
*/*) here="${0%/*}" ;;
*) here="." ;;
esac
script_dir="$(cd "${here}" && pwd)"

# The script finds version-valid.sh from its own place, so both are copied to a folder
# that holds nothing else.
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
trap 'exit 1' HUP INT TERM
cp "${script_dir}/version-compare.sh" "${script_dir}/version-valid.sh" "${work}/"
script="${work}/version-compare.sh"

passed=0

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

# check DESCRIPTION EXPECTED_STATUS EXPECTED_OUTPUT EXPECTED_ERROR_TEXT ARGS...
# An empty error text means the script must print nothing to the error output.
check() {
    description="$1"
    want_status="$2"
    want_out="$3"
    want_text="$4"
    shift 4
    status=0
    out="$(sh "${script}" "$@" 2>"${work}/stderr")" || status=$?
    errors="$(cat "${work}/stderr")"
    if [ "${status}" != "${want_status}" ]; then
        fail "${description}: exit status ${status}, wanted ${want_status} (${errors})"
    fi
    if [ "${out}" != "${want_out}" ]; then
        fail "${description}: printed \"${out}\", wanted \"${want_out}\""
    fi
    if [ -z "${want_text}" ]; then
        if [ -n "${errors}" ]; then
            fail "${description}: printed an error (${errors})"
        fi
    else
        case "${errors}" in
        *"${want_text}"*) ;;
        *) fail "${description}: the error output lacks \"${want_text}\" (${errors})" ;;
        esac
    fi
    passed=$((passed + 1))
    echo "ok - ${description}"
}

check "the same version is equal" 0 equal "" v1.2.3 v1.2.3
check "zero is equal to zero" 0 equal "" v0.0.0 v0.0.0

check "a greater patch is greater" 0 greater "" v1.2.4 v1.2.3
check "a lower patch is less" 0 less "" v1.2.3 v1.2.4
check "a greater minor is greater" 0 greater "" v1.3.0 v1.2.9
check "a lower minor is less" 0 less "" v1.2.9 v1.3.0
check "a greater major is greater" 0 greater "" v2.0.0 v1.9.9
check "a lower major is less" 0 less "" v1.9.9 v2.0.0

# The numbers are compared as numbers, not as text, in each of the three places.
check "a patch of two digits is greater than one of one digit" 0 greater "" v1.0.10 v1.0.9
check "a minor of two digits is greater than one of one digit" 0 greater "" v1.10.0 v1.9.0
check "a major of two digits is greater than one of one digit" 0 greater "" v10.0.0 v9.0.0
check "a number of two digits is less than a greater one of three" 0 less "" v1.0.99 v1.0.100

# The first place that differs decides, whatever the places after it hold.
check "the major decides before the minor" 0 greater "" v2.0.0 v1.99.99
check "the minor decides before the patch" 0 less "" v1.1.99 v1.2.0

# A number is not turned into a machine integer, so a very long one is still exact.
check "numbers beyond a machine integer are compared exactly" 0 greater "" \
    v1.0.99999999999999999999999999999999 v1.0.99999999999999999999999999999998
check "numbers beyond a machine integer that differ in length" 0 less "" \
    v1.0.99999999999999999999 v1.0.100000000000000000000

check "a first argument that is not a version is an error" 1 "" '"v1" is not a version' v1 v1.0.0
check "a second argument that is not a version is an error" 1 "" '"latest" is not a version' v1.0.0 latest
check "an empty argument is an error" 1 "" "is not a version" "" v1.0.0

check "no argument is a usage error" 2 "" "usage: version-compare.sh"
check "one argument is a usage error" 2 "" "usage: version-compare.sh" v1.0.0
check "three arguments are a usage error" 2 "" "usage: version-compare.sh" v1.0.0 v1.0.1 v1.0.2

echo "${passed} checks passed"
