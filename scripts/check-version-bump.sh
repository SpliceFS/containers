#!/bin/sh
# Fails, naming the image, when an image that a change touched does not also have a greater
# version than it had before the change. A published version never changes, so a change to
# an image is only allowed to go out as a new, greater version. A pull request runs this
# with the fork point as BASE and its last commit as HEAD.
#
#   check-version-bump.sh BASE HEAD
#
# The images are those that changed-images.sh lists. Only the version at BASE and the
# version at HEAD are compared, whatever happened between them. An image with no version
# at BASE is new, or is getting its first version, and needs only a valid one.
set -eu

usage() {
    echo "usage: check-version-bump.sh BASE HEAD" >&2
    exit 2
}

if [ "$#" -ne 2 ] || [ -z "$1" ] || [ -z "$2" ]; then
    usage
fi
base="$1"
head="$2"

# The other scripts are found from this script's own place, so the script works from any
# folder and can be tested against a throwaway copy of the layout.
case "$0" in
*/*) here="${0%/*}" ;;
*) here="." ;;
esac

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
trap 'exit 1' HUP INT TERM

# Run on its own line, so that its failure stops this script.
sh "${here}/changed-images.sh" "${base}" "${head}" >"${work}/images"

failed=0
while IFS= read -r name; do
    # Status 3 says there was no version file. Any other failure is a version that cannot
    # be read, and image-version.sh has said why.
    old_status=0
    old="$(sh "${here}/image-version.sh" "${name}" "${base}" 2>"${work}/error")" || old_status=$?
    case "${old_status}" in
    0 | 3) ;;
    *)
        cat "${work}/error" >&2
        failed=1
        continue
        ;;
    esac

    new_status=0
    new="$(sh "${here}/image-version.sh" "${name}" "${head}" 2>"${work}/error")" || new_status=$?
    case "${new_status}" in
    0) ;;
    3)
        echo "check-version-bump.sh: images/${name} changed and has no version: add images/${name}/version" >&2
        failed=1
        continue
        ;;
    *)
        cat "${work}/error" >&2
        failed=1
        continue
        ;;
    esac

    if [ "${old_status}" -eq 3 ]; then
        echo "images/${name}: ${new} (new)"
    elif [ "${new#v}" -gt "${old#v}" ]; then
        echo "images/${name}: ${old} -> ${new}"
    else
        echo "check-version-bump.sh: images/${name} changed, but its version ${new} is not greater than ${old} before the change: raise images/${name}/version" >&2
        failed=1
    fi
done <"${work}/images"

if [ "${failed}" -ne 0 ]; then
    exit 1
fi
