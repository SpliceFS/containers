#!/bin/sh
# Tests the one-shot rc.d script of the FreeBSD images (images/freebsd-15.1/second-boot.in,
# the other releases hold the same file) with the machine's commands replaced by stubs and its
# paths moved into a throwaway folder. Run from anywhere:
#   sh scripts/freebsd-second-boot-test.sh
#
# The scratch disk is a plain file here and tar is the real one, so the archive of the first
# boot is really read and the archive of the second boot is really written. What it proves: the
# file runs once, with the result folder as its only argument, after the script removed itself;
# the results of the first boot are in the results that go back, without the ok and the file
# second-boot of the first boot; the ok of the second boot is the status of the file alone;
# the output of the file is on the console once and added to log.txt; nothing an earlier boot
# left in /tmp reaches the caller; and the machine is powered off only after the results are
# on the scratch disk.
set -eu

case "$0" in
*/*) here="${0%/*}" ;;
*) here="." ;;
esac
template="$(cd "${here}/.." && pwd)/images/freebsd-15.1/second-boot.in"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
trap 'exit 1' HUP INT TERM

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

mkdir -p "${work}/stubs"
# rc.subr runs start_cmd when the script is enabled, which is all of it that the script
# uses here.
cat >"${work}/rc.subr" <<'STUB'
load_rc_config() { :; }
run_rc_command() {
    if [ "$1" = start ] && [ "${second_boot_enable}" = YES ]; then
        eval "${start_cmd}"
    fi
}
STUB
# The machine is powered off with the scratch disk as it is at that moment, which shows
# whether the results were written before.
cat >"${work}/stubs/shutdown" <<STUB
#!/bin/sh
echo "\$*" >"${work}/shutdown-arguments"
tar tf "${work}/vtbd2" >"${work}/disk-at-shutdown"
STUB
chmod 755 "${work}/stubs/shutdown"

# The paths of the machine are moved first from /tmp/, because the work folder can be under
# /tmp/ (it is on Linux), and the paths that come in after must not be moved again.
install_script() {
    mkdir -p "${work}/rcd"
    sed -e "s|/tmp/|${work}/tmp/|g" \
        -e "s|@FILE@|${work}/file.sh|" \
        -e "s|/usr/local/etc/rc.d/|${work}/rcd/|g" \
        -e "s|/dev/vtbd2|${work}/vtbd2|g" \
        -e "s|/dev/console|${work}/console|g" \
        -e "s|/etc/rc.subr|${work}/rc.subr|" \
        "${template}" >"${work}/rcd/second_boot"
    chmod 555 "${work}/rcd/second_boot"
}

# fresh makes the machine after its first boot: the archive of the results of the first boot
# on the scratch disk, the script installed, and the file to run from stdin.
fresh() {
    rm -rf "${work}/first" "${work}/after" "${work}/tmp" "${work}/rcd" "${work}/console" \
        "${work}/shutdown-arguments" "${work}/disk-at-shutdown"
    mkdir -p "${work}/first" "${work}/tmp"
    printf 'phase one\n' >"${work}/first/log.txt"
    : >"${work}/first/ok"
    : >"${work}/first/second-boot"
    printf 'written in boot one\n' >"${work}/first/first"
    tar cf "${work}/vtbd2" -C "${work}/first" .
    cat >"${work}/file.sh"
    install_script
}

# start boots the machine the second time and unpacks what goes back to the caller.
start() {
    PATH="${work}/stubs:${PATH}" sh "${work}/rcd/second_boot" start
    mkdir -p "${work}/after"
    tar xf "${work}/vtbd2" -C "${work}/after"
}

fresh <<JOB
echo "phase two"
echo "\$#:\$1" >"\$1/arguments"
if [ -e "${work}/rcd/second_boot" ]; then echo present; else echo gone; fi >"\$1/script"
echo written in boot two >"\$1/second"
JOB
start

arguments="$(cat "${work}/after/arguments")"
if [ "${arguments}" != "1:${work}/tmp/out" ]; then
    fail "the file got \"${arguments}\", wanted its result folder as its only argument"
fi
echo "ok - the file runs with the result folder as its only argument"

script="$(cat "${work}/after/script")"
if [ "${script}" != gone ]; then
    fail "the script was still installed when the file ran"
fi
if [ -e "${work}/rcd/second_boot" ]; then
    fail "the script is still installed after the boot"
fi
echo "ok - the script removes itself before it runs the file"

for name in first second; do
    if [ ! -f "${work}/after/${name}" ]; then
        fail "${name} is not in the results that go back"
    fi
done
echo "ok - the results of both boots go back"

if [ ! -f "${work}/after/ok" ]; then
    fail "a file that exits with 0 left no ok file"
fi
if [ -e "${work}/after/second-boot" ]; then
    fail "the file second-boot of the first boot went back"
fi
echo "ok - the file second-boot does not go back, and ok comes from this boot"

logged="$(cat "${work}/after/log.txt")"
if [ "${logged}" != "phase one
phase two" ]; then
    fail "log.txt does not hold the log of the first boot and the output of the file"
fi
shown="$(cat "${work}/console")"
if [ "${shown}" != "phase two" ]; then
    fail "the console holds \"${shown}\", wanted the output of the file once"
fi
echo "ok - the output of the file is added to log.txt and shown once on the console"

arguments="$(cat "${work}/shutdown-arguments")"
if [ "${arguments}" != "-p now" ]; then
    fail "shutdown was called with \"${arguments}\", wanted -p now"
fi
if ! grep -q 'second' "${work}/disk-at-shutdown"; then
    fail "the results were not on the scratch disk when the machine was powered off"
fi
echo "ok - the machine is powered off after the results are on the scratch disk"

if [ -e "${work}/tmp/out" ] || [ -e "${work}/tmp/status" ]; then
    fail "the boot left its result folder or its status file behind"
fi
echo "ok - the boot leaves nothing in /tmp"

# The ok of the first boot must not make a failing file pass, and the machine is powered off
# all the same.
fresh <<'JOB'
echo "failing"
exit 3
JOB
start
if [ -e "${work}/after/ok" ]; then
    fail "a file that exits with 3 left an ok file, from the first boot or the pipe"
fi
if [ ! -f "${work}/disk-at-shutdown" ]; then
    fail "the machine was not powered off after a failing file"
fi
echo "ok - a file that fails leaves no ok file and the machine is still powered off"

# Results of an earlier second boot in /tmp (FreeBSD keeps it) must not go back.
fresh <<'JOB'
echo "phase two"
JOB
mkdir -p "${work}/tmp/out"
: >"${work}/tmp/out/stale"
echo 0 >"${work}/tmp/status"
start
if [ -e "${work}/after/stale" ]; then
    fail "a file left in /tmp by an earlier boot went back"
fi
echo "ok - nothing an earlier boot left in /tmp reaches the caller"
