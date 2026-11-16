FROM golang:1.27
ARG TARGETARCH
# The release of golangci-lint that the CI of the SpliceFS repositories uses. The workflows
# name it as v2.15 and v2.15.0 is the only release of that line. Change it here together
# with the workflows, and raise the version of this image.
ARG GOLANGCI_LINT_VERSION=2.15.0

# The source label links the published image to this repository on GitHub.
LABEL org.opencontainers.image.source="https://github.com/SpliceFS/images" \
      org.opencontainers.image.description="The Go toolchain plus golangci-lint, ShellCheck, git, make, curl, FUSE, GnuPG, OpenSSL, apt-utils, xz and zstd, for the builds and checks of the SpliceFS repositories" \
      org.opencontainers.image.licenses="MIT"

# One layer, so that the package lists are gone from the image. The package versions are
# those of the Debian release that the base image is built on, so they are not pinned here.
# hadolint ignore=DL3008
RUN set -eu; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        fuse3 curl xz-utils zstd apt-utils gnupg openssl git make shellcheck; \
    rm -rf /var/lib/apt/lists/*

# The official binary for the CPU type of the image, checked against the checksum file that
# the same release publishes. Only the line of the archive is checked, because the file also
# lists the other archives of the release. The download is deleted in the same layer.
RUN set -eu; \
    case "${TARGETARCH:-}" in \
        amd64|arm64) ;; \
        *) echo "Unsupported TARGETARCH \"${TARGETARCH:-}\": use amd64 or arm64." >&2; exit 1 ;; \
    esac; \
    release="https://github.com/golangci/golangci-lint/releases/download/v${GOLANGCI_LINT_VERSION}"; \
    name="golangci-lint-${GOLANGCI_LINT_VERSION}-linux-${TARGETARCH}"; \
    work="$(mktemp -d)"; \
    cd "${work}"; \
    curl -fsSLO "${release}/${name}.tar.gz"; \
    curl -fsSLO "${release}/golangci-lint-${GOLANGCI_LINT_VERSION}-checksums.txt"; \
    awk -v file="${name}.tar.gz" '$2 == file' "golangci-lint-${GOLANGCI_LINT_VERSION}-checksums.txt" | sha256sum -c -; \
    tar -xzf "${name}.tar.gz" -C /usr/local/bin --strip-components=1 "${name}/golangci-lint"; \
    cd /; \
    rm -rf "${work}"
