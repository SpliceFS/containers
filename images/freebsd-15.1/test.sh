#!/bin/sh
# Checks the FreeBSD disk of the image. The build workflow runs this inside the image, so
# that a broken disk is not published. It boots the disk with a job that reports the FreeBSD
# release and whether the package tool is set up, and checks the release against the file
# official, so that this script is the same in the folder of every release. It boots it once
# more with a job that fails, which must make vm.sh fail: the disk was booted to prepare it,
# and nothing that boot left behind may pass for the result of a later job.
set -eu

disk=/freebsd/disk.qcow2
official=/freebsd/official

# The release is the first field of the line of official that is not a comment.
release="$(awk '$1 !~ /^#/ && NF > 0 { print $1; exit }' "${official}")"
if [ -z "${release}" ]; then
    echo "FAIL: ${official} names no release" >&2
    exit 1
fi

qemu-img check "${disk}"
echo "ok: ${disk} is a valid qcow2 file"

# The job folders are made like the folder of any test: the file user-data from the template
# runs the job script, and the machine reads both as the disk labelled cidata.
work="$(mktemp -d)"

# make_job NAME makes the job folder ${work}/NAME with the job script from stdin.
make_job() {
    mkdir -p "${work}/$1"
    cat > "${work}/$1/job.sh"
    sed -e "s|@JOB@|job.sh|" -e "s|@ARGS@||" /freebsd/user-data.in > "${work}/$1/user-data"
    printf 'instance-id: test-%s\nlocal-hostname: test\n' "$1" > "${work}/$1/meta-data"
}

make_job report <<'JOB'
#!/bin/sh
echo "release: $(uname -r)"
if pkg -N >/dev/null 2>&1; then
    echo "pkg: set up"
else
    echo "pkg: not set up"
fi
JOB
make_job failing <<'JOB'
#!/bin/sh
echo "this job fails"
exit 1
JOB

# vm.sh prints the output of the job and stops the machine after VM_TIMEOUT seconds.
VM_TIMEOUT=300
export VM_TIMEOUT

if /freebsd/vm.sh amd64 "${disk}" "${work}/failing" "${work}/failing-results" > "${work}/failing.txt"; then
    cat "${work}/failing.txt"
    echo "FAIL: vm.sh passed a job that exits with 1" >&2
    exit 1
fi
echo "ok: vm.sh fails when the job fails"

start="$(date +%s)"
status=0
/freebsd/vm.sh amd64 "${disk}" "${work}/report" "${work}/results" > "${work}/output.txt" || status=$?
stop="$(date +%s)"
cat "${work}/output.txt"
echo "machine run: $((stop - start)) seconds"

if [ "${status}" -ne 0 ]; then
    echo "FAIL: the machine did not finish the job" >&2
    exit 1
fi
# uname -r prints the release, then RELEASE and the patch level.
reported="$(sed -n 's/^release: //p' "${work}/output.txt")"
case "${reported}" in
"${release}"*) ;;
*)
    echo "FAIL: the machine reports FreeBSD \"${reported}\", official says ${release}" >&2
    exit 1
    ;;
esac
if ! grep -q '^pkg: set up$' "${work}/output.txt"; then
    echo "FAIL: the package tool is not set up on the disk" >&2
    exit 1
fi
echo "ok: FreeBSD ${release} with the package tool set up"
