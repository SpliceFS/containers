#!/bin/sh
# Tests image-arches.sh against a throwaway copy of the repository layout. Run from anywhere:
#   sh scripts/image-arches-test.sh
set -eu

case "$0" in
*/*) here="${0%/*}" ;;
*) here="." ;;
esac
script_dir="$(cd "${here}" && pwd)"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
trap 'exit 1' HUP INT TERM

# The script finds the images folder from its own place, so it is copied next to a
# throwaway images folder.
mkdir -p "${work}/scripts" "${work}/images"
cp "${script_dir}/image-arches.sh" "${work}/scripts/image-arches.sh"
script="${work}/scripts/image-arches.sh"

passed=0

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

# arch_file NAME CONTENT makes images/NAME/arch. Line breaks in CONTENT are written as \n.
arch_file() {
    mkdir -p "${work}/images/$1"
    printf '%b' "$2" >"${work}/images/$1/arch"
}

# check DESCRIPTION EXPECTED_STATUS EXPECTED_ARCHES ARGS...
# EXPECTED_ARCHES is the output with newlines written as spaces.
check() {
    description="$1"
    want_status="$2"
    want_arches="$3"
    shift 3
    status=0
    out="$(sh "${script}" "$@" 2>"${work}/stderr")" || status=$?
    if [ "${status}" != "${want_status}" ]; then
        errors="$(cat "${work}/stderr")"
        fail "${description}: exit status ${status}, wanted ${want_status} (${errors})"
    fi
    got="$(printf '%s\n' "${out}" | tr '\n' ' ')"
    got="${got% }"
    if [ "${got}" != "${want_arches}" ]; then
        fail "${description}: printed \"${got}\", wanted \"${want_arches}\""
    fi
    passed=$((passed + 1))
    echo "ok - ${description}"
}

mkdir -p "${work}/images/plain"
check "an image without an arch file is built for both" 0 "amd64 arm64" plain

arch_file only-amd64 "amd64\n"
check "an arch file with amd64 prints amd64" 0 "amd64" only-amd64

arch_file only-arm64 "arm64\n"
check "an arch file with arm64 prints arm64" 0 "arm64" only-arm64

arch_file both "amd64\narm64\n"
check "an arch file with both prints both" 0 "amd64 arm64" both

arch_file reversed "arm64\namd64\n"
check "the order of the file is kept" 0 "arm64 amd64" reversed

arch_file no-break "amd64"
check "a last line without a line break counts" 0 "amd64" no-break

arch_file blanks "\namd64\n\narm64\n\n"
check "blank lines are ignored" 0 "amd64 arm64" blanks

arch_file unknown "amd64\nppc64\n"
check "an unknown CPU type is an error" 1 "" unknown

arch_file upper "AMD64\n"
check "a CPU type in capital letters is an error" 1 "" upper

arch_file two-words "amd64 arm64\n"
check "two types on one line are an error" 1 "" two-words

arch_file padded "amd64 \n"
check "a space after the type is an error" 1 "" padded

arch_file empty ""
check "an empty arch file is an error" 1 "" empty

arch_file only-blanks "\n\n"
check "an arch file of blank lines is an error" 1 "" only-blanks

arch_file twice "amd64\narm64\namd64\n"
check "the same type twice is an error" 1 "" twice

mkdir -p "${work}/images/folder/arch"
check "an arch that is a folder is an error" 1 "" folder

# A release number in a name has a dot, as in freebsd-15.1.
arch_file with-1.5 "amd64\n"
check "a name with a dot is allowed" 0 "amd64" with-1.5
check "an upper case image name is an error" 1 "" Bad_Name
check "an image name with a slash is an error" 1 "" ../plain
check "an empty image name is an error" 1 "" ""
check "no arguments is a usage error" 2 ""
check "two arguments are a usage error" 2 "" plain both

echo "${passed} checks passed"
