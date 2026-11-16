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
one line of the file `version` in this folder. `test.sh` checks the tools inside the image.
