#!/bin/sh
# Tests image-version.sh in a throwaway git repository that holds a copy of the scripts
# and an images folder. Run from anywhere:
#   sh scripts/image-version-test.sh
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

# The script finds the repository from its own place.
mkdir -p "${repo}/scripts" "${repo}/images"
cp "${script_dir}/image-version.sh" "${script_dir}/version-valid.sh" "${repo}/scripts/"
script="${repo}/scripts/image-version.sh"

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

# commit stages everything and commits. The new commit is left in ${rev}.
commit() {
    git -C "${repo}" add -A
    git -C "${repo}" commit -q -m "$1"
    rev="$(git -C "${repo}" rev-parse HEAD)"
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
    out="$(cd "${work}" && sh "${script}" "$@" 2>"${work}/stderr")" || status=$?
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

version_file alpha "v1.0.0\n"
check "a version file prints its version" 0 "v1.0.0" "" alpha

version_file alpha "v7.1.2"
check "a last line without a line break counts" 0 "v7.1.2" "" alpha

version_file alpha "v12.30.45\n"
check "a version of two digits in each place is printed whole" 0 "v12.30.45" "" alpha

# The version of the working files is not the version of a commit.
version_file alpha "v1.0.0\n"
version_file beta "v3.1.4\n"
commit "first versions"
c1="${rev}"
version_file alpha "v2.0.0\n"
check "without a commit the working file is read" 0 "v2.0.0" "" alpha
check "with a commit the version of that commit is read" 0 "v1.0.0" "" alpha "${c1}"
check "a branch name or HEAD works as a commit" 0 "v3.1.4" "" beta HEAD

version_file gamma "v1.0.0\n"
check "an image with no version file at the commit exits 3" 3 "" "images/gamma/version" gamma "${c1}"
check "an image without a version file exits 3" 3 "" "images/delta/version" delta
check "a commit that does not exist exits 3" 3 "" "images/alpha/version" alpha "1111111111111111111111111111111111111111"

for bad in "v1\n" "v1.2\n" "v1.2.3.4\n" "v01.2.3\n" "v1.02.3\n" "v1.2.03\n" "1.2.3\n" "latest\n" "V1.2.3\n" "v1.2.3-rc1\n" "v1.2.3 \n" " v1.2.3\n" "v1.2.3\r\n"; do
    version_file bad "${bad}"
    check "a malformed version is an error: ${bad}" 1 "" "use vMAJOR.MINOR.PATCH, as in v1.0.0" bad
done
commit "malformed versions"
check "a malformed version of a commit is an error" 1 "" "is not a version" bad "${rev}"

version_file empty ""
check "an empty version file is an error" 1 "" "one line" empty

version_file blank "\n"
check "a version file of one blank line is an error" 1 "" "is not a version" blank

version_file two-lines "v1.0.0\nv2.0.0\n"
check "two lines are an error" 1 "" "one line" two-lines

version_file trailing-blank "v1.0.0\n\n"
check "a blank line after the version is an error" 1 "" "one line" trailing-blank
commit "more malformed versions"
check "two lines of a commit are an error" 1 "" "one line" two-lines "${rev}"

mkdir -p "${repo}/images/folder/version"
check "a version that is a folder is an error" 1 "" "is not a file" folder

check "no arguments is a usage error" 2 "" "usage: image-version.sh"
check "an empty commit is a usage error, it would read the index" 2 "" "usage: image-version.sh" alpha ""
check "three arguments are a usage error" 2 "" "usage: image-version.sh" alpha "${c1}" extra

echo "${passed} checks passed"
