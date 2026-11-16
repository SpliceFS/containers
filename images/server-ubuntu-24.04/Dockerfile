FROM ubuntu:24.04

# The source label links the published image to this repository on GitHub.
LABEL org.opencontainers.image.source="https://github.com/SpliceFS/images" \
      org.opencontainers.image.description="Ubuntu 24.04 as a server that is up and running: systemd as process 1 and ca-certificates, nothing else. The system the SpliceFS deb packages are tested on" \
      org.opencontainers.image.licenses="MIT"

# The script is mounted for this one step instead of copied, so no layer of the image
# holds it: the image has nothing of ours in it.
RUN --mount=type=bind,source=server-setup-deb.sh,target=/server-setup.sh \
    sh /server-setup.sh

# The container settings that systemd wants, and that docker run would otherwise be given:
# the variable tells systemd that it runs in a container, and the real-time signal is the
# one that makes it shut down cleanly (the default signal would only kill it).
ENV container=docker
STOPSIGNAL SIGRTMIN+3

# The service manager is process 1, as on a server that has booted.
CMD ["/lib/systemd/systemd"]
