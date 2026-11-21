# freebsd-15.1

The `go-qemu` image plus one file: `/freebsd/disk.qcow2`, a FreeBSD 15.1 disk that is
already set up (about 1.7 GB, compressed). The package tool works on it, and a job runs on
every boot. A test that boots it does the job itself and skips the minute the official
disk spends on its first boot (base system updates, growing its filesystem, first-boot
scripts).

The disk is the official FreeBSD 15.1 release image, booted once with the package tool
(`pkg`) bootstrapped, and a boot hook (`/etc/rc.local`) that runs a test job from a disk
labelled `cidata` on every boot. Nothing of SpliceFS is on it. It serves the FreeBSD tests of
the server, the client and the packages, and it is the FreeBSD server that the package tests
install the packages into.

For amd64 only. FreeBSD is tested on amd64 only, and on an arm64 machine this image
would be emulated. The folder has an `arch` file that says so.

Used by the FreeBSD jobs of the server, the client and the packages, and by the package
tests as their FreeBSD server.
Pull it with `docker pull ghcr.io/splicefs/freebsd-15.1:v2`. The tag `v2` follows every
release of major version 2; `v2.0` and `v2.0.0` name a minor version and one exact
release. The file `version` in this folder holds the exact one.

## Who it runs as

The image runs as root, unlike the `go-qemu` image it is built on, which runs as a user that
is not root. The machine needs `/dev/kvm` for hardware virtualization, and only root and
the group of that device can open it. Because the image runs as root, a run only has to
pass the device to the container:

    docker run --rm --device /dev/kvm ghcr.io/splicefs/freebsd-15.1:v2 /freebsd/vm.sh ...

`prepare.sh` runs the preparation in the `go-qemu` image with `--user 0` for the same reason.

## Files in the image

- `/freebsd/disk.qcow2`: the prepared disk.
- `/freebsd/vm.sh`: the machine runner. QEMU comes from the `go-qemu` image.
- `/freebsd/user-data.in`: the template of the file that FreeBSD runs on boot.
- `/freebsd/second-boot.in`: the template of a one-shot rc.d script, for a job that needs a
  second boot.
- `/freebsd/official`: the line of the official disk this one was made from. Its first
  field is the FreeBSD release.

## How a test uses it

A test makes a job folder and runs the machine on it:

- `user-data`: made from `/freebsd/user-data.in` with `sed`, which puts the name of the
  job script where `@JOB@` is and its arguments where `@ARGS@` is.
- The job script itself. It runs as root inside FreeBSD with the job folder and an output
  folder as its first two arguments, and what it leaves in the output folder comes back.
- `meta-data`: two lines, `instance-id: <name>` and `local-hostname: build`, as in the job
  folders of the client.

Then:

    /freebsd/vm.sh amd64 /freebsd/disk.qcow2 <job folder> <result folder> [input archive]

The machine writes the job output to the standard output and everything the job left in
its output folder to the result folder. The job output also goes to the machine console
while the job runs, and `vm.sh` keeps the console in the result folder as
`console-<job folder name>-<arch>.log`. When a run is stopped by `VM_TIMEOUT`, `vm.sh` prints
the last 100 lines of the console, which end with the last lines the job wrote. The disk is never written to: each run works on a
copy-on-write layer, which `vm.sh` removes when the run ends. `VM_TIMEOUT` (default 900) is the longest run in seconds. Pass
`--device /dev/kvm` to `docker run` when the computer has it; without it the machine is
emulated and much slower. `test.sh` is a complete small example.

A job that needs the machine to boot a second time (to prove what a restart does) creates the
file `second-boot` in its result folder and installs the one-shot script `second-boot.in`
with a file to run; `user-data.in` shows the lines. When the first boot has powered off,
`vm.sh` boots the same disk again with the same scratch disk, and no job disk, so that the
job does not run twice. The script of the second boot runs the file, adds its output to the
log and its files to the results of the first boot, and powers off. `VM_TIMEOUT` applies to
each boot, and the console of the second boot is kept as
`console-<job folder name>-<arch>-second-boot.log`. A job that does not create the file
`second-boot` runs one boot, as before. `test.sh` has an example.

The disk is a snapshot of the day the image was built, so it does not get later FreeBSD
patches until the image gets a new version.

## How it is built

The disk cannot be made by `docker build`, because making it means booting FreeBSD. The
build workflow therefore runs `prepare.sh amd64` on the runner first. That script
downloads the official image named in `official`, refuses it when its SHA-256 checksum
differs, and runs `prepare-disk.sh` inside `go-qemu`. `prepare-disk.sh` boots the official
disk once with `prepare-job.sh`, which sets up the package tool, and writes the result as
a compressed standalone disk, `disk.qcow2` (not committed to git). Then the Dockerfile
copies it into the image.

The image is built only when this folder changes, or when somebody starts the Build
workflow by hand with the image name `freebsd-15.1`. A change to the folder comes with a
greater version in `version`, and the image is published under that version. A published
version never changes.

Each FreeBSD release has a folder of its own, and the folders are copies on purpose: the
build of an image sees only its own folder. Every file except `official`, `README.md` and
`version` is identical in all of them, and `scripts/same-files.sh` checks that. To add a
release, copy a folder, change `official` and `README.md`, set `version` to `v1.0.0`, and leave
the other files alone.
