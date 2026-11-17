# apk-build

Alpine Linux 3.22 (`alpine:3.22`) plus `abuild`, the tool that builds and signs apk
packages and signs the index of an apk repository. The package also brings `abuild-sign`,
`abuild-keygen` and the `apk` tool.

Used by the package and repository steps for apk packages of the SpliceFS repositories.
It is not one of the systems that the packages are tested on: those tests start their own
systems.
Pull it with `docker pull ghcr.io/splicefs/apk-build:<version>`, where the version is the
one line of the file `version` in this folder. `test.sh` checks the tools inside the image
and builds, signs and indexes a small package with a key that it makes itself.

## Who it runs as

The image does not run as root. It starts as the user `build` (uid 1000, home
`/home/build`), a member of the group `abuild`. Three ways to run it:

```sh
# 1. As the default user.
docker run --rm ghcr.io/splicefs/apk-build:v1 apk --version

# 2. As your own user, so that the files that the container writes into a mounted
#    folder belong to you. Any uid and gid work, for example 501:20 on macOS or
#    1001:127 on a GitHub runner. Use "$(id -u):$(id -g)" for yours.
docker run --rm --user "$(id -u):$(id -g)" -v "$PWD":/repo -v "$PWD/keys":/keys:ro -w /repo \
    ghcr.io/splicefs/apk-build:v1 \
    abuild-sign -k /keys/key.rsa -p /keys/key.rsa.pub APKINDEX.tar.gz

# 3. As root. abuild refuses to run as root unless it gets -F.
docker run --rm --user 0 ghcr.io/splicefs/apk-build:v1 id
```

A user that is not in `/etc/passwd` works because no setting depends on the user entry:

- `HOME` is set to `/home/build` in the image. Without it Docker would give such a user `/` as its home.
- `/home/build` has mode 1777: every user may create files there, and only the owner may remove them, like `/tmp`.
- `/etc/apk/keys`, the folder of the public keys that apk trusts, has mode 1777 too, so that a script can add the public key of a repository before `apk index` checks the packages against it.

Name the signing key in the environment or on the command line, because a user that is not
in the image has no `~/.abuild` with a key in it and no membership of the group `abuild`.
Both of these work for every user: `PACKAGER_PRIVKEY=/path/key.rsa abuild -F -q rootpkg` (with
`CARCH` and `REPODEST` set) and `abuild-sign -k /path/key.rsa -p /path/key.rsa.pub INDEX`.
The packages that `abuild` makes list their files as owned by root whichever user builds them.

Things to know:

- The tools are in the image and only root can install packages, so a script that runs here as a user must not call `apk add`.
- A private key with mode 600 can be read only by the user that owns it, so when the host user owns the key, start the container with `--user "$(id -u):$(id -g)"`.
- `abuild-keygen` with no `PACKAGER` and no git name calls the key after `$USER`, which is not set in a container, so the file name starts with a dash. Set `PACKAGER="Name <name@example.org>"` for a readable name.
