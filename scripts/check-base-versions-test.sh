#!/bin/sh
# Tests check-base-versions.sh in a throwaway git repository that holds a copy of the
# scripts, with a stand-in for the docker program so that no registry is asked. Run from
# anywhere:
#   sh scripts/check-base-versions-test.sh
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
for name in check-base-versions changed-images image-version version-valid moving-tags tag-published; do
    cp "${script_dir}/${name}.sh" "${repo}/scripts/${name}.sh"
done
script="${repo}/scripts/check-base-versions.sh"

# The stand-in registry knows the references in the file "published", one per line, and
# fails like a broken network while the file "broken" exists. It records every question.
mkdir -p "${work}/bin" "${work}/registry"
cat >"${work}/bin/docker" <<'STUB'
#!/bin/sh
printf '%s\n' "$3" >>"${STUB_REGISTRY}/asked"
if [ -e "${STUB_REGISTRY}/broken" ]; then
    echo "dial tcp: lookup ghcr.io: no such host" >&2
    exit 1
fi
if grep -Fxq -- "$3" "${STUB_REGISTRY}/published"; then
    exit 0
fi
echo "manifest unknown" >&2
exit 1
STUB
chmod +x "${work}/bin/docker"
STUB_REGISTRY="${work}/registry"
export STUB_REGISTRY
PATH="${work}/bin:${PATH}"
export PATH

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

# published REFERENCE... sets what the registry knows, and clears what it was asked.
published() {
    : >"${work}/registry/published"
    for reference in "$@"; do
        echo "${reference}" >>"${work}/registry/published"
    done
    rm -f "${work}/registry/asked" "${work}/registry/broken"
}

# asked_nothing fails the test when the registry was asked anything since published.
asked_nothing() {
    if [ -s "${work}/registry/asked" ]; then
        questions="$(cat "${work}/registry/asked")"
        fail "$1: the registry was asked about ${questions}"
    fi
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

# The base image "base" is at v1.0.0 and published. "app" is built on it. "other" is built on
# nothing of ours.
put images/base/Dockerfile "FROM golang:1.27"
put images/base/version "v1.0.0"
put images/app/Dockerfile "FROM ghcr.io/splicefs/base:v1.0.0"
put images/app/version "v1.0.0"
put images/other/Dockerfile "FROM golang:1.27"
put images/other/version "v1.0.0"
commit "start"
c0="${rev}"

published "ghcr.io/splicefs/base:v1.0.0"

put images/other/README.md "about other"
commit "change other"
c1="${rev}"
check "an image built on nothing of ours passes" 0 -- "${c0}" "${c1}"
asked_nothing "an image built on nothing of ours"

put images/app/README.md "about app"
commit "change app"
c2="${rev}"
check "an image built on a published version passes" 0 "images/app: ghcr.io/splicefs/base:v1.0.0" -- "${c1}" "${c2}"

published
check "an image built on a version that is not published fails" 1 \
    "images/app/Dockerfile: ghcr.io/splicefs/base:v1.0.0 is not published" -- "${c1}" "${c2}"

published "ghcr.io/splicefs/base:v1.0.0"
put images/app/Dockerfile "FROM ghcr.io/splicefs/base:v9.0.0"
commit "app on a version that does not exist"
c3="${rev}"
check "a version that nobody publishes fails" 1 \
    "images/app/Dockerfile: ghcr.io/splicefs/base:v9.0.0 is not published" -- "${c2}" "${c3}"

# The same change publishes the base version: the registry does not have it yet.
put images/base/README.md "about base"
put images/base/version "v2.0.0"
put images/app/Dockerfile "FROM ghcr.io/splicefs/base:v2.0.0"
commit "base v2.0.0 and app on it"
c4="${rev}"
published "ghcr.io/splicefs/base:v1.0.0"
check "a version that this change publishes passes without the registry" 0 \
    "images/app: ghcr.io/splicefs/base:v2.0.0" -- "${c2}" "${c4}"
asked_nothing "a version that this change publishes"

put images/app/Dockerfile "FROM ghcr.io/splicefs/base:v3.0.0"
commit "app on a version that nobody publishes"
c5="${rev}"
check "a version that is neither published nor published by this change fails" 1 \
    "images/app/Dockerfile: ghcr.io/splicefs/base:v3.0.0 is not published" -- "${c2}" "${c5}"

# The tags that move are satisfied by the version that this change publishes: v2 and v2.0
# by v2.0.0. The registry does not hold them yet. The version of the base is v2.0.0 here.
published "ghcr.io/splicefs/base:v1.0.0"
put images/app/Dockerfile "FROM ghcr.io/splicefs/base:v2"
commit "app on the major tag of the version this change publishes"
check "the major tag of a version that this change publishes passes without the registry" 0 \
    "images/app: ghcr.io/splicefs/base:v2" -- "${c2}" "${rev}"
asked_nothing "the major tag of a version that this change publishes"

put images/app/Dockerfile "FROM ghcr.io/splicefs/base:v2.0"
commit "app on the minor tag of the version this change publishes"
published "ghcr.io/splicefs/base:v1.0.0"
check "the minor tag of a version that this change publishes passes without the registry" 0 \
    "images/app: ghcr.io/splicefs/base:v2.0" -- "${c2}" "${rev}"
asked_nothing "the minor tag of a version that this change publishes"

put images/app/Dockerfile "FROM ghcr.io/splicefs/base:v2.1"
commit "app on a minor tag that this change does not publish"
check "a minor tag of the same major that this change does not publish fails" 1 \
    "images/app/Dockerfile: ghcr.io/splicefs/base:v2.1 is not published" -- "${c2}" "${rev}"

put images/app/Dockerfile "FROM ghcr.io/splicefs/base:v3"
commit "app on a major tag that this change does not publish"
check "a major tag that this change does not publish fails" 1 \
    "images/app/Dockerfile: ghcr.io/splicefs/base:v3 is not published" -- "${c2}" "${rev}"

# A tag of another line is for the registry to say, though the base is in the change.
put images/app/Dockerfile "FROM ghcr.io/splicefs/base:v1"
commit "app on the major tag of an older line"
published "ghcr.io/splicefs/base:v1"
check "the major tag of an older line passes when the registry holds it" 0 \
    "images/app: ghcr.io/splicefs/base:v1" -- "${c2}" "${rev}"
published
check "the major tag of an older line fails when the registry does not hold it" 1 \
    "images/app/Dockerfile: ghcr.io/splicefs/base:v1 is not published" -- "${c2}" "${rev}"

put images/app/Dockerfile "FROM ghcr.io/splicefs/base:v1.0"
commit "app on the minor tag of an older line"
published "ghcr.io/splicefs/base:v1.0"
check "the minor tag of an older line passes when the registry holds it" 0 \
    "images/app: ghcr.io/splicefs/base:v1.0" -- "${c2}" "${rev}"

put images/app/Dockerfile "FROM ghcr.io/splicefs/base:v1.0.0"
commit "app stays on v1.0.0"
c6="${rev}"
published "ghcr.io/splicefs/base:v1.0.0"
check "an older published version passes while the base is changed" 0 \
    "images/app: ghcr.io/splicefs/base:v1.0.0" -- "${c1}" "${c6}"

# Whether a tag is published is for the registry to say, also for a base that this change
# does not touch.
put images/app/README.md "about app 2"
commit "change app again"
c7="${rev}"
published
check "an unchanged base is not trusted without the registry" 1 \
    "images/app/Dockerfile: ghcr.io/splicefs/base:v1.0.0 is not published" -- "${c6}" "${c7}"

for ref in "ghcr.io/splicefs/base:latest" "ghcr.io/splicefs/base" "ghcr.io/splicefs/base:v01.0.0" \
    "ghcr.io/splicefs/base:v1.02" "ghcr.io/splicefs/base:v1.0.0.0" "ghcr.io/splicefs/base:v1." \
    "ghcr.io/splicefs/base:1.0.0" "ghcr.io/splicefs/base:2026-11-14-1a2b3c4" \
    "ghcr.io/splicefs/base@sha256:0123456789abcdef" "ghcr.io/splicefs/base:\${VERSION}"; do
    published "ghcr.io/splicefs/base:latest" "ghcr.io/splicefs/base:v01.0.0" "ghcr.io/splicefs/base"
    put images/app/Dockerfile "FROM ${ref}"
    commit "app on ${ref}"
    check "a reference that is not a version fails: ${ref}" 1 \
        "images/app/Dockerfile: ${ref} does not name a version" "use vX, vX.Y or vX.Y.Z, as in ghcr.io/splicefs/base:v1.0.0" -- "${c7}" "${rev}"
    asked_nothing "a reference that is not a version"
done

put images/app/Dockerfile "FROM --platform=linux/amd64 ghcr.io/splicefs/base:v1.0.0 AS build
FROM golang:1.27"
commit "app with a platform and a second stage"
c8="${rev}"
published "ghcr.io/splicefs/base:v1.0.0"
check "a platform flag and an alias are skipped" 0 "images/app: ghcr.io/splicefs/base:v1.0.0" -- "${c7}" "${c8}"

put images/app/Dockerfile "from ghcr.io/splicefs/base:v1.0.0"
commit "app with a lower case from"
c9="${rev}"
check "a lower case from is read" 0 "images/app: ghcr.io/splicefs/base:v1.0.0" -- "${c7}" "${c9}"

put images/app/Dockerfile "# FROM ghcr.io/splicefs/base:latest
FROM ghcr.io/splicefs/base:v1.0.0
RUN echo ghcr.io/splicefs/base:latest"
commit "app with the reference elsewhere"
c10="${rev}"
check "a reference in a comment or another instruction is not a base" 0 "images/app: ghcr.io/splicefs/base:v1.0.0" -- "${c7}" "${c10}"

put images/app/Dockerfile "FROM ghcr.io/splicefs/base:v1.0.0 AS first
FROM ghcr.io/splicefs/base:latest AS second"
commit "app with two stages"
c11="${rev}"
check "every stage is checked and the bad one is named" 1 \
    "images/app/Dockerfile: ghcr.io/splicefs/base:latest does not name a version" -- "${c7}" "${c11}"

put images/app/Dockerfile "FROM ghcr.io/other/base:latest"
commit "app on an image of another owner"
c12="${rev}"
check "an image of another owner is not ours to check" 0 -- "${c7}" "${c12}"

# Only images of the change are checked: an old Dockerfile is not this change's to fix.
put images/app/Dockerfile "FROM ghcr.io/splicefs/base:latest"
commit "app on latest"
c13="${rev}"
put images/other/README.md "about other 2"
commit "change other"
c14="${rev}"
check "an image that this change does not touch is not checked" 0 -- "${c13}" "${c14}"

# Not knowing is not the same as not published.
published "ghcr.io/splicefs/base:v1.0.0"
: >"${work}/registry/broken"
put images/app/Dockerfile "FROM ghcr.io/splicefs/base:v1.0.0"
commit "app on v1.0.0"
c15="${rev}"
check "a registry that cannot be asked stops the check" 3 \
    "could not ask the registry about ghcr.io/splicefs/base:v1.0.0" -- "${c14}" "${c15}"

published
check "an all-zero base checks every image" 1 \
    "images/app/Dockerfile: ghcr.io/splicefs/base:v1.0.0 is not published" -- "0000000000000000000000000000000000000000" "${c15}"

check "no arguments is a usage error" 2 "usage: check-base-versions.sh" --
check "one argument is a usage error" 2 "usage: check-base-versions.sh" -- "${c1}"
check "an empty base is a usage error" 2 "usage: check-base-versions.sh" -- "" "${c1}"
check "three arguments are a usage error" 2 "usage: check-base-versions.sh" -- "${c1}" "${c2}" "${c3}"

echo "${passed} checks passed"
