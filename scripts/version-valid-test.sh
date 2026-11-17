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

check "v1.0.0 is a version" 0 v1.0.0
check "v1.2.3 is a version" 0 v1.2.3
check "v10.20.30 is a version" 0 v10.20.30
check "v0.0.0 is a version, zero is a number" 0 v0.0.0
check "v0.1.0 is a version" 0 v0.1.0
check "a number of many digits is a version" 0 v1.123456789012345678901234567890.0

check "an empty text is not a version" 1 ""
check "v alone is not a version" 1 v
check "the old form v1 is not a version" 1 v1
check "major and minor alone are not a version" 1 v1.2
check "a fourth number is not a version" 1 v1.2.3.4
check "a leading zero in the major is not a version" 1 v01.2.3
check "a leading zero in the minor is not a version" 1 v1.02.3
check "a leading zero in the patch is not a version" 1 v1.2.03
check "an empty major is not a version" 1 v.2.3
check "an empty minor is not a version" 1 v1..3
check "an empty patch is not a version" 1 v1.2.
check "a number without v is not a version" 1 1.2.3
check "a capital V is not a version" 1 V1.2.3
check "a sign is not a version" 1 v1.-2.3
check "a pre-release suffix is not a version" 1 v1.2.3-rc1
check "a build suffix is not a version" 1 v1.2.3+5
check "a letter after the patch is not a version" 1 v1.2.3a
check "a letter inside is not a version" 1 v1.x.3
check "a space inside is not a version" 1 "v1.2. 3"
check "a trailing space is not a version" 1 "v1.2.3 "
check "a leading space is not a version" 1 " v1.2.3"
check "a line break after the version is not a version" 1 "v1.2.3
"
check "a second line is not a version" 1 "v1.2.3
v1.2.4"
check "latest is not a version" 1 latest
check "a dated tag is not a version" 1 2026-11-14-1a2b3c4

check "no argument is a usage error" 2
check "two arguments are a usage error" 2 v1.0.0 v2.0.0

echo "${passed} checks passed"
