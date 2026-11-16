FROM alpine:3.22

# The source label links the published image to this repository on GitHub.
LABEL org.opencontainers.image.source="https://github.com/SpliceFS/images" \
      org.opencontainers.image.description="Alpine Linux 3.22 plus abuild, which builds and signs apk packages and apk repository indexes" \
      org.opencontainers.image.licenses="MIT"

# --no-cache keeps the package index out of the image. The package versions are those of
# Alpine 3.22 on the day of the build, so they are not pinned here.
# hadolint ignore=DL3018
RUN apk add --no-cache abuild
