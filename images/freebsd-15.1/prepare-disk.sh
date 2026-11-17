#!/bin/sh
# Makes a FreeBSD disk that is already set up, so that a test run does not repeat the first
# boot and the package tool setup every time. It runs inside the go-qemu image, which
# already has QEMU, and installs nothing. Run it as root (prepare.sh does): only root and
# the group of /dev/kvm can use hardware virtualization, and the go-qemu image does not
# run as root by default.
#
#   prepare-disk.sh <amd64|arm64> <official disk> <output disk>
#
# It boots the official disk with the preparation job (prepare-job.sh), then turns the
# copy-on-write layer of that boot plus the official disk into one standalone compressed disk.
# The job folder is made from user-data.in and prepare-job.sh next to this script.
#
# VM_TIMEOUT (default 240) is the longest one boot may take, in seconds.
#
# The first boot of the official disk installs base system updates. When the machine is
# emulated that takes longer than one VM_TIMEOUT. After VM_TIMEOUT minus 60 seconds the
# machine is therefore asked to power off the way a person would, by the power button, so
# that its disks are left clean. WORK_DIR (a folder that stays between runs, mounted at the
# same path every time) keeps the boot layers, so that running the script again continues
# where the machine stopped. Without WORK_DIR nothing is kept, and a boot that does not
# finish is a failure. Delete WORK_DIR to start from scratch.
#
# This script boots the machine itself instead of calling vm.sh, because vm.sh throws its
# copy-on-write layer away and this script has to keep it, and because only this script
# presses the power button.
set -eu

machine="$1"
official="$2"
output="$3"
here="$(dirname "$0")"
limit="${VM_TIMEOUT:-240}"
work="${WORK_DIR:-}"
if [ -z "${work}" ]; then work="$(mktemp -d)"; fi
mkdir -p "${work}"

# Prints the seconds since the start time in $2, under the name in $1.
report() {
    stop="$(date +%s)"
    echo "[time] ${1}: $((stop - ${2}))s"
}

# Nothing is installed here, so a missing QEMU is a mistake in how the script is called.
if ! command -v qemu-img >/dev/null 2>&1; then
    echo "qemu-img is missing: run this script inside the ghcr.io/splicefs/go-qemu image or an image built on it" >&2
    exit 1
fi

# Every boot works on a layer over the one before it, and the first one over the official
# disk, which is never written to.
disk="${official}"
boots=0
for folder in "${work}"/boot-*; do
    [ -d "${folder}" ] || continue
    boots=$((boots + 1))
    if [ -f "${folder}/disk.qcow2" ]; then disk="${folder}/disk.qcow2"; fi
done
boots=$((boots + 1))
number="$(printf '%02d' "${boots}")"
boot="${work}/boot-${number}"
rm -rf "${boot}"
mkdir -p "${boot}"

# The job folder is made like any other: FreeBSD runs the file user-data from the disk
# labelled cidata, and user-data runs the job script. A boot that continues an earlier one
# gets an instance id of its own, so that nuageinit does not take it for a repeat and skip
# the job.
job="${work}/prepare-job"
rm -rf "${job}"
mkdir -p "${job}"
cp "${here}/prepare-job.sh" "${job}/"
sed -e "s|@JOB@|prepare-job.sh|" -e "s|@ARGS@||" "${here}/user-data.in" > "${job}/user-data"
printf 'instance-id: prepare-job-%s\nlocal-hostname: build\n' "${number}" > "${job}/meta-data"

# The layer is larger than the disk, and FreeBSD grows its filesystem into the room at first
# boot. The machine writes the results of the job as a tar archive straight onto the third
# disk, so that no filesystem has to be shared between two operating systems.
qemu-img create -q -f qcow2 -F qcow2 -b "${disk}" "${boot}/disk.qcow2" 20G
truncate -s 256M "${boot}/out.img"

# Hardware virtualization when the computer offers it for this CPU type, emulation otherwise.
accel="tcg,thread=multi"
cpu=max
if [ -w /dev/kvm ] && [ "${machine}" = amd64 ]; then
    accel=kvm
    cpu=host
fi
case "${machine}" in
    amd64) set -- qemu-system-x86_64 -machine q35 ;;
    arm64) set -- qemu-system-aarch64 -machine virt -bios /usr/share/qemu-efi-aarch64/QEMU_EFI.fd ;;
    *) echo "unknown machine ${machine}" >&2; exit 1 ;;
esac

# The power button is pressed through QEMU's monitor, which reads its commands from a pipe.
mkfifo "${boot}/monitor.in" "${boot}/monitor.out"
(
    sleep "$((limit - 60))"
    echo system_powerdown > "${boot}/monitor.in"
) &
timer=$!

# The job folder is attached through a throwaway layer (snapshot=on) because FreeBSD mounts
# it read-write and the folder itself must stay untouched. romfile= spares the network card a
# boot ROM that the image does not have and nothing needs.
start="$(date +%s)"
status=0
timeout "${limit}" "$@" -cpu "${cpu}" -accel "${accel}" -smp 4 -m 2048 \
    -drive "if=virtio,file=${boot}/disk.qcow2,format=qcow2" \
    -drive "if=virtio,driver=vvfat,dir=${job},label=cidata,snapshot=on" \
    -drive "if=virtio,file=${boot}/out.img,format=raw" \
    -netdev user,id=n0 -device virtio-net-pci,netdev=n0,romfile= \
    -display none -serial "file:${boot}/console.log" -monitor "pipe:${boot}/monitor" \
    -no-reboot || status=$?
# The timer is stopped so that it cannot write to a pipe that nobody reads any more.
kill "${timer}" 2>/dev/null || true
report "preparation boot" "${start}"

got="${boot}/got"
mkdir -p "${got}"
tar xf "${boot}/out.img" -C "${got}" 2>/dev/null || true
if [ -f "${got}/log.txt" ]; then cat "${got}/log.txt"; fi
if [ "${status}" -ne 0 ] || [ ! -f "${got}/ok" ]; then
    echo "preparation boot ${number} did not finish its job (qemu status ${status}); its console:" >&2
    tail -n 6 "${boot}/console.log" >&2 || true
    echo "run this script again with the same WORK_DIR to continue" >&2
    exit 75
fi

# -c compresses, and the result has no link to the official disk or to the layers.
start="$(date +%s)"
qemu-img convert -c -O qcow2 "${boot}/disk.qcow2" "${output}"
report "conversion" "${start}"

size="$(stat -c %s "${output}")"
echo "output disk: ${output}, ${size} bytes"
