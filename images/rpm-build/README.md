# rpm-build

Rocky Linux 9 (`rockylinux/rockylinux:9`) plus the tools that build and sign rpm packages
and rpm repositories:

- `rpm-build`: `rpmbuild`, which turns a spec file into an rpm package
- `rpm-sign`: `rpmsign`, which signs rpm packages
- `createrepo_c`: writes the index of an rpm repository
- `gnupg2`: GnuPG, which holds the signing key

Used by the package and repository steps for rpm packages of the SpliceFS repositories.
It is not one of the systems that the packages are tested on: those tests start their own
systems.
Pull it with `docker pull ghcr.io/splicefs/rpm-build:<version>`, where the version is the
one line of the file `version` in this folder. `test.sh` checks the tools inside the image
and builds, signs and indexes a small package with a key that it makes itself.

## Who it runs as

The image does not run as root. It starts as the user `build` (uid 1000, home `/tmp`).
Three ways to run it:

```sh
# 1. As the default user.
docker run --rm ghcr.io/splicefs/rpm-build:v1 rpmbuild --version

# 2. As your own user, so that the files that the container writes into a mounted
#    folder belong to you. Any uid and gid work, for example 501:20 on macOS or
#    1001:127 on a GitHub runner. Use "$(id -u):$(id -g)" for yours.
docker run --rm --user "$(id -u):$(id -g)" -v "$PWD":/src -w /src \
    ghcr.io/splicefs/rpm-build:v1 rpmbuild -bb --define "_topdir /tmp/rpm" my.spec

# 3. As root.
docker run --rm --user 0 ghcr.io/splicefs/rpm-build:v1 id
```

A user that is not in `/etc/passwd` works because no setting depends on the user entry:

- `HOME` is set to `/tmp` in the image. Without it Docker would give such a user `/` as its home, where it cannot write.
- `/tmp` is the folder that every Linux system lets all users write to, and only the owner of a file may remove it. The image changes the mode of no folder, so no folder of it is writable by everyone but `/tmp`; `test.sh` checks that. `rpmbuild` keeps its work in `~/rpmbuild`, which is `/tmp/rpmbuild`, unless the caller names another folder with `--define "_topdir ..."`.
- The packages that `rpmbuild` makes list their files as owned by root whichever user builds them.

Things to know:

- The tools are in the image and only root can install packages, so a script that runs here as a user must not call `dnf install`.
- A private key with mode 600 can be read only by the user that owns it, so when the host user owns the key, start the container with `--user "$(id -u):$(id -g)"`.
- Keep the GnuPG home in a folder of the run, for example `GNUPGHOME="$(mktemp -d)"` with mode 700, and name the key with `--define "_gpg_name ..."` and `--define "_gpg_path ..."` to `rpmsign`.
