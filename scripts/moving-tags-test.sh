#!/bin/sh
# Tests moving-tags.sh. Run from anywhere:
#   sh scripts/moving-tags-test.sh
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
cp "${script_dir}/moving-tags.sh" "${script_dir}/version-valid.sh" "${work}/"
script="${work}/moving-tags.sh"

passed=0

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

# check DESCRIPTION EXPECTED_STATUS EXPECTED_OUTPUT EXPECTED_ERROR_TEXT ARGS...
# The expected output is the lines of the tags, the minor tag first. An empty error text
# means the script must print nothing to the error output.
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

check "a version moves its minor tag and its major tag" 0 "v1.2
v1" "" v1.2.3
check "the first version of a line moves both" 0 "v1.0
v1" "" v1.0.0
check "zero is a number in the tags" 0 "v0.0
v0" "" v0.0.0
check "numbers of several digits are kept whole" 0 "v10.20
v10" "" v10.20.30

check "the old form is not a version" 1 "" '"v1" is not a version' v1
check "a minor tag is not a version" 1 "" '"v1.2" is not a version' v1.2
check "latest is not a version" 1 "" '"latest" is not a version' latest
check "an empty text is not a version" 1 "" "is not a version" ""

check "no argument is a usage error" 2 "" "usage: moving-tags.sh"
check "two arguments are a usage error" 2 "" "usage: moving-tags.sh" v1.0.0 v1.0.1

echo "${passed} checks passed"
