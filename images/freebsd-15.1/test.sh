#!/bin/sh
# Checks the FreeBSD disk of the image. The build workflow runs this inside the image, so
# that a broken disk is not published. It boots the disk once with a job that reports the
# FreeBSD release and whether the package tool is set up.
set -eu

disk=/freebsd/disk.qcow2

qemu-img check "${disk}"
echo "ok: ${disk} is a valid qcow2 file"

# The job folder is made like the folder of any test: the file user-data from the template
# runs the job script, and the machine reads both as the disk labelled cidata.
work="$(mktemp -d)"
job="${work}/job"
mkdir -p "${job}"
cat > "${job}/job.sh" <<'JOB'
#!/bin/sh
echo "release: $(uname -r)"
if pkg -N >/dev/null 2>&1; then
    echo "pkg: set up"
else
    echo "pkg: not set up"
fi
JOB
sed -e "s|@JOB@|job.sh|" -e "s|@ARGS@||" /freebsd/user-data.in > "${job}/user-data"
printf 'instance-id: test-job\nlocal-hostname: test\n' > "${job}/meta-data"

# vm.sh prints the output of the job and stops the machine after VM_TIMEOUT seconds.
VM_TIMEOUT=300
export VM_TIMEOUT
start="$(date +%s)"
status=0
/freebsd/vm.sh amd64 "${disk}" "${job}" "${work}/results" > "${work}/output.txt" || status=$?
stop="$(date +%s)"
cat "${work}/output.txt"
echo "machine run: $((stop - start)) seconds"

if [ "${status}" -ne 0 ]; then
    echo "FAIL: the machine did not finish the job" >&2
    exit 1
fi
if ! grep -q '^release: 15\.1' "${work}/output.txt"; then
    echo "FAIL: the job output does not show FreeBSD 15.1" >&2
    exit 1
fi
if ! grep -q '^pkg: set up$' "${work}/output.txt"; then
    echo "FAIL: the package tool is not set up on the disk" >&2
    exit 1
fi
echo "ok: FreeBSD 15.1 with the package tool set up"
