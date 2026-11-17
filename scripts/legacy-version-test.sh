#!/bin/sh
# Tests legacy-version.sh in a throwaway git repository that holds a copy of the scripts.
# Run from anywhere:
#   sh scripts/legacy-version-test.sh
set -eu

case "$0" in
*/*) here="${0%/*}" ;;
*) here="." ;;
esac
script_dir="$(cd "${here}" && pwd)"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
trap 'exit 1' HUP INT TERM
repo="${work}/repo"

# The repository must not read the settings of whoever runs the test.
GIT_CONFIG_GLOBAL=/dev/null
GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM

git init -q "${repo}"
git -C "${repo}" config user.name "Test"
git -C "${repo}" config user.email "test@example.com"
git -C "${repo}" config commit.gpgsign false

# The script finds version-valid.sh, and the repository, from its own place.
mkdir -p "${repo}/scripts"
cp "${script_dir}/legacy-version.sh" "${script_dir}/version-valid.sh" "${repo}/scripts/"
script="${repo}/scripts/legacy-version.sh"

passed=0

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

# version_file NAME CONTENT makes images/NAME/version. Line breaks in CONTENT are
# written as \n.
version_file() {
    mkdir -p "${repo}/images/$1"
    printf '%b' "$2" >"${repo}/images/$1/version"
}

# check DESCRIPTION EXPECTED_STATUS EXPECTED_OUTPUT ARGS...
# The script prints the version on the standard output and nothing else.
check() {
    description="$1"
    want_status="$2"
    want_out="$3"
    shift 3
    status=0
    out="$(cd "${work}" && sh "${script}" "$@" 2>"${work}/stderr")" || status=$?
    errors="$(cat "${work}/stderr")"
    if [ "${status}" != "${want_status}" ]; then
        fail "${description}: exit status ${status}, wanted ${want_status} (${errors})"
    fi
    if [ "${out}" != "${want_out}" ]; then
        fail "${description}: printed \"${out}\", wanted \"${want_out}\""
    fi
    if [ "${status}" -ne 2 ] && [ -n "${errors}" ]; then
        fail "${description}: printed an error (${errors})"
    fi
    passed=$((passed + 1))
    echo "ok - ${description}"
}

version_file one "v1\n"
version_file twelve "v12\n"
version_file new "v1.0.0\n"
version_file minor "v1.2\n"
version_file zero-first "v01\n"
version_file word "latest\n"
version_file empty ""
version_file two-lines "v1\nv2\n"
version_file spaced "v1 \n"
git -C "${repo}" add -A
git -C "${repo}" commit -q -m "versions"
rev="$(git -C "${repo}" rev-parse HEAD)"

check "the old form stands for the same number with .0.0" 0 "v1.0.0" one "${rev}"
check "a number of two digits is kept whole" 0 "v12.0.0" twelve "${rev}"
check "the new form is not the old form" 1 "" new "${rev}"
check "major and minor are not the old form" 1 "" minor "${rev}"
check "a leading zero is not the old form" 1 "" zero-first "${rev}"
check "a word is not the old form" 1 "" word "${rev}"
check "an empty file is not the old form" 1 "" empty "${rev}"
check "two lines are not the old form" 1 "" two-lines "${rev}"
check "a space after the number is not the old form" 1 "" spaced "${rev}"
check "an image without a version file is not the old form" 1 "" missing "${rev}"
check "a commit that does not exist is not the old form" 1 "" one "1111111111111111111111111111111111111111"

check "no argument is a usage error" 2 ""
check "one argument is a usage error" 2 "" one
check "an empty commit is a usage error" 2 "" one ""
check "three arguments are a usage error" 2 "" one "${rev}" extra

echo "${passed} checks passed"
