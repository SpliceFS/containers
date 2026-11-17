#!/bin/sh
# Prints the tags that publishing a version moves: its minor tag (v1.2 for v1.2.3), then its
# major tag (v1). The build workflow points them at the image it publishes, and
# check-base-versions.sh accepts them as satisfied by a version that the same change
# publishes, so what a version moves has one place.
#
#   moving-tags.sh VERSION
#
# Exit status: 0 for the tags, 1 when VERSION is not a version, 2 for wrong arguments.
set -eu

if [ "$#" -ne 1 ]; then
    echo "usage: moving-tags.sh VERSION" >&2
    exit 2
fi
version="$1"

# The other scripts are found from this script's own place.
case "$0" in
*/*) here="${0%/*}" ;;
*) here="." ;;
esac

if ! sh "${here}/version-valid.sh" "${version}"; then
    echo "moving-tags.sh: \"${version}\" is not a version: use vMAJOR.MINOR.PATCH, as in v1.0.0" >&2
    exit 1
fi

# Cut off the patch, then the minor.
minor="${version%.*}"
echo "${minor}"
echo "${minor%.*}"
