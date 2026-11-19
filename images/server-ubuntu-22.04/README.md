# server-ubuntu-22.04

Ubuntu 22.04 as a server that is up and running. The SpliceFS deb packages are tested on it:
install, upgrade, remove, and the service running.

The vendor image `ubuntu:22.04` is cut down far below a server: no service manager, no init,
no network tools. This image brings it up to Ubuntu's minimal server install, which is:

- The metapackage `ubuntu-server-minimal` and what it depends on: `systemd` (started as
  process 1, the way a server that has booted runs it), `systemd-sysv`, `udev`, `dbus`,
  `netplan.io`, `cloud-init`, `snapd`, `apparmor`, `lvm2`, `mdadm`, `sudo` and the rest of
  the set. Recommended packages are not installed.
- `ca-certificates`, which every server has.

Three things of the vendor image are changed, because a container image differs from a server
in them: `/usr/sbin/policy-rc.d`, which stops every package from starting its service, is
removed, `/etc/machine-id` is empty, so that every container made from the image
chooses its own machine id when it boots, and the console and terminal login units `console-getty.service`, `getty@.service`,
`serial-getty@.service` and `getty.target` are masked, because a container has no console
or terminal for a login prompt to run on, and a getty started on a missing one dumps core
after the container restarts.

`fuse3` is in the image. Ubuntu's minimal server install brings it in, and the image keeps
what the vendor's set has. A test of the install on this image therefore does not see the
SpliceFS packages pull `fuse3` in.

Boot it and ask the service manager (the flags are explained under "Server images" in the
top-level README):

    docker run -d --name server --privileged --cgroupns=host --tmpfs /run --tmpfs /run/lock --tmpfs /tmp ghcr.io/splicefs/server-ubuntu-22.04:v1
    docker exec server systemctl is-system-running

`test.sh` checks the image: the service manager, the marker package of the set, the
certificates and the empty machine id. `server-setup-deb.sh` is the one step that makes the
image from the vendor image, and it is the same file in the folder of every deb server
image.
