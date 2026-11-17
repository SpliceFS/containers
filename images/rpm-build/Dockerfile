FROM rockylinux/rockylinux:9

# The source label links the published image to this repository on GitHub.
LABEL org.opencontainers.image.source="https://github.com/SpliceFS/images" \
      org.opencontainers.image.description="Rocky Linux 9 plus the tools that build and sign rpm packages and rpm repositories: rpmbuild, rpmsign, createrepo_c and GnuPG. Runs as a user that is not root." \
      org.opencontainers.image.licenses="MIT"

# One layer, so that the package metadata is gone from the image. The package versions are
# those of Rocky Linux 9 on the day of the build, so they are not pinned here.
# hadolint ignore=DL3041
RUN dnf install -y --setopt=install_weak_deps=False \
        rpm-build createrepo_c rpm-sign gnupg2; \
    dnf clean all

# The user that the image runs as. No user holds uid 1000 in the base image. HOME is
# world-writable with the sticky bit, like /tmp, so that a container started with any
# other user (docker run --user 501:20, which has no entry in /etc/passwd) can write to
# it too. rpmbuild keeps its work in ~/rpmbuild unless the caller names another folder.
RUN set -eu; \
    groupadd --gid 1000 build; \
    useradd --uid 1000 --gid 1000 --create-home --home-dir /home/build --shell /bin/sh build; \
    chmod 1777 /home/build

# HOME is set here and not left to the user entry, because a user that is not in
# /etc/passwd would get "/" as its home, where it cannot write.
ENV HOME=/home/build

USER build
