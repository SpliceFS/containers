#!/bin/sh
# Tests changed-images.sh in a throwaway git repository. Run from anywhere:
#   sh scripts/changed-images-test.sh
set -eu

case "$0" in
*/*) here="${0%/*}" ;;
*) here="." ;;
esac
script_dir="$(cd "${here}" && pwd)"
script="${script_dir}/changed-images.sh"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
trap 'exit 1' HUP INT TERM
repo="${work}/repo"

# The repository must not read the settings of whoever runs the test (signing, hooks,
# default branch). Its own name and email are set in its local config only.
GIT_CONFIG_GLOBAL=/dev/null
GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM

git init -q "${repo}"
git -C "${repo}" config user.name "Test"
git -C "${repo}" config user.email "test@example.com"
git -C "${repo}" config commit.gpgsign false

passed=0

put() {
    case "$1" in
    */*) mkdir -p "${repo}/${1%/*}" ;;
    *) ;;
    esac
    echo "$2" >"${repo}/$1"
}

# Stages everything and commits. The new commit is left in ${rev}.
commit() {
    git -C "${repo}" add -A
    git -C "${repo}" commit -q -m "$1"
    rev="$(git -C "${repo}" rev-parse HEAD)"
}

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

# check DESCRIPTION EXPECTED_STATUS EXPECTED_NAMES ARGS...
# EXPECTED_NAMES is the output with newlines written as spaces.
check() {
    description="$1"
    want_status="$2"
    want_names="$3"
    shift 3
    status=0
    out="$(cd "${repo}" && sh "${script}" "$@" 2>"${work}/stderr")" || status=$?
    if [ "${status}" != "${want_status}" ]; then
        errors="$(cat "${work}/stderr")"
        fail "${description}: exit status ${status}, wanted ${want_status} (${errors})"
    fi
    got="$(printf '%s\n' "${out}" | tr '\n' ' ')"
    got="${got% }"
    if [ "${got}" != "${want_names}" ]; then
        fail "${description}: printed \"${got}\", wanted \"${want_names}\""
    fi
    passed=$((passed + 1))
    echo "ok - ${description}"
}

put README.md "readme"
put scripts/tool.sh "tool"
put images/README.md "about the images"
put images/alpha/Dockerfile "FROM scratch"
put images/beta/Dockerfile "FROM scratch"
put images/beta/README.md "beta"
put images/gamma-2/Dockerfile "FROM scratch"
put images/notes/README.md "a folder without a Dockerfile"
commit "start"
c0="${rev}"

put README.md "readme 2"
put scripts/tool.sh "tool 2"
commit "outside images"
c1="${rev}"
check "a change outside images/ prints nothing" 0 "" "${c0}" "${c1}"

put images/README.md "about the images 2"
commit "file directly under images"
c2="${rev}"
check "a file directly under images/ belongs to no image" 0 "" "${c1}" "${c2}"

put images/notes/README.md "notes 2"
commit "folder without a Dockerfile"
c3="${rev}"
check "a folder without a Dockerfile is not an image" 0 "" "${c2}" "${c3}"

put images/alpha/Dockerfile "FROM scratch 2"
commit "change alpha"
c4="${rev}"
check "a changed Dockerfile prints its image" 0 "alpha" "${c3}" "${c4}"

put images/beta/README.md "beta 2"
commit "change a file of beta"
c5="${rev}"
check "a changed file other than the Dockerfile prints its image" 0 "beta" "${c4}" "${c5}"

put images/beta/files/deep/data.txt "deep"
commit "add a nested file to beta"
c6="${rev}"
check "a nested file prints its image" 0 "beta" "${c5}" "${c6}"

put images/gamma-2/Dockerfile "FROM scratch 2"
put images/alpha/README.md "alpha"
commit "change gamma-2 and alpha"
c7="${rev}"
check "a change in two images prints both, sorted" 0 "alpha gamma-2" "${c6}" "${c7}"

check "a range of several commits prints every changed image" 0 "alpha beta gamma-2" "${c3}" "${c7}"

put images/delta/Dockerfile "FROM scratch"
commit "add delta"
c8="${rev}"
check "an added image is printed" 0 "delta" "${c7}" "${c8}"

git -C "${repo}" rm -q -r images/alpha
put images/beta/Dockerfile "FROM scratch 2"
commit "remove alpha and change beta"
c9="${rev}"
check "a removed image is not printed" 0 "beta" "${c8}" "${c9}"

git -C "${repo}" rm -q images/delta/Dockerfile
put images/delta/README.md "delta without a Dockerfile"
commit "delta loses its Dockerfile"
c10="${rev}"
check "an image that lost its Dockerfile is not printed" 0 "" "${c9}" "${c10}"

zeros="0000000000000000000000000000000000000000"
check "an all-zero base prints every image" 0 "beta gamma-2" "${zeros}" "${c10}"
check "an empty base prints every image" 0 "beta gamma-2" "" "${c10}"
check "--all prints every image" 0 "beta gamma-2" --all
check "an empty base prints every image of the head commit given" 0 "alpha beta delta gamma-2" "" "${c8}"

put images/Bad_Name/Dockerfile "FROM scratch"
commit "add a badly named image"
c11="${rev}"
check "a badly named image is an error" 1 "" "${c10}" "${c11}"
check "a badly named image is an error with --all" 1 "" --all

git -C "${repo}" rm -q -r images/Bad_Name
commit "remove the badly named image"
c12="${rev}"
check "removing a badly named image is allowed" 0 "" "${c11}" "${c12}"

check "no arguments is a usage error" 2 ""
check "one argument other than --all is a usage error" 2 "" "${c12}"
check "three arguments are a usage error" 2 "" "${c11}" "${c12}" "${c12}"
check "an unknown commit is an error" 128 "" "1111111111111111111111111111111111111111" "${c12}"

echo "${passed} checks passed"
