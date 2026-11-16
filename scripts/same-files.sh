#!/bin/sh
# Fails, naming the file, when a file differs between two folders of one group of image
# folders that are copies of each other. The groups are in group_of below: the FreeBSD
# releases (images/freebsd-*) and one group for each package family of the server images
# (deb, rpm and apk). Each group has files that may differ, in the top of a folder, see
# list_files. Every other file must be identical.
#
#   same-files.sh
#
# Why: the folders of a group are copies on purpose, because the build of an image sees only
# its own folder, so a file cannot be shared between them. Copies drift apart unless
# something compares them, and this does. It runs in the Build workflow.
#
# Every folder of a group is compared with the first one of it. If two folders differ from
# each other, at least one of them also differs from the first, so every difference is found.
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

# group_of NAME prints the group of the image folder NAME, and nothing for an image whose
# folder has no copies. This is the one list of the groups. A new family of images is added
# here, and the folders of an image that is not named here are never compared.
group_of() {
    case "$1" in
    freebsd-*) echo freebsd ;;
    server-debian-* | server-ubuntu-*) echo server-deb ;;
    server-rocky-* | server-amazonlinux-* | server-opensuse-*) echo server-rpm ;;
    server-alpine-*) echo server-apk ;;
    *) ;;
    esac
}

# list_files GROUP FOLDER OUTPUT writes the files of the folder that must be identical, as
# paths relative to it, sorted. The files that may differ are left out, but only where they
# are named, in the top of the folder. The FreeBSD folders differ in the release they hold
# ("official"), in their README.md and in their version. The server folders differ in the
# Dockerfile, because its FROM line names another system, and in README.md and version.
# disk.qcow2 and work/ are what prepare.sh leaves behind on a computer where it ran, and
# git ignores them.
list_files() {
    group="$1"
    folder="$2"
    output="$3"
    case "${group}" in
    freebsd)
        set -- ! -path ./official ! -path ./README.md ! -path ./version \
            ! -path ./disk.qcow2 ! -path './work/*'
        ;;
    *)
        set -- ! -path ./Dockerfile ! -path ./README.md ! -path ./version
        ;;
    esac
    (cd "${folder}" && find . -type f "$@") >"${output}"
    sort -o "${output}" "${output}"
}

failed=0

# compare_group GROUP compares the folders of the group with the first one, and sets failed
# when one differs.
compare_group() {
    group="$1"
    set --
    for folder in images/*; do
        if [ ! -d "${folder}" ]; then
            continue
        fi
        member="$(group_of "${folder#images/}")"
        if [ "${member}" = "${group}" ]; then
            set -- "$@" "${folder}"
        fi
    done
    if [ "$#" -lt 2 ]; then
        echo "same-files.sh: ${group}: fewer than two folders, nothing to compare"
        return 0
    fi

    reference="$1"
    count="$#"
    shift
    list_files "${group}" "${reference}" "${work}/reference"
    for folder in "$@"; do
        list_files "${group}" "${folder}" "${work}/folder"
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
    echo "same-files.sh: ${group}: ${count} folders compared"
}

# The groups that have a folder, each once. Run on its own line, so that a failure stops
# this script.
for folder in images/*; do
    if [ -d "${folder}" ]; then
        group_of "${folder#images/}"
    fi
done >"${work}/group-names"
sort -u "${work}/group-names" >"${work}/groups"

while IFS= read -r group; do
    compare_group "${group}"
done <"${work}/groups"

if [ "${failed}" -ne 0 ]; then
    exit 1
fi
