#!/bin/sh
# Succeeds, and prints nothing, when the text is a version: v, then three whole numbers
# separated by dots, as in v1.0.0 (major, minor, patch). A number has no leading zero, and
# zero itself is a number. Every other script that needs to know what a version looks like
# asks this one, so the rule has one place.
#
#   version-valid.sh TEXT
set -eu

if [ "$#" -ne 1 ]; then
    echo "usage: version-valid.sh TEXT" >&2
    exit 2
fi

# The character ranges below must not depend on the caller's locale.
LC_ALL=C
export LC_ALL

case "$1" in
v*) ;;
*) exit 1 ;;
esac

# Exactly three numbers, so exactly two dots.
rest="${1#v}"
case "${rest}" in
*.*.*.*) exit 1 ;;
*.*.*) ;;
*) exit 1 ;;
esac
major="${rest%%.*}"
rest="${rest#*.}"
minor="${rest%%.*}"
patch="${rest#*.}"

# Nothing, a zero followed by more digits or any other character than a digit is not a
# number. A line break counts as such a character, so a text of several lines never passes.
for number in "${major}" "${minor}" "${patch}"; do
    case "${number}" in
    "" | 0[0-9]* | *[!0-9]*) exit 1 ;;
    *) ;;
    esac
done
