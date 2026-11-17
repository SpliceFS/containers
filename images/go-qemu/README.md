# go-qemu

The Go toolchain image (`golang`) plus the tools the SpliceFS machine tests need:

- QEMU for amd64 and arm64 guests (`qemu-system-x86` on amd64, `qemu-system-arm` and `qemu-efi-aarch64` on arm64, `qemu-utils` on both)
- FUSE (`fuse3`), curl, xz and zstd (zstd reads the FreeBSD package catalog in the release order check)

Used by the FreeBSD machine tests of the server, the client and the packages.
Pull it with `docker pull ghcr.io/splicefs/go-qemu:v1`. The tag `v1` follows every release
of major version 1; `v1.0` and `v1.0.0` name a minor version and one exact release. The
file `version` in this folder holds the exact one. `test.sh` checks the tools inside the
image.
