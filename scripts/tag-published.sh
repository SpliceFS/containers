#!/bin/sh
# Tells whether a tag exists in a registry, by asking for its manifest. The build workflow
# asks before it publishes a version, because a published version never changes, and the
# pull request check asks whether the version another image is built on exists.
#
#   tag-published.sh REFERENCE      for example ghcr.io/splicefs/go-qemu:v1
#
# Exit status: 0 when the tag exists, 1 when it does not, 2 for wrong arguments, 3 when the
# registry could not be asked. Only an answer that says the tag does not exist counts as
# 1: an error of the network or of the program says nothing about the tag, and taking it
# for "not published" would let a published version be replaced.
set -eu

if [ "$#" -ne 1 ] || [ -z "$1" ]; then
    echo "usage: tag-published.sh REFERENCE" >&2
    exit 2
fi
reference="$1"

# The manifest itself is not wanted, only whether it came. The error output is kept to
# be read.
status=0
message="$(docker manifest inspect "${reference}" 2>&1 >/dev/null)" || status=$?
if [ "${status}" -eq 0 ]; then
    exit 0
fi

# Docker exits with 1 for what the registry said. Another status is the shell or docker
# failing, and its text may hold "not found" for a program that is missing.
if [ "${status}" -eq 1 ]; then
    # The words differ between registries and versions of docker. A package that does not
    # exist yet answers "denied", like one that may not be read.
    case "${message}" in
    *"manifest unknown"* | *"no such manifest"* | *"not found"* | *"name unknown"* | *denied*)
        exit 1
        ;;
    *) ;;
    esac
fi
echo "tag-published.sh: could not ask the registry about ${reference}: ${message}" >&2
exit 3
