# Contributing to SpliceFS images

This repository holds the definitions of the container images that the SpliceFS builds,
checks and tests run in, and the workflow that builds and publishes them.

## Before you start

Open an issue first for anything larger than a correction, so the approach can be agreed
before work is spent on it.

## Add an image

1. Make a folder `images/<name>/`. The folder name is the image name and must match
   `^[a-z0-9][a-z0-9.-]*$`.
2. Put a `Dockerfile` in it. It takes the build argument `TARGETARCH` (`amd64` or `arm64`)
   when the packages differ by CPU type, and fails with a clear message for any other value.
   Set the labels `org.opencontainers.image.source` (this links the published image to this
   repository, `https://github.com/SpliceFS/images`), `org.opencontainers.image.description`
   and `org.opencontainers.image.licenses`. An image built on another image of this
   repository names a version of it, as in `FROM ghcr.io/splicefs/go-qemu:v1` (`v1`,
   `v1.0` and `v1.0.0` are all allowed, see "Versions"), and never `latest` or a name
   without a version.
3. Put a file `version` in it that holds one line, `v1.0.0`. See "Versions" below.
4. Put a short `README.md` in it: what the image contains and which tests use it.
5. Optionally put an executable `test.sh` in it. When it exists, the workflow runs it inside
   the built image and the build fails if it fails. The test gets `/dev/kvm` when the
   runner has it, so it can boot a machine at full speed.
6. Optionally put a file `arch` in it: the CPU types the image is built for, one per line
   (`amd64`, `arm64`). Without the file the image is built for both. Any other word is an
   error.
7. Optionally put an executable `prepare.sh` in it, for an image that holds a file which can
   only be made by booting a machine, because `docker build` cannot do that with hardware
   help. The workflow runs `sh images/<name>/prepare.sh <arch>` on the runner, from the
   repository root, before `docker build`. The script may download and compute, and leaves
   its result inside `images/<name>/` for the Dockerfile to copy. Files it leaves behind
   are ignored by git (`images/*/disk.qcow2`, `images/*/work/`). The folders
   `images/freebsd-*` are copies of each other on purpose, because the build of an image sees
   only its own folder: every file except `official`, `README.md` and `version` must be
   identical in all of them, and `scripts/same-files.sh` fails when one differs.
8. Add the image to the table in the top-level `README.md`.
9. Open a pull request.

## Versions

Every image has a version, the one line of `images/<name>/version`: `v`, then the major,
minor and patch numbers separated by dots, as in `v1.0.0`. Each number is a whole number
without a leading zero, and zero itself is allowed. `scripts/image-version.sh <name>` prints
the version and refuses a malformed one. A new image starts at `v1.0.0`; any valid version
is accepted for a new image.

An image is published under its full version, `ghcr.io/splicefs/<name>:v1.2.3`, and the
same publish moves two more tags to it: `v1.2` and `v1`. There is no `latest` tag and there
are no dated tags.

- The full version is published once and never changes. The Build workflow checks the
  registry before it publishes, and stops with an error when the full version is already
  there.
- The tags `vX.Y` and `vX` always point at the newest release of their line. That is right
  because the pull request check lets the version of an image only grow, so the version
  published from `main` is always the newest of its minor and major version.
  `scripts/moving-tags.sh` names the tags a version moves.
- Old versions stay available.

How code refers to an image:

- A testing image (`go-qemu`, `freebsd-15.1`, `freebsd-14.5`) is referred to by its major
  version, as in `go-qemu:v1`. Patch and minor releases reach every user of `v1`.
- A server image (a folder named `server-*`) is referred to by its major and minor version,
  as in `server-debian-12:v1.0`. Patch releases reach every user of `v1.0`. A minor
  release reaches only the users of `v1`, so a repository takes it by moving to `v1.1`.
- An image built on another image of this repository follows the same rule in its `FROM`
  line.
- The full version is for a repository that needs a build that cannot change.

## Change an image

1. Edit the folder `images/<name>/`.
2. Raise the version in `images/<name>/version`, by one step that fits the change:
   - patch (`v1.0.0` to `v1.0.1`) for a fix, or for newer base packages with no other
     change;
   - minor (`v1.0.1` to `v1.1.0`) for a new tool or another addition, where nothing that
     worked stops working;
   - major (`v1.1.0` to `v2.0.0`) for a breaking change.

   The pull request fails when a changed image does not have a greater full version than
   it had where the branch started. Versions are compared as numbers, by major, then
   minor, then patch, so `v1.10.0` is greater than `v1.9.0`. A change of the version file
   alone is allowed: that is how an image gets newer base packages.
3. Open a pull request. When it merges, the new version is published and `vX.Y` and `vX`
   move to it. The old full versions stay as they are, and the repositories that use the
   image get the release through the tag they name.

When an image is built on another image of this repository, its `FROM` line must name a tag
of the base that is published (`vX`, `vX.Y` or `vX.Y.Z`), or one that the same pull request
publishes: the version of the base in the change, or the `vX.Y` or `vX` of that version. The
check accepts both, but the build of a pull request can only pull a base that is already
published. To change the base and an image built on it, change the base first and merge
it. The image built on it names the new version in a later pull request when it needs one.

## Build and check on your own machine

To build one image the way the workflow does:

```sh
docker build --build-arg TARGETARCH=amd64 -t go-qemu images/go-qemu
```

Use `arm64` on an arm64 machine. Building the other CPU type on your machine means
emulation and takes many times longer, so leave it to the pull request.

An image with a `prepare.sh` needs it run first, the way the workflow does it:

```sh
sh images/<name>/prepare.sh amd64
```

The scripts are POSIX sh. Check them with what the Build workflow runs:

```sh
for test in scripts/*-test.sh; do sh "${test}"; done
sh scripts/same-files.sh
shellcheck --shell=sh -o all scripts/*.sh
```

The checks that a pull request gets for the versions run on your branch the same way. They
compare your last commit with the point where the branch left `main`, and the second one
asks the registry, so it needs a network:

```sh
sh scripts/check-version-bump.sh "$(git merge-base origin/main HEAD)" HEAD
sh scripts/check-base-versions.sh "$(git merge-base origin/main HEAD)" HEAD
```

## Branches

SpliceFS uses trunk development. There is one long-lived branch, `main`.

- `main` is protected: no direct pushes, no force pushes, no deletion, and CI must pass before
  a merge.
- Every change is a pull request into `main` from its own branch. Name the branch
  `feature/<name>`, `bug/<name>` or anything else that describes the change.
- A pull request merges with one merge commit. Squash and fast-forward merges are off.
- The repository itself is not versioned. Each image has a version of its own, see
  "Versions".

## Standards

- An image holds what the tests need and nothing else. Install with `--no-install-recommends`
  and remove the package lists in the same layer.
- A Dockerfile never contains a credential, a configuration of a real system or a private
  name.
- A change to the workflows keeps every action pinned to a commit hash with the version in a
  comment.

## When images are built

Images are rebuilt only when their folder under `images/` changes, or when somebody starts
the Build workflow by hand from the Actions tab. There is no scheduled rebuild.

- A pull request builds each changed image for each of its CPU types (both, unless the
  image has an `arch` file), runs its smoke test, and publishes nothing. It also checks the
  versions, as described in "Change an image".
- The merge into `main` builds the changed images again and publishes each one as
  `ghcr.io/splicefs/<name>:<version>`, with the version of its `version` file, and moves
  `<name>:vX.Y` and `<name>:vX` to it.
- A manual run of the Build workflow takes an optional image name. Empty means every image.
  A manual run publishes, but never a full version that is already published: that image
  stops with an error and nothing of it is published.
- Each CPU type is built on a runner of that type and the results are joined into one
  tag afterwards. Between those steps the registry holds a tag `<full commit>-<arch>` for
  each CPU type. Do not use those tags.
- An image with a `prepare.sh` is prepared on the runner first, once for each CPU type it
  is built for. A change to such an image, or a manual run, repeats the preparation.
- A change outside `images/` builds nothing.

## What CI checks

| Workflow | What it does |
| --- | --- |
| Build | tests the scripts, checks that the FreeBSD image folders hold the same files, runs ShellCheck, checks the versions of the changed images in a pull request, prepares and builds the changed images for each of their CPU types, and on `main` publishes them under their version and moves their minor and major tags |
| Security | CodeQL on the workflows, the tracked-files check, and dependency review on pull requests |
| Scorecard | OpenSSF Scorecard, published weekly and on every push |

The weekly runs of Security and Scorecard only scan. They build and publish no image.

## Commits and pull requests

- One purpose per commit. The message says what changed and why.
- A pull request targets `main`. CI must pass: Build, CodeQL and dependency review.

## License

By contributing you agree that your contribution is licensed under the [MIT license](LICENSE).
