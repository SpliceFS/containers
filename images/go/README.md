# go

The Go toolchain image (`golang`) plus the tools that the builds and checks of the
SpliceFS repositories need:

- golangci-lint, in the release that the CI of the SpliceFS repositories uses (`ARG GOLANGCI_LINT_VERSION` in the `Dockerfile`). It is the official binary for the CPU type of the image, and the build stops unless it matches the checksum file of the same release.
- ShellCheck, git and make
- FUSE (`fusermount3`), for the Linux checks that mount a file system
- curl, xz and zstd
- GnuPG (`gpg`) and OpenSSL, for signing and checking files
- apt-utils (`apt-ftparchive`), for building apt repositories

Not for testing the SpliceFS packages: those tests start the systems that the packages
are made for. This image is for building and checking the code and the packages.
Pull it with `docker pull ghcr.io/splicefs/go:<version>`, where the version is the one
line of the file `version` in this folder. `test.sh` checks the tools inside the image.

To use another golangci-lint release, change the `Dockerfile` and raise the version of the
image.
