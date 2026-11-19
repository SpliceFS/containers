# go

Ubuntu 26.04 (`ubuntu:26.04`) with the Go toolchain and the tools that the builds and
checks of the SpliceFS repositories need:

- Go 1.27.4, the official release archive from go.dev for the CPU type of the image. The version and its sha256 checksums are `ARG`s in the `Dockerfile`, taken from the list at https://go.dev/dl/?mode=json, and the build stops unless the download matches the checksum.
- gcc and libc6-dev, which cgo and `go test -race` need (`CGO_ENABLED` is 1)
- golangci-lint, in the release that the CI of the SpliceFS repositories uses (`ARG GOLANGCI_LINT_VERSION` in the `Dockerfile`). It is built from source during the image build, with the Go of the image (`go install` of that release, every module checked by the Go checksum database), and not taken from the release binaries. A linter built with an older Go than the image's cannot read the export data of the standard library, and then silently skips every rule that needs types, such as revive's `unhandled-error`. `test.sh` plants a dropped error and requires the linter to report it.
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

The image does not run as root. It starts as the user `build` (uid 1000, home `/tmp`).
Three ways to run it:

```sh
# 1. As the default user.
docker run --rm ghcr.io/splicefs/go:v1 go version

# 2. As your own user, so that the files that the container writes into a mounted
#    folder belong to you. Any uid and gid work, for example 501:20 on macOS or
#    1001:127 on a GitHub runner. Use "$(id -u):$(id -g)" for yours. The module cache
#    and the build cache then start empty in every container. To keep them, mount host
#    folders that you own over /tmp/go/pkg/mod and /tmp/go-cache.
mkdir -p "$HOME/.cache/splicefs-go/mod" "$HOME/.cache/splicefs-go/build"
docker run --rm --user "$(id -u):$(id -g)" -v "$PWD":/src -w /src \
    -v "$HOME/.cache/splicefs-go/mod":/tmp/go/pkg/mod \
    -v "$HOME/.cache/splicefs-go/build":/tmp/go-cache \
    ghcr.io/splicefs/go:v1 go test -race ./...

# 3. As root, for a job that has to mount FUSE or NFS inside the container.
docker run --rm --user 0 --privileged ghcr.io/splicefs/go:v1 id
```

A user that is not in `/etc/passwd` works because no setting depends on the user entry:

- `HOME` is `/tmp` in the image. Without it Docker would give such a user `/` as its home, where it cannot write.
- `GOPATH` is `/tmp/go`, so the module cache (`GOMODCACHE`) is `/tmp/go/pkg/mod`, and `GOCACHE` is `/tmp/go-cache`.
- `/tmp` is the folder that every Linux system lets all users write to, and only the owner of a file may remove it. The image changes the mode of no folder, so no folder of it is writable by everyone but `/tmp`; `test.sh` checks that.

This is done with environment settings, not with an entrypoint script, so
`docker run --user ... <image> <command>` runs the command itself.

Things to know:

- The tools of the image are in `/usr/local/bin` and `/usr/local/go/bin`, and `PATH` does not include `GOPATH/bin`. A tool that you `go install` is in `/tmp/go/bin`, and only for that container.
- To keep a cache between runs, mount a host folder that the user of the run owns, as in the example above. A named Docker volume is created owned by root, so a user that is not root cannot write to it: `go` stops with "permission denied". Docker also creates `/tmp/go` and `/tmp/go/pkg` owned by root when a folder is mounted at `/tmp/go/pkg/mod`, so `go install` then needs `-e GOBIN=/tmp/bin` or another folder in `/tmp`.
- A cache folder belongs to the user that first filled it. Use one folder per user. A folder that a root run filled, with this image or another, gives "permission denied" on cache writes to any other user, so start a new folder for a new user.
- As root in a folder of a git checkout that another user owns, git refuses to work ("dubious ownership"), and `go build` of a main package then stops with "error obtaining VCS status". Copy the source first, or build with `-buildvcs=false`.

Raise the version of the image when you change the Go release, the checksums, or
golangci-lint.
