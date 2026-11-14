FROM golang:1.27
ARG TARGETARCH

# The source label links the published image to this repository on GitHub.
LABEL org.opencontainers.image.source="https://github.com/SpliceFS/containers" \
      org.opencontainers.image.description="The Go toolchain plus QEMU for amd64 and arm64 guests, FUSE, curl and xz, for the SpliceFS machine tests" \
      org.opencontainers.image.licenses="MIT"

# One layer, so that the package lists are gone from the image. The QEMU system
# emulator comes from a different package on each CPU type, and the arm64 guests need
# the UEFI firmware as well. ${qemu_packages} stays unquoted on purpose: it holds
# several package names. The package versions are those of the Debian release that the
# base image is built on, so they are not pinned here.
# hadolint ignore=DL3008
RUN set -eu; \
    case "${TARGETARCH:-}" in \
        amd64) qemu_packages="qemu-system-x86" ;; \
        arm64) qemu_packages="qemu-system-arm qemu-efi-aarch64" ;; \
        *) echo "Unsupported TARGETARCH \"${TARGETARCH:-}\": use amd64 or arm64." >&2; exit 1 ;; \
    esac; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        qemu-utils fuse3 curl xz-utils ${qemu_packages}; \
    rm -rf /var/lib/apt/lists/*
