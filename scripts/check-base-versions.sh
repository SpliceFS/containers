#!/bin/sh
# Fails, naming the Dockerfile, when an image that a change touched is built on another
# image of this repository without naming a version that exists. A tag that moves, such as
# latest, would make the image different from one build to the next, so the base must be
# pinned to a version, as in FROM ghcr.io/splicefs/go-qemu:v1.0.0. The version exists when the
# registry holds it, or when this same change publishes it: the base image is in the change
# and has that version at HEAD. A pull request runs this with the fork point as BASE and
# its last commit as HEAD.
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

        if ! sh "${here}/version-valid.sh" "${tag}"; then
            echo "check-base-versions.sh: images/${name}/Dockerfile: ${reference} does not name a version: pin it, as in ${prefix}${base_name}:v1.0.0" >&2
            failed=1
            continue
        fi

        # The version that this change publishes for the base is not in the registry yet.
        # An image that does not have a readable version just has none to offer here, and
        # check-version-bump.sh reports it.
        this_change=""
        if grep -Fxq "${base_name}" <"${work}/changed"; then
            this_change="$(sh "${here}/image-version.sh" "${base_name}" "${head}" 2>/dev/null)" || this_change=""
        fi
        if [ "${tag}" = "${this_change}" ]; then
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
