#!/bin/sh
# Part of the move from the old versions (v1, v2, ...) to MAJOR.MINOR.PATCH. Prints the
# version that the old form in images/NAME/version at a commit stands for: the same number
# with .0.0, so v1 is v1.0.0. check-version-bump.sh uses it to compare a new version with
# the old one that it replaces.
#
#   legacy-version.sh NAME REV
#
# Exit status: 0 for the version, 1 when the file is not in the old form or does not exist
# at that commit, 2 for wrong arguments.
#
# Delete this script and its test, and the place in check-version-bump.sh that asks it, once
# every image has the new form on the main branch.
set -eu

if [ "$#" -ne 2 ] || [ -z "$2" ]; then
    echo "usage: legacy-version.sh NAME REV" >&2
    exit 2
fi
name="$1"
rev="$2"

# The repository, and the other scripts, are found from this script's own place.
case "$0" in
*/*) here="${0%/*}" ;;
*) here="." ;;
esac
root="$(cd "${here}/.." && pwd)"

old_form="$(git -C "${root}" show "${rev}:images/${name}/version" 2>/dev/null)" || exit 1

# A dot makes it the new form, or a version that is not valid at all.
case "${old_form}" in
*.*) exit 1 ;;
*) ;;
esac

# The old form is a valid version once the two numbers are added, so the rule for a number
# stays in version-valid.sh.
sh "${here}/version-valid.sh" "${old_form}.0.0" || exit 1
echo "${old_form}.0.0"
