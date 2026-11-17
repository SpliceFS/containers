# SpliceFS images

[![Build](https://github.com/SpliceFS/images/actions/workflows/build.yml/badge.svg)](https://github.com/SpliceFS/images/actions/workflows/build.yml)
[![Security](https://github.com/SpliceFS/images/actions/workflows/security.yml/badge.svg)](https://github.com/SpliceFS/images/actions/workflows/security.yml)
[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/SpliceFS/images/badge)](https://scorecard.dev/viewer/?uri=github.com/SpliceFS/images)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Ready-made container images for the builds, checks and tests of [SpliceFS](https://splicefs.org).

The builds, checks and tests of the SpliceFS repositories run inside containers. Until now
each run started a stock image and installed the tools it needs into it: QEMU, a service
manager, package build tools. That took minutes on every run. This repository defines
images that already have those tools in them. A workflow builds them and publishes them to
the GitHub container registry as `ghcr.io/splicefs/<image>:<version>`.

The images are tools for the SpliceFS repositories. They are not meant for running
SpliceFS itself.

## Images

| Image | Contents | Used by |
| --- | --- | --- |
| [`go`](images/go) | Ubuntu 26.04 plus Go 1.27, gcc, golangci-lint, ShellCheck, git, make, FUSE, curl, xz, zstd, GnuPG, OpenSSL and apt-utils; runs as a user that is not root | Go builds, checks and lint runs of the SpliceFS repositories |
| [`rpm-build`](images/rpm-build) | Rocky Linux 9 plus rpmbuild, rpmsign, createrepo_c and GnuPG | Building and signing rpm packages and rpm repositories |
| [`apk-build`](images/apk-build) | Alpine Linux 3.22 plus abuild | Building and signing apk packages and apk repositories |
| [`go-qemu`](images/go-qemu) | The Go toolchain image plus QEMU for amd64 and arm64 guests, FUSE, curl, xz and zstd | FreeBSD machine tests of server, client and packages; `make check-linux` |
| [`freebsd-15.1`](images/freebsd-15.1) | A FreeBSD 15.1 disk that is already set up, with QEMU to boot it (amd64 only) | FreeBSD jobs of server, client and packages |
| [`freebsd-14.5`](images/freebsd-14.5) | A FreeBSD 14.5 disk that is already set up, with QEMU to boot it (amd64 only) | FreeBSD jobs of server, client and packages |

## Pull an image

```sh
docker pull ghcr.io/splicefs/go-qemu:v1
```

An image is published for amd64 and arm64, unless its folder holds a file `arch` that
lists fewer CPU types. `freebsd-15.1` and `freebsd-14.5` are amd64 only. Docker picks the
one that matches your machine.

## Versions

Every image has a version `vMAJOR.MINOR.PATCH`, as in `v1.0.0`: three whole numbers
without a leading zero. It is the one line of the file `version` in the folder of the
image. There is no `latest` tag and there are no dated tags.

Publishing `vX.Y.Z` makes three tags, all pointing at the same image:

| Tag | Holds | Moves when |
| --- | --- | --- |
| `vX.Y.Z` | one exact release | never |
| `vX.Y` | the newest release of that minor version | a patch release of it is published |
| `vX` | the newest release of that major version | a patch or minor release of it is published |

- A full version is published once and never changes. Any change to an image is published
  as a greater version, never over an old one.
- Old versions stay available, so several versions of an image can be in use at the same
  time.
- The pull request check lets the version of an image only grow, so the version that is
  published is always the newest of its minor and major version, and `vX.Y` and `vX` only
  ever move forward.

### Which tag to use

- Testing images (`go-qemu`, `freebsd-15.1`, `freebsd-14.5`): name the major version, as in
  `go-qemu:v1`. Fixes and new tools reach the repository without a change of its own.
- Server images (folders named `server-*`): name the major and minor version, as in
  `server-debian-12:v1.0`. Fixes reach the repository, and a new tool, which is a minor
  release, is taken only when the repository moves to the next minor version.
- An image that is built on another image of this repository names its base the same way in
  its `FROM` line, as in `FROM ghcr.io/splicefs/go-qemu:v1`.
- A repository that needs a build that cannot change names the full version.

### Change an image

Edit its folder and raise the version in its `version` file by one step. Choose the step by
what the change does to the people who use the image:

- Patch (`v1.0.0` to `v1.0.1`): a fix, or newer base packages with no other change.
- Minor (`v1.0.1` to `v1.1.0`): a new tool or another addition. Nothing that worked stops
  working.
- Major (`v1.1.0` to `v2.0.0`): a breaking change, such as a tool that is removed or
  behaves differently.

A new image starts at `v1.0.0`. The merge publishes the new version, moves `vX.Y` and `vX`
to it, and leaves the old full versions as they are.

## When images are built

An image is built only when its folder under `images/` changes, or when somebody starts the
Build workflow by hand. Nothing is rebuilt on a timer.

- A pull request builds the changed images for each of their CPU types and publishes
  nothing. It fails when a changed image does not have a greater version than it had where
  the branch started. Versions are compared as numbers, by major, then minor, then patch.
- A merge into `main` builds the changed images again and publishes each one under its
  full version, and moves its minor and major tags to it.
- The Build workflow can be started by hand from the Actions tab, for one image or for all.
  A manual run publishes too, but a full version that is already published is never
  published again: that image fails with an error, and a change needs a new version.

The gap this leaves: a published version holds the base image and the package versions of
the day it was built, and never gets newer ones. An image only gets new base packages with
a new version. Raise the patch number in its `version` file, with or without another
change, and merge.

To add an image, see [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT. See `LICENSE`.
