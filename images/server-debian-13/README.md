# server-debian-13

Debian 13 as a server that is up and running. The SpliceFS deb packages are tested on it:
install, upgrade, remove, and the service running.

The vendor image `debian:13` is cut down far below a server: no service manager, no init,
no network tools. This image brings it up to what the Debian installer puts on a minimal
install, which is:

- Every package of priority `required` or `important`, read from the archive when the image
  is built, plus `systemd-sysv`. That is `systemd` (started as process 1, the way a server
  that has booted runs it), `init`, `udev`, `cron`, `iproute2`, `ifupdown`, `logrotate`,
  `kmod`, `procps` and the rest of the set. Recommended packages are not installed, as the
  installer does not install them for its base system.
- `ca-certificates`, which every server has.

Three things of the vendor image are changed, because a container image differs from a server
in them: `/usr/sbin/policy-rc.d`, which stops every package from starting its service, is
removed, `/etc/machine-id` is empty, so that every container made from the image
chooses its own machine id when it boots, and the console and terminal login units `console-getty.service`, `getty@.service`,
`serial-getty@.service` and `getty.target` are masked, because a container has no console
or terminal for a login prompt to run on, and a getty started on a missing one dumps core
after the container restarts.

`fuse3` is not in the image. The SpliceFS packages pull it in themselves when they are
installed, and a test of the install has to see that happen.

Boot it and ask the service manager (the flags are explained under "Server images" in the
top-level README):

    docker run -d --name server --privileged --cgroupns=host --tmpfs /run --tmpfs /run/lock --tmpfs /tmp ghcr.io/splicefs/server-debian-13:v1
    docker exec server systemctl is-system-running

`test.sh` checks the image: the service manager, the marker packages of the set, the
certificates, the empty machine id, and that `fuse3` is absent. `server-setup-deb.sh` is the
one step that makes the image from the vendor image, and it is the same file in the folder
of every deb server image.
