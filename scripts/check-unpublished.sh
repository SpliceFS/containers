#!/bin/sh
# Fails when the version of an image is already in the registry. A published version never
# changes, so the build workflow runs this before it publishes an image, and publishes
# nothing for an image that fails it.
#
#   check-unpublished.sh NAME
#
# Exit status: 0 when the version is not published yet, 1 when it is, 2 for wrong
# arguments. A version that cannot be read, or a registry that cannot be asked, stops the
# script with the status of the script that failed (3 for either one), because neither
# says the version is free.
set -eu

if [ "$#" -ne 1 ]; then
    echo "usage: check-unpublished.sh NAME" >&2
    exit 2
fi
name="$1"

# The other scripts are found from this script's own place.
case "$0" in
*/*) here="${0%/*}" ;;
*) here="." ;;
esac

# Run on its own line, so that its failure stops this script.
version="$(sh "${here}/image-version.sh" "${name}")"

status=0
sh "${here}/tag-published.sh" "ghcr.io/splicefs/${name}:${version}" || status=$?
case "${status}" in
0)
    echo "check-unpublished.sh: ${name}:${version} is already published; a change needs a new version" >&2
    exit 1
    ;;
1) ;;
*)
    exit "${status}"
    ;;
esac
