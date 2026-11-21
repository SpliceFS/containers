#!/bin/sh
# Runs one FreeBSD virtual machine to completion: it boots the disk, the machine runs the
# first-boot script of the job folder, writes its results to a scratch disk and powers off.
# It runs inside the go-qemu image, which already has QEMU, or an image built on it. Hardware
# virtualization needs /dev/kvm, which only root and the group of the device can open. The
# freebsd images run as root, so a run of theirs has it when the device is passed to docker.
# A run as another user without that group falls back to emulation, which is much slower.
#
#   vm.sh <amd64|arm64> <disk image> <job folder> <result folder> [input archive]
#
# The input archive, when given, is attached as a fourth disk that holds the tar archive
# itself, for input too large for the job folder.
#
# A job that needs the machine to boot once more (to prove what a restart does) creates the
# file second-boot in its result folder, installs what runs at the next boot, and ends as
# usual. The first boot powers off, and this script boots the same disk a second time, with
# the same scratch disk, so that what runs in the second boot can add to the results of the
# first. The second boot has no job disk: the boot hook of the disk would run the job again.
# The machine's own restart is not used, because every boot must end with a power off that
# this script can see. See user-data.in and second-boot.in for the part inside the machine.
# VM_TIMEOUT (default 900) is the longest each boot may take.
set -eu

machine="$1"
disk="$2"
job="$3"
results="$4"
input="${5:-}"

# Nothing is installed here, so a missing QEMU is a mistake in how the script is called.
if ! command -v qemu-img >/dev/null 2>&1; then
    echo "qemu-img is missing: run this script inside the ghcr.io/splicefs/go-qemu image or an image built on it" >&2
    exit 1
fi

# The folder goes when the run ends, after the second boot when there is one. It is named
# with a template because mktemp without one does not look at TMPDIR on every system.
work="$(mktemp -d "${TMPDIR:-/tmp}/freebsd-vm.XXXXXX")"
trap 'rm -rf "${work}"' EXIT
trap 'exit 1' HUP INT TERM
# The disk is never written to: the machine works on a copy-on-write layer over it. The
# layer is larger than the disk, and FreeBSD grows its filesystem into the room at first
# boot, so a job has space to unpack its input. A second boot continues on the same layer.
qemu-img create -q -f qcow2 -F qcow2 -b "${disk}" "${work}/disk.qcow2" 20G
# The machine writes a tar archive straight onto this disk, so no filesystem has to be
# shared between two operating systems.
truncate -s 256M "${work}/out.img"
# The second boot has this empty disk where the job disk was, so that the other disks keep
# their names (the scratch disk is /dev/vtbd2 for the machine in both boots).
truncate -s 1M "${work}/no-job.img"

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
# The program and its machine type, which every boot starts with.
emulator="$*"

mkdir -p "${results}"
job_name="$(basename "${job}")"

# boot <job disk> <console file> boots the machine once and returns the status of QEMU. The
# job disk of the first boot is attached through a throwaway layer (snapshot=on) because
# FreeBSD mounts it read-write and the folder itself must stay untouched. romfile= spares
# the network card a boot ROM that the image does not have and nothing needs.
boot() {
    # shellcheck disable=SC2086
    set -- ${emulator} -cpu "${cpu}" -accel "${accel}" -smp 4 -m 2048 \
        -drive "if=virtio,file=${work}/disk.qcow2,format=qcow2" \
        -drive "$1" \
        -drive "if=virtio,file=${work}/out.img,format=raw" \
        -serial "file:$2"
    # The input archive comes last, so the machine sees it as its fourth disk whether or not
    # it is there, and the first three keep their names.
    if [ -n "${input}" ]; then
        set -- "$@" -drive "if=virtio,file=${input},format=raw,read-only=on"
    fi
    set -- "$@" -netdev user,id=n0 -device virtio-net-pci,netdev=n0,romfile= -display none -no-reboot
    timeout "${VM_TIMEOUT:-900}" "$@"
}

# collect reads what the machine wrote on the scratch disk into a new folder, got.
got="${work}/got"
collect() {
    rm -rf "${got}"
    mkdir -p "${got}"
    tar xf "${work}/out.img" -C "${got}" 2>/dev/null || true
}

# check_boot <qemu status> <console file> ends the run when the boot did not do its job. A boot
# did it when the machine ended well and the job left the file ok. The run then shows what
# the job wrote, and the end of the console, which shows where the machine stood.
check_boot() {
    if [ "$1" -eq 0 ] && [ -f "${got}/ok" ]; then return 0; fi
    if [ -f "${got}/log.txt" ]; then cat "${got}/log.txt"; fi
    echo "the FreeBSD machine did not finish its job (qemu status ${1}); its console:" >&2
    tail -n 100 "$2" >&2 || true
    exit 1
}

console="${results}/console-${job_name}-${machine}.log"
# set -e is off while the machine runs, because its status is read and a status that is not
# 0 is not the end of this script.
set +e
boot "if=virtio,driver=vvfat,dir=${job},label=cidata,snapshot=on" "${console}"
status=$?
set -e
collect
check_boot "${status}" "${console}"

# The job asks for a second boot with a file in its result folder. A job that does not ask
# is done now, as before.
if [ -f "${got}/second-boot" ]; then
    console="${results}/console-${job_name}-${machine}-second-boot.log"
    set +e
    boot "if=virtio,file=${work}/no-job.img,format=raw" "${console}"
    status=$?
    set -e
    collect
    check_boot "${status}" "${console}"
fi

if [ -f "${got}/log.txt" ]; then cat "${got}/log.txt"; fi
rm -f "${got}/ok" "${got}/log.txt" "${got}/second-boot"
cp -R "${got}"/. "${results}"/
