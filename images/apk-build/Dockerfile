FROM alpine:3.22

# The source label links the published image to this repository on GitHub.
LABEL org.opencontainers.image.source="https://github.com/SpliceFS/images" \
      org.opencontainers.image.description="Alpine Linux 3.22 plus abuild, which builds and signs apk packages and apk repository indexes. Runs as a user that is not root." \
      org.opencontainers.image.licenses="MIT"

# --no-cache keeps the package index out of the image. The package versions are those of
# Alpine 3.22 on the day of the build, so they are not pinned here.
# hadolint ignore=DL3018
RUN apk add --no-cache abuild

# The user that the image runs as. No user holds uid 1000 in the base image. abuild is made
# for a user in the group "abuild", so the user is in it. Its home is /tmp, which every Linux
# system makes writable by all users, so the image opens no folder of its own to everyone.
# The keys that apk trusts are in /etc/apk/keys, which only root may change, so a script
# that runs as a user names its keys folder to apk with --keys-dir.
RUN set -eu; \
    addgroup -g 1000 build; \
    adduser -D -H -u 1000 -G build -h /tmp -s /bin/sh build; \
    addgroup build abuild

# HOME is set here and not left to the user entry, because a container started with a user
# that is not in /etc/passwd (docker run --user 501:20) would get "/" as its home, where it
# cannot write. Every user may write to /tmp.
ENV HOME=/tmp

USER build
