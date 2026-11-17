#!/bin/sh
# Fails, naming the Dockerfile, when an image that a change touched is built on another
# image of this repository without naming a tag that exists. latest, no tag at all and a
# digest are refused: the base must name a version, so that the build does not depend on
# a tag that nobody controls. The tag is a major version (v1), a major and minor version
# (v1.2) or a full version (v1.2.3), as in FROM ghcr.io/splicefs/go-qemu:v1. It exists
# when the registry holds it, or when this same change publishes it: the base image is in
# the change, and the tag is its version or one of the tags that version moves
# (moving-tags.sh). A pull request runs this with the fork point as BASE and its last
# commit as HEAD.
#
#   check-base-versions.sh BASE HEAD
#
# The images are those that changed-images.sh lists. Only the FROM lines are read.
#
# Exit status: 0 when every base exists, 1 when one does not, 2 for wrong arguments, 3 when
# the registry could not be asked.
set -eu

usage() {
    echo "usage: check-base-versions.sh BASE HEAD" >&2
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
prefix="ghcr.io/splicefs/"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
trap 'exit 1' HUP INT TERM

# Run on its own line, so that its failure stops this script.
sh "${here}/changed-images.sh" "${base}" "${head}" >"${work}/changed"

# Lists in the file "offered" the tags that this change publishes for the image NAME: its
# version and the tags that version moves. They are not in the registry yet. The list is
# empty for an image that the change does not touch, and for one that does not have a
# readable version: that is for check-version-bump.sh to report.
offered_tags() {
    : >"${work}/offered"
    if ! grep -Fxq "$1" <"${work}/changed"; then
        return 0
    fi
    version="$(sh "${here}/image-version.sh" "$1" "${head}" 2>/dev/null)" || return 0
    echo "${version}" >"${work}/offered"
    sh "${here}/moving-tags.sh" "${version}" >>"${work}/offered"
}

failed=0
while IFS= read -r name; do
    # The image of each FROM line, after the flags such as --platform. An instruction is
    # not case sensitive. Run on its own line, so that its failure stops this script.
    git -C "${root}" show "${head}:images/${name}/Dockerfile" >"${work}/dockerfile"
    awk 'tolower($1) == "from" { i = 2; while (substr($i, 1, 2) == "--") i++; print $i }' \
        "${work}/dockerfile" >"${work}/references"

    while IFS= read -r reference; do
        case "${reference}" in
        "${prefix}"*) ;;
        *) continue ;;
        esac
        rest="${reference#"${prefix}"}"
        base_name="${rest%%[:@]*}"
        tag=""
        case "${rest}" in
        *:*) tag="${rest#*:}" ;;
        *) ;;
        esac

        # The tag is completed to three numbers, so that version-valid.sh judges all three
        # forms and the rule for a number stays in one place.
        case "${tag}" in
        *.*.*) full="${tag}" ;;
        *.*) full="${tag}.0" ;;
        *) full="${tag}.0.0" ;;
        esac
        if ! sh "${here}/version-valid.sh" "${full}"; then
            echo "check-base-versions.sh: images/${name}/Dockerfile: ${reference} does not name a version: use vX, vX.Y or vX.Y.Z, as in ${prefix}${base_name}:v1.0.0" >&2
            failed=1
            continue
        fi

        offered_tags "${base_name}"
        if grep -Fxq "${tag}" <"${work}/offered"; then
            echo "images/${name}: ${reference}"
            continue
        fi

        status=0
        sh "${here}/tag-published.sh" "${reference}" || status=$?
        case "${status}" in
        0)
            echo "images/${name}: ${reference}"
            ;;
        1)
            echo "check-base-versions.sh: images/${name}/Dockerfile: ${reference} is not published, and this change does not publish it" >&2
            failed=1
            ;;
        *)
            exit "${status}"
            ;;
        esac
    done <"${work}/references"
done <"${work}/changed"

if [ "${failed}" -ne 0 ]; then
    exit 1
fi
