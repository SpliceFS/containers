# The major version of go-qemu: a minor or patch release of it reaches this image the next
# time this image is built. To move to a newer major version, change the number here and
# raise the version of this image. prepare.sh reads this line, so that the disk is made in
# the image that it is copied into.
FROM ghcr.io/splicefs/go-qemu:v2

# The source label links the published image to this repository on GitHub.
LABEL org.opencontainers.image.source="https://github.com/SpliceFS/images" \
      org.opencontainers.image.description="The go-qemu image plus a FreeBSD disk that is already set up; the release is in /freebsd/official. For the SpliceFS FreeBSD machine tests (amd64 only). Runs as root, so that QEMU can use /dev/kvm" \
      org.opencontainers.image.licenses="MIT"

# The go-qemu image runs as a user that is not root, and the machine of this image needs
# /dev/kvm for hardware virtualization, which that user cannot open. This image runs as
# root, as the go-qemu image did before version 2, so that a caller needs no flag for it.
USER root

# The disk is made by prepare.sh before the build, because it takes a booted machine.
COPY disk.qcow2 /freebsd/disk.qcow2
# The machine runner and the templates of the job file and of the one-shot script for a
# second boot, so that every test boots the disk the same way. The file official names the
# FreeBSD release of the disk, which is how test.sh knows what to expect and how a test can
# ask the image which release it holds.
COPY vm.sh user-data.in second-boot.in official /freebsd/
