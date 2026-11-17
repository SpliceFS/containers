# go-qemu

The [`go`](../go) image plus the tools the SpliceFS machine tests need:

- QEMU for amd64 and arm64 guests (`qemu-system-x86` on amd64, `qemu-system-arm` and `qemu-efi-aarch64` on arm64, `qemu-utils` on both)
- everything the `go` image has: the Go toolchain, gcc, golangci-lint, ShellCheck, git, make, FUSE (`fuse3`), curl, xz, zstd, GnuPG, OpenSSL and apt-utils

Used by the FreeBSD machine tests of the server, the client and the packages, and by the
Linux checks. It is the base of the `freebsd-*` images.
Pull it with `docker pull ghcr.io/splicefs/go-qemu:v2`. The tag `v2` follows every release
of major version 2; `v2.0` and `v2.0.0` name a minor version and one exact release. The
file `version` in this folder holds the exact one. `test.sh` checks the tools inside the
image.

## Who it runs as

The image is built on the `go` image and runs the way that image does: as the user `build`
(uid 1000, home `/tmp`), not as root. Everything in the README of `go` about running it as
another user, and about the caches in `/tmp`, holds here too. Version 1 of this image was
the `golang` image and ran as root, so the change of the default user is why this is
version 2.

QEMU starts as any user. Only hardware virtualization is different: it needs the device
`/dev/kvm`, which is owned by root and by the group `kvm` of the host, and the user `build`
is in neither. Without access to the device QEMU still runs, but it emulates the CPU and is
many times slower. A run that boots a machine gives the container the device and one of
two ways to use it:

```sh
# As root. The files that the container writes into a mounted folder then belong to root.
docker run --rm --user 0 --device /dev/kvm ghcr.io/splicefs/go-qemu:v2 qemu-system-x86_64 --version

# As the default user, in the group that owns /dev/kvm on the host.
docker run --rm --device /dev/kvm --group-add "$(stat -c %g /dev/kvm)" \
    ghcr.io/splicefs/go-qemu:v2 qemu-system-x86_64 --version
```

`stat -c %g /dev/kvm` prints the numeric id of that group, which is not the same on every
host, and the container needs no entry for it in `/etc/group`. The device is there only on a
Linux host with hardware virtualization.

`test.sh` runs as the default user and checks that it is not root. To prove the root mode,
run it with `--user 0 -e EXPECT_ROOT=1`.
