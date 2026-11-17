#!/bin/sh
# Tells how two versions are ordered, by printing whether the first is less than, equal to
# or greater than the second. The versions are compared as numbers, major first, then
# minor, then patch, so v1.10.0 is greater than v1.9.0. Every script that needs to know
# which of two versions is newer asks this one, so the order has one place.
#
#   version-compare.sh A B     prints less, equal or greater
#
# Exit status: 0 for an answer, 1 when an argument is not a version, 2 for wrong arguments.
set -eu

if [ "$#" -ne 2 ]; then
    echo "usage: version-compare.sh A B" >&2
    exit 2
fi

# The other scripts are found from this script's own place.
case "$0" in
*/*) here="${0%/*}" ;;
*) here="." ;;
esac

for version in "$1" "$2"; do
    if ! sh "${here}/version-valid.sh" "${version}"; then
        echo "version-compare.sh: \"${version}\" is not a version: use vMAJOR.MINOR.PATCH, as in v1.0.0" >&2
        exit 1
    fi
done

# The text is only digits and dots here. A longer number is the greater one, and numbers
# of one length order like their text, so no number is turned into a machine integer,
# which would give a wrong answer for a very long one. The concatenation with an empty
# string makes awk compare text and not numbers.
LC_ALL=C awk -v a="${1#v}" -v b="${2#v}" 'BEGIN {
    split(a, x, ".")
    split(b, y, ".")
    for (i = 1; i <= 3; i++) {
        p = x[i] ""
        q = y[i] ""
        if (length(p) != length(q)) {
            print (length(p) < length(q) ? "less" : "greater")
            exit
        }
        if (p != q) {
            print (p < q ? "less" : "greater")
            exit
        }
    }
    print "equal"
}'
