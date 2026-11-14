#!/bin/sh
# Prints the names of the images that a change touched, one per line, sorted. An image
# is a folder under images/ that holds a Dockerfile at the head commit. The build
# workflow uses this so that an image is built only when its own folder changed.
#
#   changed-images.sh BASE HEAD   images with a changed, added or removed file
#   changed-images.sh --all       every image at the current commit
#
# An empty BASE, or one made of zeros (the first push of a branch has no earlier
# commit), means every image, the same as --all.
set -eu

# Sorting and the character ranges below must not depend on the caller's locale.
LC_ALL=C
export LC_ALL

usage() {
    echo "usage: changed-images.sh BASE HEAD | --all" >&2
    exit 2
}

case "$#" in
1)
    if [ "$1" != "--all" ]; then
        usage
    fi
    base=""
    head="HEAD"
    ;;
2)
    base="$1"
    head="$2"
    ;;
*)
    usage
    ;;
esac

# git prints paths relative to the folder it runs in, so run it from the top.
top="$(git rev-parse --show-toplevel)"
cd "${top}"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
trap 'exit 1' HUP INT TERM

# NUL separated lists, because git quotes unusual file names otherwise and the names
# must be seen as they are to be checked.
git ls-tree -r --name-only -z "${head}" -- images >"${work}/head.nul"
tr '\0' '\n' <"${work}/head.nul" >"${work}/head-files"

case "${base}" in
*[!0]*)
    git diff --name-only -z "${base}" "${head}" -- images >"${work}/diff.nul"
    tr '\0' '\n' <"${work}/diff.nul" >"${work}/listed"
    ;;
*)
    cp "${work}/head-files" "${work}/listed"
    ;;
esac

# Only paths inside a folder count. A file directly under images/ belongs to no image.
sed -n 's|^images/\([^/][^/]*\)/.*|\1|p' "${work}/listed" | sort -u >"${work}/names"

: >"${work}/result"
while IFS= read -r name; do
    # A folder that was removed, or that lost its Dockerfile, is not an image any more,
    # so a badly named folder can still be deleted.
    if grep -Fxq "images/${name}/Dockerfile" "${work}/head-files"; then
        case "${name}" in
        [!a-z0-9]* | *[!a-z0-9-]*)
            echo "changed-images.sh: bad image name \"${name}\", use a-z, 0-9 and -, starting with a letter or digit" >&2
            exit 1
            ;;
        *)
            echo "${name}" >>"${work}/result"
            ;;
        esac
    fi
done <"${work}/names"

cat "${work}/result"
