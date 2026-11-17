#!/bin/sh
# Tests check-unpublished.sh against a throwaway copy of the repository layout, with a
# stand-in for the docker program so that no registry is asked. Run from anywhere:
#   sh scripts/check-unpublished-test.sh
set -eu

case "$0" in
*/*) here="${0%/*}" ;;
*) here="." ;;
esac
script_dir="$(cd "${here}" && pwd)"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
trap 'exit 1' HUP INT TERM

# The scripts find each other, and the images folder, from their own place.
mkdir -p "${work}/scripts" "${work}/images"
for name in check-unpublished image-version version-valid tag-published; do
    cp "${script_dir}/${name}.sh" "${work}/scripts/${name}.sh"
done
script="${work}/scripts/check-unpublished.sh"

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

# check DESCRIPTION EXPECTED_STATUS EXPECTED_TEXT ARGS...
# The text must be in what the script printed, standard and error output together. An
# empty text means the script must print nothing.
check() {
    description="$1"
    want_status="$2"
    want_text="$3"
    shift 3
    status=0
    sh "${script}" "$@" >"${work}/output" 2>&1 || status=$?
    output="$(cat "${work}/output")"
    if [ "${status}" != "${want_status}" ]; then
        fail "${description}: exit status ${status}, wanted ${want_status} (${output})"
    fi
    if [ -z "${want_text}" ]; then
        if [ -n "${output}" ]; then
            fail "${description}: printed \"${output}\""
        fi
    elif ! grep -Fq -- "${want_text}" "${work}/output"; then
        fail "${description}: the output lacks \"${want_text}\" (${output})"
    fi
    passed=$((passed + 1))
    echo "ok - ${description}"
}

mkdir -p "${work}/images/alpha"
printf 'v3.1.4\n' >"${work}/images/alpha/version"

published
check "a version that is not in the registry passes" 0 "" alpha
asked="$(cat "${work}/registry/asked")"
if [ "${asked}" != "ghcr.io/splicefs/alpha:v3.1.4" ]; then
    fail "the registry was asked about \"${asked}\", wanted ghcr.io/splicefs/alpha:v3.1.4"
fi
passed=$((passed + 1))
echo "ok - the registry is asked about the image under its version"

published "ghcr.io/splicefs/alpha:v1.0.0" "ghcr.io/splicefs/alpha:v3.1.3" "ghcr.io/splicefs/alpha:v3.2.4" "ghcr.io/splicefs/beta:v3.1.4" "ghcr.io/splicefs/alpha:latest"
check "other versions and other images in the registry do not matter" 0 "" alpha

# The tags that move are not the version: they exist from the first publish of a line on.
published "ghcr.io/splicefs/alpha:v3.1" "ghcr.io/splicefs/alpha:v3"
check "the moving tags of the version do not count as published" 0 "" alpha

published "ghcr.io/splicefs/alpha:v3.1.4"
check "a version that is in the registry fails and says why" 1 "alpha:v3.1.4 is already published; a change needs a new version" alpha

published
: >"${work}/registry/broken"
check "a registry that cannot be asked stops the publish" 3 "could not ask the registry about ghcr.io/splicefs/alpha:v3.1.4" alpha

published
check "an image without a version file stops the publish" 3 "images/beta/version" beta
if [ -s "${work}/registry/asked" ]; then
    fail "the registry was asked although the image has no version"
fi
passed=$((passed + 1))
echo "ok - the registry is not asked for an image that has no version"

printf 'latest\n' >"${work}/images/alpha/version"
check "a malformed version stops the publish" 1 "is not a version" alpha

check "no argument is a usage error" 2 "usage: check-unpublished.sh"
check "two arguments are a usage error" 2 "usage: check-unpublished.sh" alpha beta

echo "${passed} checks passed"
