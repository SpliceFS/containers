FROM ubuntu:26.04
ARG TARGETARCH
# The Go release of this image: the newest 1.27 patch release, with the checksums that
# https://go.dev/dl/?mode=json lists for its linux archives. To move to another release,
# replace all three values together with the ones of the new release and raise the
# version of this image.
ARG GO_VERSION=1.27.4
ARG GO_SHA256_AMD64=7226736c2339719cda28fbf3a54d71aa63bcefe376e98cef00034268dab24840
ARG GO_SHA256_ARM64=3392582988a273a87ab5043ee1b2c9c17a2c3c00580bf9326c47a2e0aaaeac92
# The release of golangci-lint that the CI of the SpliceFS repositories uses. The workflows
# name it as v2.15 and v2.15.0 is the only release of that line. Change it here together
# with the workflows, and raise the version of this image.
ARG GOLANGCI_LINT_VERSION=2.15.0

# The source label links the published image to this repository on GitHub.
LABEL org.opencontainers.image.source="https://github.com/SpliceFS/images" \
      org.opencontainers.image.description="Ubuntu 26.04 with the Go toolchain, a C compiler for cgo and the race detector, golangci-lint, ShellCheck, git, make, curl, FUSE, GnuPG, OpenSSL, apt-utils, xz and zstd, for the builds and checks of the SpliceFS repositories. Runs as a user that is not root." \
      org.opencontainers.image.licenses="MIT"

# One layer, so that the package lists are gone from the image. gcc and libc6-dev are what
# cgo and the race detector need. The package versions are those of Ubuntu 26.04 on the
# day of the build, so they are not pinned here.
# hadolint ignore=DL3008
RUN set -eu; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates fuse3 curl xz-utils zstd apt-utils gnupg openssl git make shellcheck \
        gcc libc6-dev; \
    rm -rf /var/lib/apt/lists/*

# The official archive for the CPU type of the image, checked against the checksum above.
# A different checksum stops the build before anything is extracted. The download is
# deleted in the same layer.
RUN set -eu; \
    case "${TARGETARCH:-}" in \
        amd64) sha256="${GO_SHA256_AMD64}" ;; \
        arm64) sha256="${GO_SHA256_ARM64}" ;; \
        *) echo "Unsupported TARGETARCH \"${TARGETARCH:-}\": use amd64 or arm64." >&2; exit 1 ;; \
    esac; \
    name="go${GO_VERSION}.linux-${TARGETARCH}.tar.gz"; \
    work="$(mktemp -d)"; \
    cd "${work}"; \
    curl -fsSLO --proto "=https" --proto-redir "=https" "https://go.dev/dl/${name}"; \
    echo "${sha256}  ${name}" | sha256sum -c -; \
    tar -xzf "${name}" -C /usr/local; \
    cd /; \
    rm -rf "${work}"

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
    curl -fsSLO --proto "=https" --proto-redir "=https" "${release}/${name}.tar.gz"; \
    curl -fsSLO --proto "=https" --proto-redir "=https" "${release}/golangci-lint-${GOLANGCI_LINT_VERSION}-checksums.txt"; \
    awk -v file="${name}.tar.gz" '$2 == file' "golangci-lint-${GOLANGCI_LINT_VERSION}-checksums.txt" | sha256sum -c -; \
    tar -xzf "${name}.tar.gz" -C /usr/local/bin --strip-components=1 "${name}/golangci-lint"; \
    cd /; \
    rm -rf "${work}"

# The user that the image runs as, and the folders that Go and the tools write to. The
# base image has a user "ubuntu" that holds uid 1000, so it goes first. The folders are
# world-writable with the sticky bit, like /tmp, so that a container started with any
# other user (docker run --user 501:20, which has no entry in /etc/passwd) can write to
# them too. A named volume mounted at /go/pkg/mod or /go/cache copies the mode of the
# folder when Docker creates it, so it is writable by any user as well.
RUN set -eu; \
    userdel --remove ubuntu; \
    groupadd --gid 1000 build; \
    useradd --uid 1000 --gid 1000 --create-home --home-dir /home/build --shell /bin/sh build; \
    mkdir -p /go/bin /go/pkg/mod /go/cache; \
    chmod 1777 /home/build /go/bin /go/pkg/mod /go/cache

# HOME is set here and not left to the user entry, because a user that is not in
# /etc/passwd would get "/" as its home, where it cannot write.
ENV GOPATH=/go \
    GOCACHE=/go/cache \
    HOME=/home/build \
    PATH=/usr/local/go/bin:/go/bin:${PATH}

USER build
