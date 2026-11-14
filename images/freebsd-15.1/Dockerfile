# The newest go-qemu image on purpose: this image is that image plus one disk, and it is
# rebuilt by hand or when this folder changes, so it follows the QEMU of go-qemu from the
# day it is built.
# hadolint ignore=DL3007
FROM ghcr.io/splicefs/go-qemu:latest

# The source label links the published image to this repository on GitHub.
LABEL org.opencontainers.image.source="https://github.com/SpliceFS/containers" \
      org.opencontainers.image.description="The go-qemu image plus a FreeBSD 15.1 disk that is already set up, for the SpliceFS FreeBSD machine tests (amd64 only)" \
      org.opencontainers.image.licenses="MIT"

# The disk is made by prepare.sh before the build, because it takes a booted machine.
COPY disk.qcow2 /freebsd/disk.qcow2
# The machine runner and the template of the job file, so that every test boots the disk
# the same way.
COPY vm.sh user-data.in /freebsd/
