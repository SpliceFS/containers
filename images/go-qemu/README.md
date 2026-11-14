# go-qemu

The Go toolchain image (`golang`) plus the tools the SpliceFS machine tests need:

- QEMU for amd64 and arm64 guests (`qemu-system-x86` on amd64, `qemu-system-arm` and `qemu-efi-aarch64` on arm64, `qemu-utils` on both)
- FUSE (`fuse3`), curl and xz

Used by the FreeBSD machine tests of the server, the client and the packages.
Pull it with `docker pull ghcr.io/splicefs/go-qemu:latest`. `test.sh` checks the tools inside the image.
