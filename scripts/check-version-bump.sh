#!/bin/sh
# Fails, naming the image, when an image that a change touched does not also have a greater
# version than it had before the change. A published version never changes, so a change to
# an image is only allowed to go out as a new, greater version. A pull request runs this
# with the fork point as BASE and its last commit as HEAD.
#
#   check-version-bump.sh BASE HEAD
#
# The images are those that changed-images.sh lists. Only the version at BASE and the
# version at HEAD are compared, as numbers by major, minor and patch (version-compare.sh),
# whatever happened between them. An image with no version at BASE is new, or is getting
# its first version, and needs only a valid one.
#
# One exception, for the move from the old versions (v1, v2) to MAJOR.MINOR.PATCH: a base
# that holds the old form counts as the same number with .0.0, so v1 is v1.0.0
# (legacy-version.sh). The new form of the same release, v1.0.0, passes when nothing but
# the version file of the image changed, which gives the image the new form without a
# change of its content. Every other change needs a version greater than that.
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

# The other scripts, and the repository, are found from this script's own place, so the
# script works from any folder and can be tested against a throwaway copy of the layout.
case "$0" in
*/*) here="${0%/*}" ;;
*) here="." ;;
esac
root="$(cd "${here}/.." && pwd)"

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

    # The old form of a version is malformed to image-version.sh, and counts as the same
    # number with .0.0. Its new form is allowed once, when only the version file changed.
    old_note=""
    same_allowed=0
    if [ "${old_status}" -eq 1 ]; then
        legacy_status=0
        legacy="$(sh "${here}/legacy-version.sh" "${name}" "${base}" 2>/dev/null)" || legacy_status=$?
        if [ "${legacy_status}" -eq 0 ]; then
            old="${legacy}"
            old_status=0
            old_note=" (${old%.0.0} in the old form)"
            files="$(git -C "${root}" diff --name-only "${base}" "${head}" -- "images/${name}")"
            if [ "${files}" = "images/${name}/version" ]; then
                same_allowed=1
            fi
        fi
    fi
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
        continue
    fi
    # Run on its own line, so that its failure stops this script.
    order="$(sh "${here}/version-compare.sh" "${new}" "${old}")"
    if [ "${order}" = greater ] || { [ "${order}" = equal ] && [ "${same_allowed}" -eq 1 ]; }; then
        echo "images/${name}: ${old}${old_note} -> ${new}"
    else
        echo "check-version-bump.sh: images/${name} changed, but its version ${new} is not greater than ${old}${old_note} before the change: raise images/${name}/version" >&2
        failed=1
    fi
done <"${work}/images"

if [ "${failed}" -ne 0 ]; then
    exit 1
fi
