#!/bin/sh
# Prints the version of an image: the one line of images/NAME/version, for example v3. A
# version that is malformed is an error, so nothing downstream sees one. The build
# workflow publishes the image under this name, and the pull request checks compare it.
#
#   image-version.sh NAME        the version in the working files
#   image-version.sh NAME REV    the version at a commit, found the way git names it
#
# Exit status: 0 for a version, 1 for a file that is malformed, 2 for wrong arguments, 3
# for an image that has no version file (at that commit). The pull request checks treat 3
# as "no version yet", which is how an image starts.
set -eu

usage() {
    echo "usage: image-version.sh NAME [REV]" >&2
    exit 2
}

case "$#" in
1)
    rev=""
    ;;
2)
    rev="$2"
    # An empty name for git would read the index, not a commit.
    if [ -z "${rev}" ]; then
        usage
    fi
    ;;
*)
    usage
    ;;
esac
name="$1"

# The repository is found from this script's own place, so the script works from any
# folder and can be tested against a throwaway copy of the layout. The name comes from
# changed-images.sh, which checks it.
case "$0" in
*/*) here="${0%/*}" ;;
*) here="." ;;
esac
root="$(cd "${here}/.." && pwd)"
path="images/${name}/version"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
trap 'exit 1' HUP INT TERM

# Both ways end in the same file, so one set of checks below covers the working files and
# a commit alike. The line breaks at the end of the file are kept, which a variable would
# lose.
content="${work}/content"
if [ -n "${rev}" ]; then
    if ! git -C "${root}" show "${rev}:${path}" >"${content}" 2>/dev/null; then
        echo "image-version.sh: ${path} does not exist at ${rev}" >&2
        exit 3
    fi
    where="${path} at ${rev}"
else
    if [ ! -e "${root}/${path}" ]; then
        echo "image-version.sh: ${path} does not exist" >&2
        exit 3
    fi
    if [ ! -f "${root}/${path}" ]; then
        echo "image-version.sh: ${path} is not a file" >&2
        exit 1
    fi
    cp "${root}/${path}" "${content}"
    where="${path}"
fi

# awk counts a last line that has no line break, which wc does not.
lines="$(awk 'END { print NR }' "${content}")"
if [ "${lines}" -ne 1 ]; then
    echo "image-version.sh: ${where} must hold one line, the version, and it holds ${lines}" >&2
    exit 1
fi

# IFS is emptied so that spaces around the text stay and make it malformed. read reports
# failure for a last line without a line break, though it has read the line.
IFS= read -r version <"${content}" || [ -n "${version}" ]
if ! sh "${here}/version-valid.sh" "${version}"; then
    echo "image-version.sh: ${where} says \"${version}\", which is not a version: use v followed by a number, as in v1" >&2
    exit 1
fi
echo "${version}"
