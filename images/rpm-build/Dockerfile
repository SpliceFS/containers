FROM rockylinux/rockylinux:9

# The source label links the published image to this repository on GitHub.
LABEL org.opencontainers.image.source="https://github.com/SpliceFS/images" \
      org.opencontainers.image.description="Rocky Linux 9 plus the tools that build and sign rpm packages and rpm repositories: rpmbuild, rpmsign, createrepo_c and GnuPG" \
      org.opencontainers.image.licenses="MIT"

# One layer, so that the package metadata is gone from the image. The package versions are
# those of Rocky Linux 9 on the day of the build, so they are not pinned here.
# hadolint ignore=DL3041
RUN dnf install -y --setopt=install_weak_deps=False \
        rpm-build createrepo_c rpm-sign gnupg2; \
    dnf clean all
