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

There are two kinds of image. Tool images hold what a build, check or test needs to run: a
toolchain, package build tools, QEMU, a prepared FreeBSD disk. Server images are the systems
the SpliceFS packages are installed into: each one is a vendor system as a server that is up
and running. None of the images is meant for running SpliceFS in production.

## Images

### Tool images

| Image | Contents | Used by |
| --- | --- | --- |
| [`go`](images/go) | Ubuntu 26.04 plus Go 1.27, gcc, golangci-lint, ShellCheck, git, make, FUSE, curl, xz, zstd, GnuPG, OpenSSL and apt-utils; runs as a user that is not root | Go builds, checks and lint runs of the SpliceFS repositories |
| [`rpm-build`](images/rpm-build) | Rocky Linux 9 plus rpmbuild, rpmsign, createrepo_c and GnuPG | Building and signing rpm packages and rpm repositories |
| [`apk-build`](images/apk-build) | Alpine Linux 3.22 plus abuild | Building and signing apk packages and apk repositories |
| [`go-qemu`](images/go-qemu) | The Go toolchain image plus QEMU for amd64 and arm64 guests, FUSE, curl, xz and zstd | FreeBSD machine tests of server, client and packages; `make check-linux` |
| [`freebsd-15.1`](images/freebsd-15.1) | A FreeBSD 15.1 disk that is already set up, with QEMU to boot it (amd64 only) | FreeBSD jobs of server, client and packages |
| [`freebsd-14.5`](images/freebsd-14.5) | A FreeBSD 14.5 disk that is already set up, with QEMU to boot it (amd64 only) | FreeBSD jobs of server, client and packages |

### Server images

Each server image is the vendor image of one system brought up to the vendor's own minimal
server install, with the service manager started as process 1. They are used by the install,
upgrade, remove and service tests of the SpliceFS packages.

| Image | System | Service manager | Package format |
| --- | --- | --- | --- |
| [`server-debian-12`](images/server-debian-12) | Debian 12 | systemd | deb |
| [`server-debian-13`](images/server-debian-13) | Debian 13 | systemd | deb |
| [`server-ubuntu-22.04`](images/server-ubuntu-22.04) | Ubuntu 22.04 | systemd | deb |
| [`server-ubuntu-24.04`](images/server-ubuntu-24.04) | Ubuntu 24.04 | systemd | deb |
| [`server-ubuntu-26.04`](images/server-ubuntu-26.04) | Ubuntu 26.04 | systemd | deb |
| [`server-rocky-8`](images/server-rocky-8) | Rocky Linux 8 | systemd | rpm |
| [`server-rocky-9`](images/server-rocky-9) | Rocky Linux 9 | systemd | rpm |
| [`server-rocky-10`](images/server-rocky-10) | Rocky Linux 10 | systemd | rpm |
| [`server-amazonlinux-2023`](images/server-amazonlinux-2023) | Amazon Linux 2023 | systemd | rpm |
| [`server-opensuse-leap-16.0`](images/server-opensuse-leap-16.0) | openSUSE Leap 16.0 | systemd | rpm |
| [`server-alpine-3.22`](images/server-alpine-3.22) | Alpine 3.22 | OpenRC | apk |
| [`server-alpine-3.23`](images/server-alpine-3.23) | Alpine 3.23 | OpenRC | apk |
| [`server-alpine-3.24`](images/server-alpine-3.24) | Alpine 3.24 | OpenRC | apk |

## What a server image is

A package test is only worth something on a system that looks like a server a user deploys:
the vendor's system, installed, with its service manager running as process 1, and nothing of
ours in it. The vendor's container images are not that. They are cut far below a server: most
have no service manager, and Debian and Ubuntu carry a file that stops packages from starting
services. A server image installs the set that the vendor's own installer puts on a minimal
server, and the set is read from the vendor, not listed here:

| System | The vendor's minimal set that the image installs |
| --- | --- |
| Debian | every package of priority `required` or `important`, plus `systemd-sysv`, read from the archive at build time |
| Ubuntu | the metapackage `ubuntu-server-minimal` |
| Rocky Linux | the group `core` |
| Amazon Linux | the group `base-minimal` (the group `core` is five packages that the vendor image has already) |
| openSUSE Leap | the patterns `base` and `minimal_base` (`minimal_base` alone is already in the vendor image and has no service manager) |
| Alpine | the package `alpine-base`, which brings OpenRC |

The images also hold:

- `ca-certificates`, which every server has.
- An empty `/etc/machine-id` on the systemd images, as vendors' images ship it, so that
  every container made from an image chooses its own machine id when it boots.

Where a container image differs from a server, the image follows the server: on Debian and
Ubuntu `/usr/sbin/policy-rc.d` is removed, and the full `coreutils` and `curl` replace the
minimal ones of the Rocky Linux and Amazon Linux images. The one setting made only for the
container is on Alpine, where OpenRC is told it runs in a container (`rc_sys="docker"`).

Recommended and weak dependencies follow the vendor's installer: left out on Debian, Ubuntu and
Amazon Linux, installed on Rocky Linux and openSUSE.

`fuse3` is not added. The SpliceFS packages pull in `fuse3` themselves when they are
installed, and a test of the install has to see that happen. The vendor's set decides the
rest: the Ubuntu set brings `fuse3` in through `snapd`, so a test on the Ubuntu images does not
see that happen. Nothing of this repository stays in an image: the setup script is mounted for
the one build step that runs it.

Some units of a vendor's set cannot work inside a container, for example `auditd` on Rocky
Linux and Amazon Linux, so `systemctl is-system-running` prints `degraded` there. Details are
in the README of each image.

### Boot a server image

A systemd image is started the way a container with systemd as process 1 is started. These
are the flags the SpliceFS service tests use:

    docker run -d --name server --privileged --cgroupns=host --tmpfs /run --tmpfs /run/lock --tmpfs /tmp ghcr.io/splicefs/server-debian-13:v1
    docker exec server systemctl is-system-running

- `--privileged` lets systemd manage its cgroups and mounts.
- `--cgroupns=host` gives it the cgroup view of the host, so it manages cgroups the same way
  on every host.
- `--tmpfs /run`, `--tmpfs /run/lock` and `--tmpfs /tmp` give it the memory file systems it
  expects there.

The image itself sets `container=docker`, so systemd knows it runs in a container, and the
stop signal `SIGRTMIN+3`, so that `docker stop` shuts systemd down cleanly. `is-system-running`
prints `running`, or `degraded` when a unit of the system cannot work inside a container.

An Alpine image needs no flags. The image sets the stop signal `SIGUSR2` for it, and the
flags above do no harm:

    docker run -d --name server ghcr.io/splicefs/server-alpine-3.24:v1
    docker exec server rc-status

Each `test.sh` checks the files of its image and runs inside the image without booting it.
Booting is what the commands above do.

## Pull an image

```sh
docker pull ghcr.io/splicefs/go-qemu:v1
```

An image is published for amd64 and arm64, unless its folder holds a file `arch` that
lists fewer CPU types. `freebsd-15.1` and `freebsd-14.5` are amd64 only. Docker picks the
one that matches your machine. The server images are published for both.

## Versions

Every image has a version: `v1`, `v2`, `v3` and so on. It is the one line of the file
`version` in the folder of the image, and the image is published as
`ghcr.io/splicefs/<image>:<version>`. There is no `latest` tag and there are no dated tags.

- A published version never changes. Any change to an image is published as the next
  version, never over an old one.
- Old versions stay available, so several versions of an image can be in use at the same
  time.
- A repository that uses an image pins the exact version it needs, and moves to a newer
  version when it chooses to. An image that is built on another image of this repository
  does the same: its `FROM` line names the version of the base, as in
  `FROM ghcr.io/splicefs/go-qemu:v1`.

To change an image: edit its folder, raise the number in its `version` file, and merge the
pull request. The merge publishes the new version. The old versions stay as they are, and
the repositories that use the image keep the version they pin until they change it.

## When images are built

An image is built only when its folder under `images/` changes, or when somebody starts the
Build workflow by hand. Nothing is rebuilt on a timer.

- A pull request builds the changed images for each of their CPU types and publishes
  nothing. It fails when a changed image does not have a greater version than it had where
  the branch started.
- A merge into `main` builds the changed images again and publishes each one under its
  version.
- The Build workflow can be started by hand from the Actions tab, for one image or for all.
  A manual run publishes too, but a version that is already published is never published
  again: that image fails with an error, and a change needs a new version.

The gap this leaves: a published version holds the base image and the package versions of
the day it was built, and never gets newer ones. An image only gets new base packages with
a new version. Raise the number in its `version` file, with or without another change, and
merge.

To add an image, see [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT. See `LICENSE`.
