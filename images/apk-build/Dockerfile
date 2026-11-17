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
# for a user in the group "abuild", so the user is in it. HOME is world-writable with the
# sticky bit, like /tmp, so that a container started with any other user (docker run
# --user 501:20, which has no entry in /etc/passwd and no group) can write to it too. The
# folder of the keys that apk trusts is the same, because the repository script adds the
# public key of a repository there before it builds the index: apk checks each package
# against the keys in that folder.
RUN set -eu; \
    addgroup -g 1000 build; \
    adduser -D -u 1000 -G build -h /home/build -s /bin/sh build; \
    addgroup build abuild; \
    chmod 1777 /home/build /etc/apk/keys

# HOME is set here and not left to the user entry, because a user that is not in
# /etc/passwd would get "/" as its home, where it cannot write.
ENV HOME=/home/build

USER build
