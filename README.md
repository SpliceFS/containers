# SpliceFS containers

[![Build](https://github.com/SpliceFS/containers/actions/workflows/build.yml/badge.svg)](https://github.com/SpliceFS/containers/actions/workflows/build.yml)
[![Security](https://github.com/SpliceFS/containers/actions/workflows/security.yml/badge.svg)](https://github.com/SpliceFS/containers/actions/workflows/security.yml)
[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/SpliceFS/containers/badge)](https://scorecard.dev/viewer/?uri=github.com/SpliceFS/containers)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Ready-made container images for the tests of [SpliceFS](https://splicefs.org).

The tests of the SpliceFS repositories run inside containers. Until now each run started a
stock image and installed the tools the tests need into it: QEMU, a service manager,
package build tools. That took minutes on every run. This repository defines images that
already have those tools in them. A workflow builds them and publishes them to the GitHub
container registry as `ghcr.io/splicefs/<image>`.

The images are test tools for the SpliceFS repositories. They are not meant for running
SpliceFS itself.

## Images

| Image | Contents | Used by |
| --- | --- | --- |
| [`go-qemu`](images/go-qemu) | The Go toolchain image plus QEMU for amd64 and arm64 guests, FUSE, curl and xz | FreeBSD machine tests of server, client and packages |

## Pull an image

```sh
docker pull ghcr.io/splicefs/go-qemu:latest
```

Every image is published for amd64 and arm64. Docker picks the one that matches your
machine.

## Tags

- `latest` is the newest build of the image.
- One tag per build is made of the date and the short commit, for example
  `2026-11-14-1a2b3c4`. Use it to pin a test to a known build.

## When images are built

An image is built only when its folder under `images/` changes, or when somebody starts the
Build workflow by hand. Nothing is rebuilt on a timer.

- A pull request builds the changed images for amd64 and arm64 and publishes nothing.
- A merge into `main` builds the changed images again and publishes them.
- The Build workflow can be started by hand from the Actions tab, for one image or for all.
  A manual run publishes.

The gap this leaves: an image does not pick up a new base image or new package versions
until its folder changes or someone runs the Build workflow by hand.

To add an image, see [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT. See `LICENSE`.
