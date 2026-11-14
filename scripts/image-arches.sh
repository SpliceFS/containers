#!/bin/sh
# Prints the CPU types an image is built for, one per line. The file images/NAME/arch
# lists them, one per line, as amd64 or arm64. An image without that file is built for
# both. The build workflow uses this to pick what to build and what to join.
#
#   image-arches.sh NAME
set -eu

usage() {
    echo "usage: image-arches.sh NAME" >&2
    exit 2
}

if [ "$#" -ne 1 ]; then
    usage
fi
name="$1"

# The name becomes part of a path, so it is checked before it is used.
case "${name}" in
"" | [!a-z0-9]* | *[!a-z0-9.-]*)
    echo "image-arches.sh: bad image name \"${name}\", use a-z, 0-9, . and -, starting with a letter or digit" >&2
    exit 1
    ;;
*) ;;
esac

# The images folder is found from this script's own place, so the script works from any
# folder and can be tested against a throwaway copy of the layout.
case "$0" in
*/*) here="${0%/*}" ;;
*) here="." ;;
esac
root="$(cd "${here}/.." && pwd)"
file="${root}/images/${name}/arch"

if [ ! -e "${file}" ]; then
    echo "amd64"
    echo "arm64"
    exit 0
fi
if [ ! -f "${file}" ]; then
    echo "image-arches.sh: images/${name}/arch is not a file" >&2
    exit 1
fi

newline='
'
result=""
# The last line counts even when it has no line break at its end.
while IFS= read -r line || [ -n "${line}" ]; do
    case "${line}" in
    "")
        # A blank line says nothing.
        ;;
    amd64 | arm64)
        # Twice the same type would build and join the same image twice.
        case "${newline}${result}" in
        *"${newline}${line}${newline}"*)
            echo "image-arches.sh: images/${name}/arch lists ${line} twice" >&2
            exit 1
            ;;
        *) ;;
        esac
        result="${result}${line}${newline}"
        ;;
    *)
        echo "image-arches.sh: images/${name}/arch: unknown CPU type \"${line}\", use amd64 or arm64" >&2
        exit 1
        ;;
    esac
done <"${file}"

# An empty file is a mistake, not a way to build nothing: an image that is not to be
# built is removed, not emptied.
if [ -z "${result}" ]; then
    echo "image-arches.sh: images/${name}/arch lists no CPU type" >&2
    exit 1
fi

# Printed only now, so that a file with an error prints nothing.
printf '%s' "${result}"
