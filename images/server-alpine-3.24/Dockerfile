FROM alpine:3.24

# The source label links the published image to this repository on GitHub.
LABEL org.opencontainers.image.source="https://github.com/SpliceFS/images" \
      org.opencontainers.image.description="Alpine 3.24 as a server that is up and running: the vendor's own minimal install (alpine-base) with OpenRC as the service manager under init, plus ca-certificates. The system the SpliceFS apk packages are tested on" \
      org.opencontainers.image.licenses="MIT"

# The script is mounted for this one step instead of copied, so no layer of the image
# holds it: the image has nothing of ours in it.
RUN --mount=type=bind,source=server-setup-apk.sh,target=/server-setup.sh \
    sh /server-setup.sh

# Alpine starts OpenRC from its init, which is process 1, as on a server that has booted.
# That init powers the machine off on this signal, after OpenRC has stopped the services;
# its default signal, SIGTERM, would reboot it.
STOPSIGNAL SIGUSR2
CMD ["/sbin/init"]
