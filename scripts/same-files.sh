#!/bin/sh
# Fails, naming the file, when a file differs between two of the folders images/freebsd-*.
# The files "official", "README.md" and "version" in the top of a folder are the only ones
# that may. Each release has a version of its own, and they differ as soon as one release
# gets a new version.
#
#   same-files.sh
#
# Why: there is one folder for each FreeBSD release, and the folders are copies on purpose,
# because the build of an image sees only its own folder, so a file cannot be shared
# between them. Copies drift apart unless something compares them, and this does. It runs
# in the Build workflow.
#
# Every folder is compared with the first one. If two folders differ from each other, at
# least one of them also differs from the first, so every difference is found.
set -eu

usage() {
    echo "usage: same-files.sh" >&2
    exit 2
}

if [ "$#" -ne 0 ]; then
    usage
fi

# Sorting must not depend on the caller's locale.
LC_ALL=C
export LC_ALL

# The repository is found from this script's own place, so the script works from any folder
# and can be tested against a throwaway copy of the layout.
case "$0" in
*/*) here="${0%/*}" ;;
*) here="." ;;
esac
root="$(cd "${here}/.." && pwd)"
cd "${root}"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
trap 'exit 1' HUP INT TERM

# list_files FOLDER OUTPUT writes the files of the folder, as paths relative to it, sorted.
# The three files that may differ are left out. So are disk.qcow2 and work/, which prepare.sh
# leaves behind on a computer where it ran, and which git ignores.
list_files() {
    (cd "$1" && find . -type f ! -path ./official ! -path ./README.md ! -path ./version \
        ! -path ./disk.qcow2 ! -path './work/*') >"$2"
    sort -o "$2" "$2"
}

# The folders to compare. A folder name that matched nothing, or a file, is not one.
set --
for folder in images/freebsd-*; do
    if [ -d "${folder}" ]; then
        set -- "$@" "${folder}"
    fi
done
if [ "$#" -lt 2 ]; then
    echo "same-files.sh: fewer than two folders images/freebsd-*, nothing to compare"
    exit 0
fi

reference="$1"
count="$#"
shift
failed=0
list_files "${reference}" "${work}/reference"
for folder in "$@"; do
    list_files "${folder}" "${work}/folder"
    sort -u "${work}/reference" "${work}/folder" >"${work}/all"
    while IFS= read -r path; do
        path="${path#./}"
        if [ ! -f "${folder}/${path}" ]; then
            echo "same-files.sh: ${folder}/${path} is missing, but ${reference}/${path} exists" >&2
            failed=1
        elif [ ! -f "${reference}/${path}" ]; then
            echo "same-files.sh: ${reference}/${path} is missing, but ${folder}/${path} exists" >&2
            failed=1
        elif ! cmp -s "${reference}/${path}" "${folder}/${path}"; then
            echo "same-files.sh: ${folder}/${path} differs from ${reference}/${path}" >&2
            failed=1
        fi
    done <"${work}/all"
done

if [ "${failed}" -ne 0 ]; then
    exit 1
fi
echo "same-files.sh: ${count} folders hold the same files"
