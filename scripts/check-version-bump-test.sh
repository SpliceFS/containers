#!/bin/sh
# Tests check-version-bump.sh in a throwaway git repository that holds a copy of the
# scripts. Run from anywhere:
#   sh scripts/check-version-bump-test.sh
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

# The script finds the other scripts, and they find the repository, from their own place.
mkdir -p "${repo}/scripts"
for name in check-version-bump changed-images image-version version-valid; do
    cp "${script_dir}/${name}.sh" "${repo}/scripts/${name}.sh"
done
script="${repo}/scripts/check-version-bump.sh"

passed=0

put() {
    case "$1" in
    */*) mkdir -p "${repo}/${1%/*}" ;;
    *) ;;
    esac
    printf '%s\n' "$2" >"${repo}/$1"
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

# check DESCRIPTION EXPECTED_STATUS EXPECTED_TEXT... -- ARGS...
# Every text must be in what the script printed, standard and error output together. With
# no text, the script must print nothing.
check() {
    description="$1"
    want_status="$2"
    shift 2
    texts=""
    while [ "$1" != "--" ]; do
        texts="${texts}${1}
"
        shift
    done
    shift
    status=0
    (cd "${repo}" && sh "${script}" "$@") >"${work}/output" 2>&1 || status=$?
    output="$(cat "${work}/output")"
    if [ "${status}" != "${want_status}" ]; then
        fail "${description}: exit status ${status}, wanted ${want_status} (${output})"
    fi
    if [ -z "${texts}" ] && [ -n "${output}" ]; then
        fail "${description}: printed \"${output}\""
    fi
    while IFS= read -r text; do
        if [ -n "${text}" ] && ! grep -Fq -- "${text}" "${work}/output"; then
            fail "${description}: the output lacks \"${text}\" (${output})"
        fi
    done <<TEXTS
${texts}
TEXTS
    passed=$((passed + 1))
    echo "ok - ${description}"
}

put README.md "readme"
put images/alpha/Dockerfile "FROM scratch"
put images/alpha/version "v1"
put images/beta/Dockerfile "FROM scratch"
put images/beta/version "v4"
commit "start"
c0="${rev}"

put README.md "readme 2"
commit "outside images"
c1="${rev}"
check "a change outside images/ needs no version" 0 -- "${c0}" "${c1}"

put images/alpha/Dockerfile "FROM scratch 2"
commit "change alpha, same version"
c2="${rev}"
check "a changed image with the same version fails" 1 \
    "images/alpha changed, but its version v1 is not greater than v1" \
    "raise images/alpha/version" -- "${c1}" "${c2}"

put images/alpha/version "v2"
commit "raise alpha"
c3="${rev}"
check "a changed image with a greater version passes" 0 "images/alpha: v1 -> v2" -- "${c1}" "${c3}"

put images/alpha/Dockerfile "FROM scratch 3"
put images/alpha/version "v5"
commit "change alpha, skip versions"
c4="${rev}"
check "a range of several commits compares only the versions at its two ends" 0 \
    "images/alpha: v1 -> v5" -- "${c1}" "${c4}"
check "a version that skips numbers passes" 0 "images/alpha: v2 -> v5" -- "${c3}" "${c4}"

put images/alpha/Dockerfile "FROM scratch 4"
put images/alpha/version "v3"
commit "change alpha, lower the version"
c5="${rev}"
check "a lower version fails" 1 "images/alpha changed, but its version v3 is not greater than v5" -- "${c4}" "${c5}"

put images/alpha/version "v10"
commit "alpha to v10"
c6="${rev}"
check "the versions are compared as numbers, v10 is greater than v5" 0 "images/alpha: v5 -> v10" -- "${c4}" "${c6}"

put images/alpha/version "v11"
commit "only the version of alpha"
c7="${rev}"
check "a change of only the version file passes" 0 "images/alpha: v10 -> v11" -- "${c6}" "${c7}"

put images/alpha/README.md "about alpha"
put images/beta/README.md "about beta"
put images/beta/version "v5"
commit "change alpha and beta, raise only beta"
c8="${rev}"
check "an image that is not raised fails and a raised one passes" 1 \
    "images/alpha changed, but its version v11 is not greater than v11" \
    "images/beta: v4 -> v5" -- "${c7}" "${c8}"

put images/alpha/README.md "about alpha 2"
put images/beta/README.md "about beta 2"
commit "change alpha and beta, raise none"
c9="${rev}"
check "every image that is not raised is named" 1 \
    "images/alpha changed, but its version v11 is not greater than v11" \
    "images/beta changed, but its version v5 is not greater than v5" -- "${c8}" "${c9}"

put images/alpha/version "v12"
commit "raise alpha"
c10="${rev}"
check "a range of several commits compares the versions at its two ends" 0 \
    "images/alpha: v11 -> v12" "images/beta: v4 -> v5" -- "${c7}" "${c10}"

put images/gamma/Dockerfile "FROM scratch"
put images/gamma/version "v1"
commit "add gamma"
c11="${rev}"
check "a new image with a version passes" 0 "images/gamma: v1 (new)" -- "${c10}" "${c11}"

put images/delta/Dockerfile "FROM scratch"
commit "add delta without a version"
c12="${rev}"
check "a new image without a version file fails" 1 "images/delta changed and has no version" "images/delta/version" -- "${c11}" "${c12}"

put images/delta/version "v01"
commit "delta with a malformed version"
c13="${rev}"
check "a new image with a malformed version fails" 1 "images/delta/version" "is not a version" -- "${c12}" "${c13}"

put images/delta/version "v1"
commit "delta with a version"
c14="${rev}"
check "an image that gets its first version passes, as when the rule begins" 0 "images/delta: v1 (new)" -- "${c12}" "${c14}"

# A malformed version on the base cannot be compared with.
put images/epsilon/Dockerfile "FROM scratch"
put images/epsilon/version "latest"
commit "epsilon with a malformed version"
c15="${rev}"
put images/epsilon/Dockerfile "FROM scratch 2"
put images/epsilon/version "v2"
commit "epsilon repaired"
c16="${rev}"
check "a malformed version on the base fails" 1 "is not a version" "images/epsilon" -- "${c15}" "${c16}"

git -C "${repo}" rm -q -r images/beta
commit "remove beta"
c17="${rev}"
check "a removed image needs no version" 0 -- "${c16}" "${c17}"

zeros="0000000000000000000000000000000000000000"
check "an all-zero base means every image is new" 0 \
    "images/alpha: v12 (new)" "images/delta: v1 (new)" -- "${zeros}" "${c14}"

check "no arguments is a usage error" 2 "usage: check-version-bump.sh" --
check "an empty base is a usage error" 2 "usage: check-version-bump.sh" -- "" "${c1}"
check "an empty head is a usage error" 2 "usage: check-version-bump.sh" -- "${c1}" ""
check "one argument is a usage error" 2 "usage: check-version-bump.sh" -- "${c1}"
check "three arguments are a usage error" 2 "usage: check-version-bump.sh" -- "${c1}" "${c2}" "${c3}"
check "an unknown commit is an error" 128 "1111111111111111111111111111111111111111" -- "1111111111111111111111111111111111111111" "${c3}"

echo "${passed} checks passed"
