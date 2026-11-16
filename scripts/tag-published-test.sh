#!/bin/sh
# Tests tag-published.sh with a stand-in for the docker program, so that no registry is
# asked. Run from anywhere:
#   sh scripts/tag-published-test.sh
set -eu

case "$0" in
*/*) here="${0%/*}" ;;
*) here="." ;;
esac
script_dir="$(cd "${here}" && pwd)"
script="${script_dir}/tag-published.sh"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
trap 'exit 1' HUP INT TERM

# The stand-in records its arguments, then answers as the files in ${work}/answer say.
mkdir -p "${work}/bin" "${work}/answer"
cat >"${work}/bin/docker" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >>"${STUB_ANSWER}/calls"
cat "${STUB_ANSWER}/stdout"
cat "${STUB_ANSWER}/stderr" >&2
exit "$(cat "${STUB_ANSWER}/status")"
STUB
chmod +x "${work}/bin/docker"
STUB_ANSWER="${work}/answer"
export STUB_ANSWER
PATH="${work}/bin:${PATH}"
export PATH

passed=0

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

# answer STATUS STDOUT STDERR sets what the registry says.
answer() {
    printf '%s\n' "$1" >"${work}/answer/status"
    printf '%s' "$2" >"${work}/answer/stdout"
    printf '%s' "$3" >"${work}/answer/stderr"
    : >"${work}/answer/calls"
}

# check DESCRIPTION EXPECTED_STATUS EXPECTED_ERROR_TEXT ARGS...
# An empty error text means the script must print nothing at all.
check() {
    description="$1"
    want_status="$2"
    want_text="$3"
    shift 3
    status=0
    sh "${script}" "$@" >"${work}/stdout" 2>"${work}/stderr" || status=$?
    errors="$(cat "${work}/stderr")"
    if [ "${status}" != "${want_status}" ]; then
        fail "${description}: exit status ${status}, wanted ${want_status} (${errors})"
    fi
    if [ -s "${work}/stdout" ]; then
        fail "${description}: printed to the standard output"
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

ref="ghcr.io/example/tool:v1"

answer 0 '{"schemaVersion": 2}' ""
check "a tag the registry knows is published" 0 "" "${ref}"
calls="$(cat "${work}/answer/calls")"
if [ "${calls}" != "manifest inspect ${ref}" ]; then
    fail "the registry was asked \"${calls}\", wanted \"manifest inspect ${ref}\""
fi
passed=$((passed + 1))
echo "ok - the registry is asked with docker manifest inspect and the reference"

# What the registry says when a tag does not exist differs between registries and
# versions of docker. Each of these means "not published".
answer 1 "" "manifest unknown"
check "manifest unknown is not published" 1 "" "${ref}"

answer 1 "" "no such manifest: ${ref}"
check "no such manifest is not published" 1 "" "${ref}"

answer 1 "" "${ref}: not found"
check "not found is not published" 1 "" "${ref}"

answer 1 "" "name unknown: repository name not known to registry"
check "name unknown is not published" 1 "" "${ref}"

# A package that does not exist yet answers as one that may not be read.
answer 1 "" "Get \"https://ghcr.io/v2/example/tool/manifests/v1\": denied"
check "denied is not published" 1 "" "${ref}"

# Anything else says nothing about the tag. Treating it as not published would let a
# published version be replaced, so the script stops instead.
answer 1 "" "dial tcp: lookup ghcr.io: no such host"
check "a network error cannot be told" 3 "could not ask the registry about ${ref}: dial tcp: lookup ghcr.io: no such host" "${ref}"

answer 1 "" "toomanyrequests: rate limit exceeded"
check "a rate limit cannot be told" 3 "toomanyrequests" "${ref}"

# The shell says "not found" too, when there is no docker program at all.
answer 127 "" "sh: docker: command not found"
check "a missing docker program cannot be told" 3 "command not found" "${ref}"

answer 1 "" ""
check "a failure with no message cannot be told" 3 "could not ask the registry" "${ref}"

answer 0 "" ""
check "no argument is a usage error" 2 "usage: tag-published.sh"
check "two arguments are a usage error" 2 "usage: tag-published.sh" "${ref}" "${ref}"
check "an empty reference is a usage error" 2 "usage: tag-published.sh" ""

echo "${passed} checks passed"
