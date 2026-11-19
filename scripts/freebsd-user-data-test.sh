#!/bin/sh
# Tests the boot script template of the FreeBSD images (images/freebsd-15.1/user-data.in, the
# other releases hold the same file) with its machine commands replaced by stubs and its
# paths moved into a throwaway folder. Run from anywhere:
#   sh scripts/freebsd-user-data-test.sh
#
# What it proves: the job output reaches the console while the job still runs, so that a job
# that is killed from outside leaves its last lines there; the same output is in log.txt;
# nothing reaches the console twice; the exit status of the job alone decides "ok"; and
# nothing left in the result folder or the status file by an earlier boot reaches the caller
# or survives the boot (FreeBSD keeps /tmp across boots).
set -eu

case "$0" in
*/*) here="${0%/*}" ;;
*) here="." ;;
esac
template="$(cd "${here}/.." && pwd)/images/freebsd-15.1/user-data.in"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
trap 'exit 1' HUP INT TERM

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

# The machine commands do nothing here: the folders are plain ones and there is no disk. The
# tar stub keeps a copy of what the machine would send back (tar cf <disk> -C <folder> .) in
# ${work}/sent, because that, not the folder after the boot, is what the caller gets.
mkdir -p "${work}/stubs"
for command in mount shutdown; do
    printf '#!/bin/sh\nexit 0\n' >"${work}/stubs/${command}"
    chmod 755 "${work}/stubs/${command}"
done
cat >"${work}/stubs/tar" <<STUB
#!/bin/sh
rm -rf "${work}/sent"
mkdir -p "${work}/sent"
cp -R "\$4"/. "${work}/sent"/
STUB
chmod 755 "${work}/stubs/tar"

# render makes the boot script for the job script named job.sh, with every machine path
# moved under ${work}/tmp and the console moved to the file or pipe named by $1.
render() {
    # The /tmp/ paths are moved first: the work folder itself can be under /tmp/ (it is on
    # Linux), and the console path that comes in after must not be moved again.
    sed -e "s|@JOB@|job.sh|" -e "s|@ARGS@||" \
        -e "s|/tmp/|${work}/tmp/|g" -e "s|/dev/console|$1|g" \
        "${template}" >"${work}/user-data"
}

# fresh makes the folders of a run, with the job script from stdin.
fresh() {
    rm -rf "${work}/tmp" "${work}/sent"
    mkdir -p "${work}/tmp/in"
    cat >"${work}/tmp/in/job.sh"
}

start() {
    PATH="${work}/stubs:${PATH}" sh "${work}/user-data"
}

# A job that is stopped from outside stands still on a pipe. The console is a pipe too, so
# the test reads it as a machine's console would be read: a line is there or it is not.
mkfifo "${work}/console" "${work}/gate"
fresh <<JOB
echo first
read -r release <"${work}/gate"
echo second >&2
JOB
render "${work}/console"

# Only a failing test waits for the watchdog: it frees the job and the reader of the console
# (which waits for a writer when the job never opens the console), and the flag fails the test.
(
    sleep 30
    : >"${work}/timed-out"
    echo timed-out >"${work}/console" &
    echo go >"${work}/gate"
) >/dev/null 2>&1 &
watchdog=$!

start >/dev/null 2>&1 &
boot=$!
exec 3<"${work}/console"
read -r line <&3
if [ "${line}" != first ]; then
    fail "the first console line is \"${line}\", wanted \"first\""
fi
if [ -f "${work}/timed-out" ]; then
    fail "the console got no line while the job was still running"
fi
echo go >"${work}/gate"
read -r line <&3
if [ "${line}" != second ]; then
    fail "the second console line is \"${line}\", wanted \"second\""
fi
if read -r line <&3; then
    fail "the console got \"${line}\" after the job output, so a line came twice"
fi
exec 3<&-
wait "${boot}"
kill "${watchdog}" 2>/dev/null || true
echo "ok - the job output is on the console while the job runs, once"

logged="$(cat "${work}/sent/log.txt")"
if [ "${logged}" != "first
second" ]; then
    fail "log.txt does not hold the standard output and the error output of the job"
fi
echo "ok - log.txt holds both streams of the job"

if [ ! -f "${work}/sent/ok" ]; then
    fail "a job that exits with 0 left no ok file"
fi
echo "ok - a job that exits with 0 leaves the ok file"

# The pipe to the console must not decide the result: the status is the job's own.
for code in 1 3; do
    fresh <<JOB
echo failing
exit ${code}
JOB
    render "${work}/console-file"
    start >/dev/null 2>&1
    if [ -f "${work}/sent/ok" ]; then
        fail "a job that exits with ${code} left the ok file"
    fi
    shown="$(cat "${work}/console-file")"
    if [ "${shown}" != failing ]; then
        fail "the console of the failing job does not hold its output"
    fi
    echo "ok - a job that exits with ${code} leaves no ok file"
done

# The result folder goes back to the caller as it is, so nothing else may be put in it.
for file in "${work}/sent"/*; do
    if [ "${file}" != "${work}/sent/log.txt" ]; then
        fail "the result folder holds ${file}, which would go back to the caller"
    fi
done
echo "ok - the result folder holds only log.txt"

# The disk of the image was booted once to prepare it, and FreeBSD keeps /tmp across boots,
# so a later boot can find the result folder and the status file of an earlier one. A stale
# ok must not make a failing job pass, and nothing stale may go back to the caller.
fresh <<JOB
exit 1
JOB
mkdir -p "${work}/tmp/out"
: >"${work}/tmp/out/ok"
: >"${work}/tmp/out/stale"
echo 0 >"${work}/tmp/status"
render "${work}/console-file"
start >/dev/null 2>&1
if [ -f "${work}/sent/ok" ]; then
    fail "an ok file left by an earlier boot made a failing job pass"
fi
if [ -f "${work}/sent/stale" ]; then
    fail "a file left by an earlier boot went back to the caller"
fi
echo "ok - nothing an earlier boot left in the result folder reaches the caller"

# The boot leaves nothing behind for the next one, so the disk made by the preparation boot
# ships without a result folder or a status file.
if [ -e "${work}/tmp/out" ] || [ -e "${work}/tmp/status" ]; then
    fail "the boot left its result folder or its status file on the disk"
fi
echo "ok - the boot removes its result folder and its status file"
