#!/bin/sh
# Makes disk.qcow2 next to this script, the FreeBSD disk that the Dockerfile copies into the
# image. The build workflow runs it on the runner before "docker build", from the
# repository root, because the disk is made by booting FreeBSD once and docker build
# cannot give a machine hardware help.
#
#   sh images/<name>/prepare.sh amd64
#
# It downloads the official disk (the line of the file "official"), checks its checksum,
# unpacks it, and lets prepare-disk.sh set it up inside the go-qemu image. The download
# and the unpacked disk are removed at the end.
set -eu

arch="${1:-}"
if [ "${arch}" != amd64 ]; then
    echo "usage: prepare.sh amd64 (this image is built for amd64 only, got \"${arch}\")" >&2
    exit 1
fi

# The folder of this script as an absolute path, because docker mounts it.
case "$0" in
    */*) script_dir="${0%/*}" ;;
    *) script_dir=. ;;
esac
here="$(cd "${script_dir}" && pwd)"
work="${here}/work"
archive="${work}/official.qcow2.xz"
disk="${here}/disk.qcow2"

# Prints the seconds since the start time in $2, under the name in $1.
report() {
    stop="$(date +%s)"
    echo "[time] ${1}: $((stop - ${2}))s"
}

# The line of "official" for this CPU type: release, CPU type, checksum, address. Comment
# lines start with #.
line="$(awk -v arch="${arch}" '$1 !~ /^#/ && $2 == arch { print; exit }' "${here}/official")"
if [ -z "${line}" ]; then
    echo "no line for ${arch} in ${here}/official" >&2
    exit 1
fi
read -r release _ checksum address <<LINE
${line}
LINE

rm -rf "${work}"
rm -f "${disk}"
mkdir -p "${work}"

echo "Downloading FreeBSD ${release} ${arch}"
start="$(date +%s)"
curl -fsSL --retry 3 -o "${archive}" "${address}"
report "download" "${start}"

# A download that does not match the checksum is never used.
actual="$(sha256sum "${archive}")"
actual="${actual%% *}"
if [ "${actual}" != "${checksum}" ]; then
    echo "checksum of the download is ${actual}, the file official says ${checksum}" >&2
    exit 1
fi

start="$(date +%s)"
xz -d "${archive}"
report "unpack" "${start}"

# The machine may take up to 600 seconds. /dev/kvm is passed on when the runner has it,
# because without it the machine is emulated and many times slower.
set -- run --rm
if [ -e /dev/kvm ]; then set -- "$@" --device /dev/kvm; fi
start="$(date +%s)"
docker "$@" -e VM_TIMEOUT=600 -v "${here}:/image" ghcr.io/splicefs/go-qemu:latest \
    sh /image/prepare-disk.sh "${arch}" /image/work/official.qcow2 /image/disk.qcow2
report "preparation" "${start}"

rm -rf "${work}"
size="$(wc -c < "${disk}")"
echo "disk: ${disk}, $((size)) bytes"
