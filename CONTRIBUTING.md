# Contributing to the SpliceFS containers

This repository holds the definitions of the container images that the SpliceFS tests run
in, and the workflow that builds and publishes them.

## Before you start

Open an issue first for anything larger than a correction, so the approach can be agreed
before work is spent on it.

## Add an image

1. Make a folder `images/<name>/`. The folder name is the image name and must match
   `^[a-z0-9][a-z0-9-]*$`.
2. Put a `Dockerfile` in it. It takes the build argument `TARGETARCH` (`amd64` or `arm64`)
   when the packages differ by CPU type, and fails with a clear message for any other value.
   Set the labels `org.opencontainers.image.source` (this links the published image to this
   repository), `org.opencontainers.image.description` and `org.opencontainers.image.licenses`.
3. Put a short `README.md` in it: what the image contains and which tests use it.
4. Optionally put an executable `test.sh` in it. When it exists, the workflow runs it inside
   the built image and the build fails if it fails.
5. Add the image to the table in the top-level `README.md`.
6. Open a pull request.

## Build and check on your own machine

To build one image the way the workflow does:

```sh
docker build --build-arg TARGETARCH=amd64 -t go-qemu images/go-qemu
```

Use `arm64` on an arm64 machine. Building the other CPU type on your machine means
emulation and takes many times longer, so leave it to the pull request.

The scripts are POSIX sh. Check them with what the Build workflow runs:

```sh
sh scripts/changed-images-test.sh
shellcheck --shell=sh -o all scripts/*.sh
```

## Branches

SpliceFS uses trunk development. There is one long-lived branch, `main`.

- `main` is protected: no direct pushes, no force pushes, no deletion, and CI must pass before
  a merge.
- Every change is a pull request into `main` from its own branch. Name the branch
  `feature/<name>`, `bug/<name>` or anything else that describes the change.
- A pull request merges with one merge commit. Squash and fast-forward merges are off.
- The repository is not versioned. Images are identified by their tags.

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

- A pull request builds each changed image for amd64 and arm64, runs its smoke test, and
  publishes nothing.
- The merge into `main` builds the changed images again and publishes them as
  `ghcr.io/splicefs/<name>:latest` and `ghcr.io/splicefs/<name>:<date>-<short commit>`.
- A manual run of the Build workflow takes an optional image name. Empty means every image.
  A manual run publishes.
- Each CPU type is built on a runner of that type and the two results are joined into one
  tag afterwards. Between those steps the registry holds a tag `<full commit>-<arch>` for
  each CPU type. Do not use those tags.
- A change outside `images/` builds nothing.

## What CI checks

| Workflow | What it does |
| --- | --- |
| Build | tests the script that picks the images, runs ShellCheck, builds the changed images for amd64 and arm64, and on `main` publishes them |
| Security | CodeQL on the workflows, the tracked-files check, and dependency review on pull requests |
| Scorecard | OpenSSF Scorecard, published weekly and on every push |

The weekly runs of Security and Scorecard only scan. They build and publish no image.

## Commits and pull requests

- One purpose per commit. The message says what changed and why.
- A pull request targets `main`. CI must pass: Build, CodeQL and dependency review.

## License

By contributing you agree that your contribution is licensed under the [MIT license](LICENSE).
