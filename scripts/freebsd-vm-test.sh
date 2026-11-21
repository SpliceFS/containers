#!/bin/sh
# Tests vm.sh of the FreeBSD images (images/freebsd-15.1/vm.sh, the other releases hold the
# same file) with a stand-in for QEMU. Run from anywhere:
#   sh scripts/freebsd-vm-test.sh
#
# The stand-in is a small program that does what the real machine does to its disks: it
# keeps one file for the system disk layer, writes a tar archive onto the output disk, and
# can read the archive that an earlier boot left there. What it proves about vm.sh: a job
# that wants no second boot runs one machine and gets its result as always; a job that
# creates the file second-boot in its result folder gets a second boot of the same system
# disk layer with the same output disk, and no job disk, so that nothing runs the job again;
# a failure of either boot fails the run and shows the console of that boot; and the layer
# is removed at the end and not before.
set -eu

case "$0" in
*/*) here="${0%/*}" ;;
*) here="." ;;
esac
vm="$(cd "${here}/.." && pwd)/images/freebsd-15.1/vm.sh"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
trap 'exit 1' HUP INT TERM

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

plans="${work}/plans"
tmp="${work}/tmp"
mkdir -p "${work}/stubs" "${work}/job" "${tmp}"

# There is no QEMU here, and macOS has no timeout program.
cat >"${work}/stubs/timeout" <<'STUB'
#!/bin/sh
shift
exec "$@"
STUB
cat >"${work}/stubs/qemu-img" <<'STUB'
#!/bin/sh
# The layer is a file that every boot of the machine adds a line to. Its name is the one
# before the size, the last argument.
for argument in "$@"; do
    previous="${layer:-}"
    layer="${argument}"
done
: >"${previous}"
STUB
# The machine. PLANS holds what each boot does: PLANS/N/send is the folder the boot writes
# as its result archive, PLANS/N/restore says that the boot reads the archive of the boot
# before it first (as the script of a second boot does), PLANS/N/status is the exit status.
cat >"${work}/stubs/qemu-system-x86_64" <<'STUB'
#!/bin/sh
set -eu
number=$(($(cat "${PLANS}/boots" 2>/dev/null || echo 0) + 1))
echo "${number}" >"${PLANS}/boots"
drives="${PLANS}/drives-${number}"
: >"${drives}"
while [ "$#" -gt 0 ]; do
    case "$1" in
    -drive) echo "$2" >>"${drives}"; shift ;;
    -serial) console="${2#file:}"; shift ;;
    *) ;;
    esac
    shift
done
file_of() { sed -n "${1}p" "${drives}" | sed -n 's/.*file=\([^,]*\).*/\1/p'; }
layer="$(file_of 1)"
output="$(file_of 3)"
cp "${layer}" "${PLANS}/layer-seen-${number}"
echo "boot ${number}" >>"${layer}"
tar tf "${output}" >"${PLANS}/output-seen-${number}" 2>/dev/null || true
machine="${PLANS}/machine-${number}"
rm -rf "${machine}"
mkdir -p "${machine}"
if [ -f "${PLANS}/${number}/restore" ]; then tar xf "${output}" -C "${machine}"; fi
if [ -d "${PLANS}/${number}/send" ]; then cp -R "${PLANS}/${number}/send"/. "${machine}"/; fi
tar cf "${output}" -C "${machine}" .
echo "console of boot ${number}" >"${console}"
exit "$(cat "${PLANS}/${number}/status" 2>/dev/null || echo 0)"
STUB
chmod 755 "${work}/stubs"/*

# plan N [status]: starts the plan of boot N. The files it sends are added with send.
plan() {
    mkdir -p "${plans}/$1/send"
    echo "${2:-0}" >"${plans}/$1/status"
}
send() {
    printf '%s\n' "$3" >"${plans}/$1/send/$2"
}

# run [input archive]: runs vm.sh and keeps what it did in variables: its status, its
# standard output (out), its error output (err), the number of machines it started (boots)
# and what is left of the folder it made (left). The standard output and the error output
# are read into variables because ShellCheck wants a command substitution to stand alone.
run() {
    status=0
    PLANS="${plans}" TMPDIR="${tmp}" PATH="${work}/stubs:${PATH}" \
        sh "${vm}" amd64 "${work}/disk.qcow2" "${work}/job" "${work}/results" "$@" \
        >"${work}/stdout" 2>"${work}/stderr" || status=$?
    out="$(cat "${work}/stdout")"
    err="$(cat "${work}/stderr")"
    boots="$(cat "${plans}/boots")"
    left="$(ls -A "${tmp}")"
}

fresh() {
    rm -rf "${plans}" "${work}/results" "${work}/stdout" "${work}/stderr"
    mkdir -p "${plans}"
}

# disks_of N sets the disks that boot N was given: first_N, second_N, third_N and count_N.
disks_of() {
    first="$(sed -n 1p "${plans}/drives-${1}")"
    second="$(sed -n 2p "${plans}/drives-${1}")"
    third="$(sed -n 3p "${plans}/drives-${1}")"
    count="$(wc -l <"${plans}/drives-${1}")"
}

# A job that needs no second boot: one machine, the result as always.
fresh
plan 1
send 1 log.txt "phase one"
send 1 ok ""
send 1 data "from the job"
run
[ "${status}" -eq 0 ] || fail "a job without a second boot failed: ${err}"
[ "${boots}" -eq 1 ] || fail "a job without a second boot ran ${boots} machines"
[ "${out}" = "phase one" ] || fail "the log of the job is not the standard output"
data="$(cat "${work}/results/data")"
[ "${data}" = "from the job" ] || fail "the result of the job is not in the result folder"
for name in ok log.txt second-boot; do
    [ ! -e "${work}/results/${name}" ] || fail "${name} went into the result folder"
done
[ -f "${work}/results/console-job-amd64.log" ] || fail "the console of the machine is not in the result folder"
[ -z "${left}" ] || fail "vm.sh left ${left} behind"
echo "ok - a job without a second boot runs one machine and leaves only its result"

# A job that asks for a second boot. The second boot restores the archive of the first and
# does not remove second-boot from it, which vm.sh must not pass on.
fresh
plan 1
send 1 log.txt "phase one"
send 1 ok ""
send 1 second-boot ""
send 1 first "written in boot one"
plan 2
: >"${plans}/2/restore"
send 2 log.txt "phase one
phase two"
send 2 ok ""
send 2 second "written in boot two"
run
[ "${status}" -eq 0 ] || fail "a job with a second boot failed: ${err}"
[ "${boots}" -eq 2 ] || fail "a job with a second boot ran ${boots} machines"
echo "ok - the file second-boot in the result folder makes a second machine run"

disks_of 1
system_1="${first}"
output_1="${third}"
count_1="${count}"
disks_of 2
[ "${first}" = "${system_1}" ] || fail "the second boot did not get the system disk layer of the first"
grep -q 'boot 1' "${plans}/layer-seen-2" || fail "the layer of the second boot is not the one the first boot wrote to"
echo "ok - the second boot starts from the system disk layer the first boot left"

[ "${third}" = "${output_1}" ] || fail "the second boot did not get the output disk of the first"
grep -q 'first' "${plans}/output-seen-2" || fail "the second boot does not find the result of the first on the output disk"
echo "ok - the second boot gets the output disk of the first, with its result on it"

case "${second}" in
*cidata* | *vvfat*) fail "the second boot got a job disk, which would run the job again" ;;
*) ;;
esac
[ "${count}" -eq "${count_1}" ] || fail "the second boot has a different number of disks, so the output disk would get another name"
echo "ok - the second boot has a disk in the place of the job disk, and no job"

[ "${out}" = "phase one
phase two" ] || fail "the standard output is not the whole log, once: ${out}"
for name in first second; do
    [ -f "${work}/results/${name}" ] || fail "${name}, written by one of the boots, is not in the result folder"
done
for name in ok log.txt second-boot; do
    [ ! -e "${work}/results/${name}" ] || fail "${name} went into the result folder"
done
for console in console-job-amd64.log console-job-amd64-second-boot.log; do
    [ -f "${work}/results/${console}" ] || fail "${console} is not in the result folder"
done
echo "ok - the result folder holds what both boots wrote, the log is printed once, both consoles are kept"
[ -z "${left}" ] || fail "vm.sh left ${left} behind"
echo "ok - the layer is removed after the second boot"

# The input archive is a disk of both boots, so that the second boot sees the same machine.
fresh
plan 1
send 1 ok ""
send 1 second-boot ""
plan 2
send 2 ok ""
run "${work}/input.tar"
[ "${status}" -eq 0 ] || fail "a run with an input archive and a second boot failed: ${err}"
for number in 1 2; do
    fourth="$(sed -n 4p "${plans}/drives-${number}")"
    case "${fourth}" in
    *"${work}/input.tar"*"read-only=on"*) ;;
    *) fail "the fourth disk of boot ${number} is not the input archive, read only" ;;
    esac
done
echo "ok - the input archive is the fourth disk of both boots"

# A first boot that did not finish does not get a second boot, even when it asked for one.
fresh
plan 1
send 1 log.txt "phase one"
send 1 second-boot ""
send 1 first "written in boot one"
run
[ "${status}" -ne 0 ] || fail "a first boot without ok passed"
[ "${boots}" -eq 1 ] || fail "a first boot that did not finish got a second boot"
case "${err}" in
*"console of boot 1"*) ;;
*) fail "the console of the first boot is not shown" ;;
esac
[ "${out}" = "phase one" ] || fail "the log of the first boot is not shown"
[ ! -e "${work}/results/first" ] || fail "the result of a failed run went into the result folder"
[ -z "${left}" ] || fail "vm.sh left ${left} behind after a failed first boot"
echo "ok - a first boot that does not finish fails the run and gets no second boot"

# A second boot that did not finish fails the run, with the console of the second boot, and
# a status of the machine that is not 0 fails it even when the archive says ok.
for variant in "no ok" "ok and a failing machine"; do
    fresh
    plan 1
    send 1 ok ""
    send 1 second-boot ""
    send 1 first "written in boot one"
    case "${variant}" in
    "no ok") plan 2 ;;
    *) plan 2 124; send 2 ok "" ;;
    esac
    send 2 log.txt "phase two"
    run
    [ "${status}" -ne 0 ] || fail "a second boot with ${variant} passed"
    [ "${boots}" -eq 2 ] || fail "a second boot with ${variant}: ${boots} machines ran"
    case "${err}" in
    *"console of boot 2"*) ;;
    *) fail "a second boot with ${variant}: its console is not shown" ;;
    esac
    [ "${out}" = "phase two" ] || fail "a second boot with ${variant}: its log is not shown"
    [ ! -e "${work}/results/first" ] || fail "a second boot with ${variant}: a result went into the result folder"
    [ -z "${left}" ] || fail "a second boot with ${variant}: vm.sh left ${left} behind"
done
echo "ok - a second boot that does not finish fails the run and shows its own console"
