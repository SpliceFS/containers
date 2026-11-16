#!/bin/sh
# Succeeds, and prints nothing, when the text is a version: v followed by a positive whole
# number without a leading zero (v1, v2, v10). Every other script that needs to know what
# a version looks like asks this one, so the rule has one place.
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

# Nothing, a zero first or any other character than a digit is not a number. A line
# break counts as such a character, so a text of several lines never passes.
case "${1#v}" in
"" | 0* | *[!0-9]*) exit 1 ;;
*) ;;
esac
