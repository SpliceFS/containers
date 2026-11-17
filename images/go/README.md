# go

Ubuntu 26.04 (`ubuntu:26.04`) with the Go toolchain and the tools that the builds and
checks of the SpliceFS repositories need:

- Go 1.27.4, the official release archive from go.dev for the CPU type of the image. The version and its sha256 checksums are `ARG`s in the `Dockerfile`, taken from the list at https://go.dev/dl/?mode=json, and the build stops unless the download matches the checksum.
- gcc and libc6-dev, which cgo and `go test -race` need (`CGO_ENABLED` is 1)
- golangci-lint, in the release that the CI of the SpliceFS repositories uses (`ARG GOLANGCI_LINT_VERSION` in the `Dockerfile`). It is the official binary for the CPU type of the image, and the build stops unless it matches the checksum file of the same release.
- ShellCheck, git and make
- FUSE (`fusermount3`), for the Linux checks that mount a file system
- curl, xz and zstd
- GnuPG (`gpg`) and OpenSSL, for signing and checking files
- apt-utils (`apt-ftparchive`) and `dpkg-deb`, for building deb packages and apt repositories

Not for testing the SpliceFS packages: those tests start the systems that the packages
are made for. This image is for building and checking the code and the packages.
Pull it with `docker pull ghcr.io/splicefs/go:<version>`, where the version is the one
line of the file `version` in this folder. `test.sh` checks the tools inside the image.

## Who it runs as

The image does not run as root. It starts as the user `build` (uid 1000, home
`/home/build`). Three ways to run it:

```sh
# 1. As the default user.
docker run --rm ghcr.io/splicefs/go:v1 go version

# 2. As your own user, so that the files that the container writes into a mounted
#    folder belong to you. Any uid and gid work, for example 501:20 on macOS or
#    1001:127 on a GitHub runner. Use "$(id -u):$(id -g)" for yours.
docker run --rm --user "$(id -u):$(id -g)" -v "$PWD":/src -w /src \
    -v gomod:/go/pkg/mod ghcr.io/splicefs/go:v1 go test -race ./...

# 3. As root, for a job that has to mount FUSE or NFS inside the container.
docker run --rm --user 0 --privileged ghcr.io/splicefs/go:v1 id
```

A user that is not in `/etc/passwd` works because no setting depends on the user entry:

- `HOME` is set to `/home/build` in the image. Without it Docker would give such a user `/` as its home.
- `/home/build`, `/go/bin`, `/go/pkg/mod` (`GOMODCACHE`) and `/go/cache` (`GOCACHE`) have mode 1777: every user may create files there, and only the owner may remove them, like `/tmp`.
- A named volume that is empty gets the mode of the folder it is mounted on, so a volume mounted at `/go/pkg/mod` or `/go/cache` is writable by any user too.

This is done with environment settings and folder modes, not with an entrypoint script,
so `docker run --user ... <image> <command>` runs the command itself.

Things to know:

- A cache volume belongs to the user that first filled it. Use one volume per user. A volume that a root run filled, with this image or another, gives "permission denied" on cache writes to any other user, so start a new volume for a new user.
- As root in a folder of a git checkout that another user owns, git refuses to work ("dubious ownership"), and `go build` of a main package then stops with "error obtaining VCS status". Copy the source first, or build with `-buildvcs=false`.

Raise the version of the image when you change the Go release, the checksums, or
golangci-lint.
