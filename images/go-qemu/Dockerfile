# The major version of go: a minor or patch release of it reaches this image the next time
# this image is built. To move to a newer major version, change the number here and raise
# the version of this image. The go image sets the user, HOME, GOPATH and the caches, and
# this image changes none of them.
FROM ghcr.io/splicefs/go:v1
ARG TARGETARCH

# The source label links the published image to this repository on GitHub.
LABEL org.opencontainers.image.source="https://github.com/SpliceFS/images" \
      org.opencontainers.image.description="The go image plus QEMU for amd64 and arm64 guests, for the SpliceFS machine tests and Linux checks. Runs as a user that is not root." \
      org.opencontainers.image.licenses="MIT"

# The go image runs as a user that is not root, and installing packages needs root, so this
# step is the only one that runs as root. The user is set back below.
USER root

# One layer, so that the package lists are gone from the image. The QEMU system
# emulator comes from a different package on each CPU type, and the arm64 guests need
# the UEFI firmware as well. ${qemu_packages} stays unquoted on purpose: it holds
# several package names. FUSE, curl, xz and zstd are in the go image already. The package
# versions are those of Ubuntu 26.04 on the day of the build, so they are not pinned here.
# hadolint ignore=DL3008
RUN set -eu; \
    case "${TARGETARCH:-}" in \
        amd64) qemu_packages="qemu-system-x86" ;; \
        arm64) qemu_packages="qemu-system-arm qemu-efi-aarch64" ;; \
        *) echo "Unsupported TARGETARCH \"${TARGETARCH:-}\": use amd64 or arm64." >&2; exit 1 ;; \
    esac; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        qemu-utils ${qemu_packages}; \
    rm -rf /var/lib/apt/lists/*

USER build
