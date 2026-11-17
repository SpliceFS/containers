# server-rocky-9

Rocky Linux 9 as a server that is up and running. The SpliceFS rpm packages are tested on
it: install, upgrade, remove, and the service running.

The vendor image `rockylinux/rockylinux:9` is cut down far below a server: no service
manager, a minimal curl and coreutils, no sshd, no firewall. This image brings it up to what
the Rocky Linux installer puts on a "Minimal Install":

- The group `core`, with its mandatory and default packages and the weak dependencies, as
  the installer installs them. That is `systemd` (started as process 1, the way a server that
  has booted runs it), `openssh-server`, `firewalld`, `NetworkManager`, `rsyslog`, `cronie`,
  `sudo`, `dnf` and the rest of the group. `coreutils` and `curl` replace `coreutils-single`
  and `curl-minimal` of the vendor image, because the group asks for the full ones.
- `ca-certificates`, which every server has.

`fuse3` is not in the image. The SpliceFS packages pull it in themselves when they are
installed, and a test of the install has to see that happen.

Two things of the vendor image are changed, because a container image differs from a server
in them: `/etc/machine-id` is empty, so that every container made from the image chooses its
own machine id when it boots (installing systemd fills it in), and nothing else is removed or
replaced except where the set needs it, see below.

Boot it and ask the service manager (the flags are explained under "Server images" in the
top-level README):

    docker run -d --name server --privileged --cgroupns=host --tmpfs /run --tmpfs /run/lock --tmpfs /tmp ghcr.io/splicefs/server-rocky-9:v1
    docker exec server systemctl is-system-running

`test.sh` checks the image: the service manager, marker packages of the set, the
certificates, the empty machine id, and that `fuse3` is absent. `server-setup-rpm.sh` is the
one step that makes the image from the vendor image, and it is the same file in the folder
of every rpm server image.
