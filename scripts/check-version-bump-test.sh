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
for name in check-version-bump changed-images image-version version-valid version-compare legacy-version; do
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
put images/alpha/version "v1.0.0"
put images/beta/Dockerfile "FROM scratch"
put images/beta/version "v4.0.0"
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
    "images/alpha changed, but its version v1.0.0 is not greater than v1.0.0" \
    "raise images/alpha/version" -- "${c1}" "${c2}"

put images/alpha/version "v2.0.0"
commit "raise alpha"
c3="${rev}"
check "a changed image with a greater version passes" 0 "images/alpha: v1.0.0 -> v2.0.0" -- "${c1}" "${c3}"

put images/alpha/Dockerfile "FROM scratch 3"
put images/alpha/version "v5.0.0"
commit "change alpha, skip versions"
c4="${rev}"
check "a range of several commits compares only the versions at its two ends" 0 \
    "images/alpha: v1.0.0 -> v5.0.0" -- "${c1}" "${c4}"
check "a version that skips numbers passes" 0 "images/alpha: v2.0.0 -> v5.0.0" -- "${c3}" "${c4}"

put images/alpha/Dockerfile "FROM scratch 4"
put images/alpha/version "v3.0.0"
commit "change alpha, lower the version"
c5="${rev}"
check "a lower version fails" 1 "images/alpha changed, but its version v3.0.0 is not greater than v5.0.0" -- "${c4}" "${c5}"

put images/alpha/version "v10.0.0"
commit "alpha to v10.0.0"
c6="${rev}"
check "the versions are compared as numbers, v10.0.0 is greater than v5.0.0" 0 "images/alpha: v5.0.0 -> v10.0.0" -- "${c4}" "${c6}"

put images/alpha/version "v11.0.0"
commit "only the version of alpha"
c7="${rev}"
check "a change of only the version file passes" 0 "images/alpha: v10.0.0 -> v11.0.0" -- "${c6}" "${c7}"

put images/alpha/README.md "about alpha"
put images/beta/README.md "about beta"
put images/beta/version "v5.0.0"
commit "change alpha and beta, raise only beta"
c8="${rev}"
check "an image that is not raised fails and a raised one passes" 1 \
    "images/alpha changed, but its version v11.0.0 is not greater than v11.0.0" \
    "images/beta: v4.0.0 -> v5.0.0" -- "${c7}" "${c8}"

put images/alpha/README.md "about alpha 2"
put images/beta/README.md "about beta 2"
commit "change alpha and beta, raise none"
c9="${rev}"
check "every image that is not raised is named" 1 \
    "images/alpha changed, but its version v11.0.0 is not greater than v11.0.0" \
    "images/beta changed, but its version v5.0.0 is not greater than v5.0.0" -- "${c8}" "${c9}"

put images/alpha/version "v12.0.0"
commit "raise alpha"
c10="${rev}"
check "a range of several commits compares the versions at its two ends" 0 \
    "images/alpha: v11.0.0 -> v12.0.0" "images/beta: v4.0.0 -> v5.0.0" -- "${c7}" "${c10}"

put images/gamma/Dockerfile "FROM scratch"
put images/gamma/version "v1.0.0"
commit "add gamma"
c11="${rev}"
check "a new image with a version passes" 0 "images/gamma: v1.0.0 (new)" -- "${c10}" "${c11}"

put images/delta/Dockerfile "FROM scratch"
commit "add delta without a version"
c12="${rev}"
check "a new image without a version file fails" 1 "images/delta changed and has no version" "images/delta/version" -- "${c11}" "${c12}"

put images/delta/version "v01.0.0"
commit "delta with a malformed version"
c13="${rev}"
check "a new image with a malformed version fails" 1 "images/delta/version" "is not a version" -- "${c12}" "${c13}"

put images/delta/version "v1.0.0"
commit "delta with a version"
c14="${rev}"
check "an image that gets its first version passes, as when the rule begins" 0 "images/delta: v1.0.0 (new)" -- "${c12}" "${c14}"

# A malformed version on the base cannot be compared with.
put images/epsilon/Dockerfile "FROM scratch"
put images/epsilon/version "latest"
commit "epsilon with a malformed version"
c15="${rev}"
put images/epsilon/Dockerfile "FROM scratch 2"
put images/epsilon/version "v2.0.0"
commit "epsilon repaired"
c16="${rev}"
check "a malformed version on the base fails" 1 "is not a version" "images/epsilon" -- "${c15}" "${c16}"

git -C "${repo}" rm -q -r images/beta
commit "remove beta"
c17="${rev}"
check "a removed image needs no version" 0 -- "${c16}" "${c17}"

# The three places of a version are compared in order, each as a number.
put images/zeta/Dockerfile "FROM scratch"
put images/zeta/version "v1.9.9"
commit "add zeta"
z0="${rev}"

# bump VERSION changes zeta and sets its version.
bump() {
    put images/zeta/Dockerfile "FROM scratch ${1}"
    put images/zeta/version "${1}"
    commit "zeta ${1}"
}

bump v1.10.0
check "a minor of two digits is greater than one of one digit" 0 "images/zeta: v1.9.9 -> v1.10.0" -- "${z0}" "${rev}"
z1="${rev}"
bump v1.10.1
check "a greater patch passes" 0 "images/zeta: v1.10.0 -> v1.10.1" -- "${z1}" "${rev}"
z2="${rev}"
bump v1.10.10
check "a patch of two digits is greater than one of one digit" 0 "images/zeta: v1.10.1 -> v1.10.10" -- "${z2}" "${rev}"
z3="${rev}"
bump v1.11.0
check "a greater minor passes, whatever the patch was" 0 "images/zeta: v1.10.10 -> v1.11.0" -- "${z3}" "${rev}"
z4="${rev}"
bump v2.0.0
check "a greater major passes, whatever the minor and patch were" 0 "images/zeta: v1.11.0 -> v2.0.0" -- "${z4}" "${rev}"
bump v2.3.4
z5="${rev}"
bump v2.3.3
check "a lower patch fails" 1 "images/zeta changed, but its version v2.3.3 is not greater than v2.3.4" -- "${z5}" "${rev}"
bump v2.2.9
check "a lower minor fails, whatever the patch is" 1 \
    "images/zeta changed, but its version v2.2.9 is not greater than v2.3.4" -- "${z5}" "${rev}"
bump v1.99.99
check "a lower major fails, whatever the minor and patch are" 1 \
    "images/zeta changed, but its version v1.99.99 is not greater than v2.3.4" -- "${z5}" "${rev}"

# The one-time move from the old versions (v1, v2) to MAJOR.MINOR.PATCH. A base that holds
# the old form counts as the same number with .0.0, so v1 is v1.0.0. The same release is
# allowed in the new form only when nothing but the version file changed.
put images/theta/Dockerfile "FROM scratch"
put images/theta/version "v1"
put images/iota/Dockerfile "FROM scratch"
put images/iota/version "v2"
put images/kappa/Dockerfile "FROM scratch"
put images/kappa/version "v3"
commit "add theta, iota and kappa with the old versions"
t0="${rev}"

put images/theta/version "v1.0.0"
commit "theta: only the version file, to the new form"
check "the new form of the same release passes when only the version file changed" 0 \
    "images/theta: v1.0.0 (v1 in the old form) -> v1.0.0" -- "${t0}" "${rev}"

put images/theta/version "v1.0.1"
commit "theta: only the version file, a patch above"
check "a greater version passes when only the version file changed" 0 \
    "images/theta: v1.0.0 (v1 in the old form) -> v1.0.1" -- "${t0}" "${rev}"

put images/theta/version "v0.9.9"
commit "theta: only the version file, below the old version"
check "a version below the old one fails, though only the version file changed" 1 \
    "images/theta changed, but its version v0.9.9 is not greater than v1.0.0 (v1 in the old form)" -- "${t0}" "${rev}"

put images/theta/version "v1.0.0"
put images/theta/README.md "about theta"
commit "theta: the new form of the same release, with another file"
check "the new form of the same release fails when another file changed" 1 \
    "images/theta changed, but its version v1.0.0 is not greater than v1.0.0 (v1 in the old form)" \
    "raise images/theta/version" -- "${t0}" "${rev}"

put images/theta/version "v1.1.0"
commit "theta: a greater version, with another file"
t1="${rev}"
check "a greater version passes when another file changed" 0 "images/theta: v1.0.0 (v1 in the old form) -> v1.1.0" -- "${t0}" "${t1}"

# Only the files between the two ends of the range count, not the commits that make it.
put images/kappa/Dockerfile "FROM scratch 2"
commit "kappa: another file, the version still old"
t2="${rev}"
put images/kappa/version "v3.0.0"
commit "kappa: then only the version file"
t3="${rev}"
check "another file changed earlier in the range counts as a change of the image" 1 \
    "images/kappa changed, but its version v3.0.0 is not greater than v3.0.0 (v3 in the old form)" \
    "images/theta: v1.0.0 (v1 in the old form) -> v1.1.0" -- "${t0}" "${t3}"
check "the last commit alone holds only the version file, and its base has the old form" 0 \
    "images/kappa: v3.0.0 (v3 in the old form) -> v3.0.0" -- "${t2}" "${t3}"

put images/iota/version "v2.0.0"
commit "iota: only the version file, to the new form"
check "every image of the old form is moved the same way" 0 "images/iota: v2.0.0 (v2 in the old form) -> v2.0.0" -- "${t3}" "${rev}"

# Only a number of the old form is moved. Anything else on the base is malformed.
put images/lambda/Dockerfile "FROM scratch"
put images/lambda/version "v01"
put images/mu/Dockerfile "FROM scratch"
put images/mu/version "v1"
put images/nu/Dockerfile "FROM scratch"
put images/nu/extra.sh "echo extra"
put images/nu/version "v5"
commit "add lambda, mu and nu"
n0="${rev}"

put images/lambda/version "v1.0.0"
commit "lambda: a malformed version repaired"
check "a malformed old version on the base is not the old form" 1 "is not a version" "images/lambda" -- "${n0}" "${rev}"

put images/mu/version "v1"
put images/mu/README.md "about mu"
commit "mu: another file, the version still old"
check "the old form at the head is not a version" 1 "is not a version" "images/mu" -- "${n0}" "${rev}"

git -C "${repo}" rm -q images/nu/extra.sh
put images/nu/version "v5.0.0"
commit "nu: a file removed, the new form"
check "a removed file counts as a change of the image" 1 \
    "images/nu changed, but its version v5.0.0 is not greater than v5.0.0 (v5 in the old form)" -- "${n0}" "${rev}"

zeros="0000000000000000000000000000000000000000"
check "an all-zero base means every image is new" 0 \
    "images/alpha: v12.0.0 (new)" "images/delta: v1.0.0 (new)" -- "${zeros}" "${c14}"

check "no arguments is a usage error" 2 "usage: check-version-bump.sh" --
check "an empty base is a usage error" 2 "usage: check-version-bump.sh" -- "" "${c1}"
check "an empty head is a usage error" 2 "usage: check-version-bump.sh" -- "${c1}" ""
check "one argument is a usage error" 2 "usage: check-version-bump.sh" -- "${c1}"
check "three arguments are a usage error" 2 "usage: check-version-bump.sh" -- "${c1}" "${c2}" "${c3}"
check "an unknown commit is an error" 128 "1111111111111111111111111111111111111111" -- "1111111111111111111111111111111111111111" "${c3}"

echo "${passed} checks passed"
