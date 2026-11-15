#!/bin/sh
# Tests same-files.sh against a throwaway copy of the repository layout. Run from anywhere:
#   sh scripts/same-files-test.sh
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
cp "${script_dir}/same-files.sh" "${work}/scripts/same-files.sh"
script="${work}/scripts/same-files.sh"

passed=0

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

# put PATH CONTENT makes the file PATH under images/, with its folders.
put() {
    case "$1" in
    */*) mkdir -p "${work}/images/${1%/*}" ;;
    *) ;;
    esac
    printf '%s\n' "$2" >"${work}/images/$1"
}

# reset removes every folder, so that each check starts from its own layout.
reset() {
    rm -rf "${work}/images"
    mkdir -p "${work}/images"
}

# two_folders makes freebsd-14.5 and freebsd-15.1 with the same files, and an "official"
# and a README.md that differ, as they do in the repository.
two_folders() {
    reset
    for name in freebsd-14.5 freebsd-15.1; do
        put "${name}/Dockerfile" "FROM base"
        put "${name}/test.sh" "echo test"
        put "${name}/official" "release of ${name}"
        put "${name}/README.md" "readme of ${name}"
    done
}

# check DESCRIPTION EXPECTED_STATUS EXPECTED_TEXT ARGS...
# The text must be in what the script printed to the error output. An empty text means the
# script must print nothing there.
check() {
    description="$1"
    want_status="$2"
    want_text="$3"
    shift 3
    status=0
    sh "${script}" "$@" >"${work}/stdout" 2>"${work}/stderr" || status=$?
    if [ "${status}" != "${want_status}" ]; then
        errors="$(cat "${work}/stderr")"
        fail "${description}: exit status ${status}, wanted ${want_status} (${errors})"
    fi
    if [ -z "${want_text}" ]; then
        if [ -s "${work}/stderr" ]; then
            errors="$(cat "${work}/stderr")"
            fail "${description}: printed an error (${errors})"
        fi
    elif ! grep -Fq -- "${want_text}" "${work}/stderr"; then
        errors="$(cat "${work}/stderr")"
        fail "${description}: the error output lacks \"${want_text}\" (${errors})"
    fi
    passed=$((passed + 1))
    echo "ok - ${description}"
}

two_folders
check "folders that differ only in official and README.md pass" 0 ""

# The script can be started from another folder.
status=0
(cd "${work}/images" && sh "${script}" >/dev/null 2>&1) || status=$?
if [ "${status}" != 0 ]; then
    fail "the script fails when started from another folder"
fi
passed=$((passed + 1))
echo "ok - the script works from another folder"

put freebsd-15.1/test.sh "echo changed"
check "a file with other content fails and is named" 1 "images/freebsd-15.1/test.sh differs from images/freebsd-14.5/test.sh"

two_folders
rm "${work}/images/freebsd-15.1/test.sh"
check "a file missing in the second folder fails and is named" 1 "images/freebsd-15.1/test.sh is missing"

two_folders
put freebsd-15.1/extra.sh "echo extra"
check "a file missing in the first folder fails and is named" 1 "images/freebsd-14.5/extra.sh is missing"

two_folders
put freebsd-14.5/sub/deep/file "one"
put freebsd-15.1/sub/deep/file "two"
check "a difference in a subfolder is named with its path" 1 "images/freebsd-15.1/sub/deep/file differs"

two_folders
put freebsd-14.5/sub/official "one"
put freebsd-15.1/sub/official "two"
check "only the official of the top of a folder may differ" 1 "images/freebsd-15.1/sub/official differs"

two_folders
put freebsd-15.1/disk.qcow2 "a disk"
put freebsd-15.1/work/official.qcow2 "a download"
check "disk.qcow2 and work/ left by prepare.sh are ignored" 0 ""

# Three folders: the file that differs is named in the folder that has the difference.
two_folders
put freebsd-15.2/Dockerfile "FROM base"
put freebsd-15.2/test.sh "echo test"
check "three identical folders pass" 0 ""

put freebsd-15.2/test.sh "echo changed"
check "a difference in the third folder is found" 1 "images/freebsd-15.2/test.sh differs from images/freebsd-14.5/test.sh"

two_folders
put freebsd-14.5/test.sh "echo changed"
put freebsd-15.2/Dockerfile "FROM base"
put freebsd-15.2/test.sh "echo test"
check "a difference in the first folder is found" 1 "images/freebsd-15.1/test.sh differs from images/freebsd-14.5/test.sh"

# Folders that are not freebsd-* are other images and are not compared.
two_folders
put go-qemu/Dockerfile "FROM other"
put freebsd-notes "a file that is not a folder"
check "other folders and files are not compared" 0 ""

reset
put freebsd-15.1/Dockerfile "FROM base"
check "one folder has nothing to compare with" 0 ""

reset
check "no folder has nothing to compare" 0 ""

two_folders
check "an argument is a usage error" 2 "usage: same-files.sh" extra

echo "${passed} checks passed"
